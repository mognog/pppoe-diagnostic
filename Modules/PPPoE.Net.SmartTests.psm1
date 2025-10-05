# PPPoE.Net.SmartTests.psm1 - Intelligent test selection and instability detection

Set-StrictMode -Version 3.0

function Test-ICMPAvailability {
  <#
  .SYNOPSIS
  Quick test to determine if ICMP is functional (not blocked by firewall)
  .DESCRIPTION
  Performs a quick ICMP test and TCP fallback to determine if ICMP responses work.
  If ICMP is blocked but TCP works, returns status indicating to skip ICMP tests.
  #>
  param(
    [string]$TestIP = '1.1.1.1',
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Testing ICMP availability (quick firewall check)..."
  
  # Try 3 quick ICMP pings
  $icmpSuccess = 0
  for ($i = 1; $i -le 3; $i++) {
    try {
      $ping = Test-Connection -TargetName $TestIP -Count 1 -TimeoutSeconds 1 -ErrorAction Stop
      if ($ping) { $icmpSuccess++ }
    } catch {
      # Failed
    }
  }
  
  # Test TCP as fallback
  & $WriteLog "Testing TCP connectivity as fallback..."
  $tcpSuccess = $false
  try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $tcpClient.Connect($TestIP, 443)
    $tcpSuccess = $tcpClient.Connected
    $tcpClient.Close()
  } catch {
    # TCP also failed
  }
  
  # Determine status
  if ($icmpSuccess -ge 2) {
    & $WriteLog "ICMP Status: AVAILABLE (firewall allows ICMP)"
    return @{ 
      Status = "AVAILABLE"
      ICMPWorks = $true
      Recommendation = "Run full ICMP-based tests"
    }
  } elseif ($tcpSuccess) {
    & $WriteLog "ICMP Status: BLOCKED (firewall/ISP blocks ICMP, but TCP works)"
    & $WriteLog "  Recommendation: Skip ICMP ping tests, use TCP-based diagnostics"
    return @{ 
      Status = "BLOCKED"
      ICMPWorks = $false
      TCPWorks = $true
      Recommendation = "Skip ICMP tests, use TCP alternatives"
    }
  } else {
    & $WriteLog "ICMP Status: CONNECTIVITY_ISSUE (both ICMP and TCP failed)"
    return @{ 
      Status = "CONNECTIVITY_ISSUE"
      ICMPWorks = $false
      TCPWorks = $false
      Recommendation = "Major connectivity problem - investigate further"
    }
  }
}

function Test-ConnectionStabilityPattern {
  <#
  .SYNOPSIS
  Detects patterns in connection failures to diagnose instability
  .DESCRIPTION
  Runs tests over time to detect:
  - Intermittent drops
  - Periodic failures
  - Progressive degradation
  - Random packet loss vs systematic issues
  #>
  param(
    [string]$TestIP = '1.1.1.1',
    [int]$DurationSeconds = 60,
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Running connection stability pattern analysis ($DurationSeconds seconds)..."
  & $WriteLog "This will detect intermittent drops, periodic failures, and patterns..."
  
  $results = @()
  $testCount = 0
  $startTime = Get-Date
  
  while (((Get-Date) - $startTime).TotalSeconds -lt $DurationSeconds) {
    $testCount++
    $timestamp = Get-Date
    
    # Test TCP connection (more reliable than ICMP)
    $tcpSuccess = $false
    $latency = $null
    
    try {
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $tcpClient = New-Object System.Net.Sockets.TcpClient
      $tcpClient.Connect($TestIP, 443)
      $sw.Stop()
      
      $tcpSuccess = $tcpClient.Connected
      $latency = $sw.ElapsedMilliseconds
      $tcpClient.Close()
    } catch {
      # Failed
    }
    
    $results += @{
      Test = $testCount
      Timestamp = $timestamp
      Success = $tcpSuccess
      Latency = $latency
      SecondsSinceStart = [Math]::Round(($timestamp - $startTime).TotalSeconds, 1)
    }
    
    if ($testCount % 10 -eq 0) {
      $successRate = [Math]::Round((($results | Where-Object { $_.Success }).Count / $testCount) * 100, 1)
      & $WriteLog "  Progress: $testCount tests, $successRate% success rate so far..."
    }
    
    Start-Sleep -Milliseconds 500
  }
  
  # Analyze patterns
  $totalTests = $results.Count
  $successfulResults = $results | Where-Object { $_.Success }
  $failedResults = $results | Where-Object { -not $_.Success }
  
  $successCount = if ($successfulResults) { $successfulResults.Count } else { 0 }
  $failureCount = if ($failedResults) { $failedResults.Count } else { 0 }
  $successRate = [Math]::Round(($successCount / $totalTests) * 100, 1)
  
  # Detect failure patterns
  $patterns = @()
  
  # Check for consecutive failures (drops)
  $maxConsecutiveFailures = 0
  $currentConsecutive = 0
  $dropEvents = 0
  
  foreach ($result in $results) {
    if (-not $result.Success) {
      $currentConsecutive++
      if ($currentConsecutive -gt $maxConsecutiveFailures) {
        $maxConsecutiveFailures = $currentConsecutive
      }
    } else {
      if ($currentConsecutive -gt 0) {
        $dropEvents++
      }
      $currentConsecutive = 0
    }
  }
  
  # Classify stability
  $stabilityClass = "UNKNOWN"
  $diagnosis = ""
  
  if ($successRate -eq 100) {
    $stabilityClass = "STABLE"
    $diagnosis = "Connection is perfectly stable over $DurationSeconds seconds"
  } elseif ($successRate -ge 95) {
    $stabilityClass = "MOSTLY_STABLE"
    $diagnosis = "Minor intermittent issues ($failureCount failures in $totalTests tests)"
  } elseif ($maxConsecutiveFailures -ge 5) {
    $stabilityClass = "INTERMITTENT_DROPS"
    $diagnosis = "Connection experiencing drops (longest drop: $maxConsecutiveFailures consecutive failures)"
    $patterns += "Detected $dropEvents separate drop events"
  } elseif ($failureCount -gt ($totalTests * 0.3)) {
    $stabilityClass = "SEVERE_INSTABILITY"
    $diagnosis = "Severe connection instability ($successRate% success rate)"
  } else {
    $stabilityClass = "UNSTABLE"
    $diagnosis = "Connection is unstable with sporadic failures"
  }
  
  # Calculate latency statistics for successful tests
  if ($successfulResults -and $successfulResults.Count -gt 0) {
    $latencies = $successfulResults | ForEach-Object { $_.Latency } | Where-Object { $_ -ne $null }
    if ($latencies -and $latencies.Count -gt 0) {
      $avgLatency = [Math]::Round(($latencies | Measure-Object -Average).Average, 1)
      $minLatency = ($latencies | Measure-Object -Minimum).Minimum
      $maxLatency = ($latencies | Measure-Object -Maximum).Maximum
      $jitter = $maxLatency - $minLatency
    } else {
      $avgLatency = 0; $minLatency = 0; $maxLatency = 0; $jitter = 0
    }
  } else {
    $avgLatency = 0; $minLatency = 0; $maxLatency = 0; $jitter = 0
  }
  
  & $WriteLog "Stability Analysis Complete:"
  & $WriteLog "  Classification: $stabilityClass"
  & $WriteLog "  Success Rate: $successRate% ($successCount/$totalTests)"
  & $WriteLog "  Drop Events: $dropEvents"
  & $WriteLog "  Longest Drop: $maxConsecutiveFailures consecutive failures"
  & $WriteLog "  Latency: avg ${avgLatency}ms, range ${minLatency}-${maxLatency}ms, jitter ${jitter}ms"
  & $WriteLog "  Diagnosis: $diagnosis"
  
  return @{
    StabilityClass = $stabilityClass
    SuccessRate = $successRate
    TotalTests = $totalTests
    SuccessfulTests = $successCount
    FailedTests = $failureCount
    DropEvents = $dropEvents
    MaxConsecutiveFailures = $maxConsecutiveFailures
    AvgLatency = $avgLatency
    MinLatency = $minLatency
    MaxLatency = $maxLatency
    Jitter = $jitter
    Diagnosis = $diagnosis
    Patterns = $patterns
    Results = $results
  }
}

function Test-DNSStability {
  <#
  .SYNOPSIS
  Tests DNS resolution stability over multiple queries
  .DESCRIPTION
  Performs repeated DNS queries to detect:
  - DNS timeout issues
  - Inconsistent responses
  - DNS server failures
  #>
  param(
    [string]$TestDomain = 'google.com',
    [int]$QueryCount = 20,
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Testing DNS resolution stability ($QueryCount queries to $TestDomain)..."
  
  $results = @()
  $dnsServers = @('8.8.8.8', '1.1.1.1', '9.9.9.9')
  
  for ($i = 1; $i -le $QueryCount; $i++) {
    # Rotate through DNS servers
    $dnsServer = $dnsServers[($i - 1) % $dnsServers.Count]
    
    $success = $false
    $responseTime = $null
    $resolvedIP = $null
    
    try {
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $resolution = Resolve-DnsName -Name $TestDomain -Server $dnsServer -Type A -ErrorAction Stop -DnsOnly
      $sw.Stop()
      
      if ($resolution) {
        $success = $true
        $responseTime = $sw.ElapsedMilliseconds
        $resolvedIP = $resolution[0].IPAddress
      }
    } catch {
      # DNS query failed
    }
    
    $results += @{
      Query = $i
      DNSServer = $dnsServer
      Success = $success
      ResponseTime = $responseTime
      ResolvedIP = $resolvedIP
    }
    
    if ($i % 5 -eq 0) {
      $successCount = ($results | Where-Object { $_.Success }).Count
      & $WriteLog "  Progress: $successCount/$i queries successful..."
    }
    
    Start-Sleep -Milliseconds 200
  }
  
  # Analyze results
  $successfulResults = $results | Where-Object { $_.Success }
  $successCount = if ($successfulResults) { $successfulResults.Count } else { 0 }
  $successRate = [Math]::Round(($successCount / $QueryCount) * 100, 1)
  
  # Check response times
  if ($successfulResults -and $successfulResults.Count -gt 0) {
    $responseTimes = $successfulResults | ForEach-Object { $_.ResponseTime } | Where-Object { $_ -ne $null }
    if ($responseTimes -and $responseTimes.Count -gt 0) {
      $avgResponseTime = [Math]::Round(($responseTimes | Measure-Object -Average).Average, 1)
      $maxResponseTime = ($responseTimes | Measure-Object -Maximum).Maximum
    } else {
      $avgResponseTime = 0; $maxResponseTime = 0
    }
  } else {
    $avgResponseTime = 0; $maxResponseTime = 0
  }
  
  & $WriteLog "DNS Stability: $successRate% success rate, avg ${avgResponseTime}ms response time"
  
  return @{
    SuccessRate = $successRate
    SuccessfulQueries = $successCount
    TotalQueries = $QueryCount
    AvgResponseTime = $avgResponseTime
    MaxResponseTime = $maxResponseTime
    Results = $results
  }
}

function Test-TCPConnectionResetDetection {
  <#
  .SYNOPSIS
  Detects TCP connection reset patterns and detailed failure modes
  .DESCRIPTION
  Monitors for RST (reset) packets and connection termination patterns to identify:
  - Clean FIN/ACK closure (normal)
  - RST from remote (connection reset)
  - Timeout (no response)
  - Local error conditions
  This test is specifically designed to detect the 4.1-second connection drop pattern.
  #>
  param(
    [string]$TestHost = 'netflix.com',
    [int]$TestPort = 443,
    [int]$TestDurationSeconds = 30,
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Testing TCP connection reset detection ($TestDurationSeconds seconds)..."
  & $WriteLog "This test will detect RST packets, timeouts, and connection termination patterns"
  & $WriteLog "Target: $TestHost`:$TestPort"
  
  $results = @()
  $startTime = Get-Date
  $endTime = $startTime.AddSeconds($TestDurationSeconds)
  $testCount = 0
  
  while ((Get-Date) -lt $endTime) {
    $testCount++
    $currentTime = Get-Date
    $elapsedSeconds = [Math]::Round(($currentTime - $startTime).TotalSeconds, 1)
    
    & $WriteLog "Connection test $testCount at ${elapsedSeconds}s..."
    
    $connectionResult = @{
      TestNumber = $testCount
      Timestamp = $currentTime
      ElapsedSeconds = $elapsedSeconds
      Host = $TestHost
      Port = $TestPort
      ConnectionEstablished = $false
      ConnectionDuration = $null
      TerminationType = $null
      ErrorCode = $null
      SocketError = $null
      RemoteReset = $false
      LocalReset = $false
      TimeoutOccurred = $false
      CleanClose = $false
      DetailedError = $null
    }
    
    try {
      # Create TCP client with detailed error handling
      $tcpClient = New-Object System.Net.Sockets.TcpClient
      $tcpClient.ReceiveTimeout = 5000
      $tcpClient.SendTimeout = 5000
      
      # Establish connection with timing
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $tcpClient.Connect($TestHost, $TestPort)
      $connectionTime = $sw.ElapsedMilliseconds
      
      if ($tcpClient.Connected) {
        $connectionResult.ConnectionEstablished = $true
        & $WriteLog "  Connection established: ${connectionTime}ms"
        
        # Monitor connection for specific duration to detect 4.1-second pattern
        $monitorDuration = 6  # Monitor for 6 seconds to catch 4.1s drops
        $monitorStart = Get-Date
        $monitorEnd = $monitorStart.AddSeconds($monitorDuration)
        
        $connectionStable = $true
        $disconnectionTime = $null
        
        while ((Get-Date) -lt $monitorEnd -and $connectionStable) {
          try {
            # Test connection health by attempting to read
            $stream = $tcpClient.GetStream()
            $stream.ReadTimeout = 1000
            
            # Send minimal HTTP request to keep connection alive
            $request = "HEAD / HTTP/1.1`r`nHost: $TestHost`r`nConnection: close`r`n`r`n"
            $requestBytes = [System.Text.Encoding]::ASCII.GetBytes($request)
            $stream.Write($requestBytes, 0, $requestBytes.Length)
            
            # Try to read response
            $buffer = New-Object byte[] 1024
            $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
            
            $currentElapsed = [Math]::Round(((Get-Date) - $monitorStart).TotalSeconds, 1)
            & $WriteLog "    [$currentElapsed s] Connection healthy (${bytesRead} bytes received)"
            
          } catch {
            $connectionStable = $false
            $disconnectionTime = [Math]::Round(((Get-Date) - $monitorStart).TotalSeconds, 1)
            $errorException = $_.Exception
            
            & $WriteLog "    [$disconnectionTime s] Connection lost: $($errorException.Message)"
            
            # Analyze error type
            if ($errorException -is [System.Net.Sockets.SocketException]) {
              $socketError = $errorException.SocketErrorCode
              $connectionResult.SocketError = $socketError.ToString()
              $connectionResult.ErrorCode = $errorException.ErrorCode
              
              # Detect specific error patterns
              switch ($socketError) {
                'ConnectionReset' {
                  $connectionResult.RemoteReset = $true
                  $connectionResult.TerminationType = "REMOTE_RESET"
                  & $WriteLog "    Error Analysis: REMOTE RESET (RST packet received)"
                }
                'ConnectionAborted' {
                  $connectionResult.LocalReset = $true
                  $connectionResult.TerminationType = "LOCAL_ABORT"
                  & $WriteLog "    Error Analysis: LOCAL ABORT"
                }
                'TimedOut' {
                  $connectionResult.TimeoutOccurred = $true
                  $connectionResult.TerminationType = "TIMEOUT"
                  & $WriteLog "    Error Analysis: CONNECTION TIMEOUT"
                }
                'ConnectionRefused' {
                  $connectionResult.TerminationType = "CONNECTION_REFUSED"
                  & $WriteLog "    Error Analysis: CONNECTION REFUSED"
                }
                'HostUnreachable' {
                  $connectionResult.TerminationType = "HOST_UNREACHABLE"
                  & $WriteLog "    Error Analysis: HOST UNREACHABLE"
                }
                default {
                  $connectionResult.TerminationType = "SOCKET_ERROR"
                  & $WriteLog "    Error Analysis: SOCKET ERROR - $socketError"
                }
              }
            } else {
              $connectionResult.TerminationType = "GENERAL_ERROR"
              & $WriteLog "    Error Analysis: GENERAL ERROR"
            }
            
            $connectionResult.DetailedError = $errorException.Message
          }
        }
        
        # Close connection cleanly if still connected
        if ($tcpClient.Connected) {
          try {
            $tcpClient.Close()
            $connectionResult.CleanClose = $true
            $connectionResult.TerminationType = "CLEAN_CLOSE"
            $connectionResult.ConnectionDuration = $monitorDuration
            & $WriteLog "  Connection closed cleanly after ${monitorDuration}s"
          } catch {
            $connectionResult.DetailedError = "Error during close: $($_.Exception.Message)"
          }
        } else {
          $connectionResult.ConnectionDuration = if ($disconnectionTime) { $disconnectionTime } else { $monitorDuration }
        }
        
      } else {
        $connectionResult.TerminationType = "CONNECTION_FAILED"
        & $WriteLog "  Failed to establish connection"
      }
      
    } catch {
      $errorException = $_.Exception
      $connectionResult.TerminationType = "CONNECTION_EXCEPTION"
      $connectionResult.DetailedError = $errorException.Message
      
      if ($errorException -is [System.Net.Sockets.SocketException]) {
        $connectionResult.SocketError = $errorException.SocketErrorCode.ToString()
        $connectionResult.ErrorCode = $errorException.ErrorCode
      }
      
      & $WriteLog "  Connection exception: $($errorException.Message)"
    }
    
    $results += $connectionResult
    
    # Analyze patterns in real-time
    if ($testCount -ge 3) {
      $recentResults = $results | Select-Object -Last 3
      $resetCount = ($recentResults | Where-Object { $_.RemoteReset -eq $true }).Count
      $timeoutCount = ($recentResults | Where-Object { $_.TimeoutOccurred -eq $true }).Count
      $cleanCount = ($recentResults | Where-Object { $_.CleanClose -eq $true }).Count
      
      if ($resetCount -gt 0) {
        & $WriteLog "  PATTERN DETECTED: $resetCount/$testCount recent connections received RST packets"
      }
      if ($timeoutCount -gt 0) {
        & $WriteLog "  PATTERN DETECTED: $timeoutCount/$testCount recent connections timed out"
      }
      if ($cleanCount -eq $testCount) {
        & $WriteLog "  PATTERN: All recent connections closed cleanly"
      }
    }
    
    Start-Sleep -Seconds 2
  }
  
  # Comprehensive analysis
  & $WriteLog "TCP Connection Reset Detection Analysis:"
  
  $totalTests = $results.Count
  $establishedConnections = $results | Where-Object { $_.ConnectionEstablished -eq $true }
  $remoteResets = $results | Where-Object { $_.RemoteReset -eq $true }
  $timeouts = $results | Where-Object { $_.TimeoutOccurred -eq $true }
  $cleanCloses = $results | Where-Object { $_.CleanClose -eq $true }
  # $localResets = $results | Where-Object { $_.LocalReset -eq $true }  # Not currently used in analysis
  
  $establishmentRate = [Math]::Round(($establishedConnections.Count / $totalTests) * 100, 1)
  $resetRate = [Math]::Round(($remoteResets.Count / $totalTests) * 100, 1)
  $timeoutRate = [Math]::Round(($timeouts.Count / $totalTests) * 100, 1)
  $cleanCloseRate = [Math]::Round(($cleanCloses.Count / $totalTests) * 100, 1)
  
  & $WriteLog "  Total tests: $totalTests"
  & $WriteLog "  Connection establishment rate: $establishmentRate%"
  & $WriteLog "  Remote reset rate: $resetRate%"
  & $WriteLog "  Timeout rate: $timeoutRate%"
  & $WriteLog "  Clean close rate: $cleanCloseRate%"
  
  # Detect 4.1-second pattern
  $fourSecondDrops = $results | Where-Object { 
    $_.ConnectionDuration -and $_.ConnectionDuration -ge 3.5 -and $_.ConnectionDuration -le 4.5 -and -not $_.CleanClose 
  }
  
  if ($fourSecondDrops.Count -gt 0) {
    $fourSecondRate = [Math]::Round(($fourSecondDrops.Count / $totalTests) * 100, 1)
    & $WriteLog "  *** 4.1-SECOND DROP PATTERN DETECTED: $fourSecondRate% of connections drop around 4 seconds ***"
    & $WriteLog "  This suggests CGNAT connection tracking timeout or ISP rate limiting"
    
    foreach ($drop in $fourSecondDrops) {
      & $WriteLog "    Test $($drop.TestNumber): Dropped at $($drop.ConnectionDuration)s - $($drop.TerminationType)"
    }
  }
  
  # Analyze socket error patterns
  $socketErrors = $results | Where-Object { $_.SocketError } | Group-Object SocketError
  if ($socketErrors.Count -gt 0) {
    & $WriteLog "  Socket Error Patterns:"
    foreach ($errorGroup in $socketErrors) {
      & $WriteLog "    $($errorGroup.Name): $($errorGroup.Count) occurrences"
    }
  }
  
  # Determine diagnosis
  $diagnosis = ""
  if ($resetRate -gt 50) {
    $diagnosis = "SEVERE_RESET_PATTERN"
    & $WriteLog "  DIAGNOSIS: Severe RST packet pattern - ISP or CGNAT is actively resetting connections"
    & $WriteLog "  IMPACT: Streaming services will frequently disconnect with 'connection lost' errors"
    & $WriteLog "  RECOMMENDATION: Contact ISP about CGNAT configuration or connection tracking issues"
  } elseif ($fourSecondDrops.Count -gt ($totalTests * 0.3)) {
    $diagnosis = "FOUR_SECOND_TIMEOUT_PATTERN"
    & $WriteLog "  DIAGNOSIS: Consistent 4.1-second connection timeout pattern detected"
    & $WriteLog "  IMPACT: Netflix/Twitch will drop at exactly 4.1 seconds - this is a configuration timeout"
    & $WriteLog "  RECOMMENDATION: ISP has misconfigured connection tracking timeout - escalate to technical support"
  } elseif ($timeoutRate -gt 30) {
    $diagnosis = "HIGH_TIMEOUT_RATE"
    & $WriteLog "  DIAGNOSIS: High connection timeout rate - network path or routing issues"
    & $WriteLog "  IMPACT: Apps will show 'connection timeout' errors frequently"
    & $WriteLog "  RECOMMENDATION: Check network path stability and routing configuration"
  } elseif ($establishmentRate -lt 70) {
    $diagnosis = "CONNECTION_ESTABLISHMENT_ISSUES"
    & $WriteLog "  DIAGNOSIS: Connection establishment problems - firewall or network blocking"
    & $WriteLog "  IMPACT: Apps will fail to connect entirely"
    & $WriteLog "  RECOMMENDATION: Check firewall settings and network connectivity"
  } else {
    $diagnosis = "CONNECTION_STABILITY_OK"
    & $WriteLog "  DIAGNOSIS: Connection stability is acceptable"
    & $WriteLog "  IMPACT: Connection issues are not the primary cause of streaming problems"
    & $WriteLog "  RECOMMENDATION: Investigate other factors (DNS, bandwidth, etc.)"
  }
  
  return @{
    TotalTests = $totalTests
    EstablishmentRate = $establishmentRate
    ResetRate = $resetRate
    TimeoutRate = $timeoutRate
    CleanCloseRate = $cleanCloseRate
    FourSecondDrops = $fourSecondDrops.Count
    FourSecondRate = if ($totalTests -gt 0) { [Math]::Round(($fourSecondDrops.Count / $totalTests) * 100, 1) } else { 0 }
    SocketErrorPatterns = $socketErrors
    Diagnosis = $diagnosis
    Results = $results
  }
}

function Test-TCPConnectionResetDetectionQuick {
  <#
  .SYNOPSIS
  Quick TCP connection reset detection for diagnostic workflow
  .DESCRIPTION
  Optimized version that runs 5 connection tests in ~15 seconds to detect
  the 4.1-second connection drop pattern without taking too long.
  #>
  param(
    [string]$TestHost = 'netflix.com',
    [int]$TestPort = 443,
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Quick TCP connection reset detection (5 tests, ~15 seconds)..."
  & $WriteLog "This test will detect RST packets and 4.1-second connection drop patterns"
  & $WriteLog "Target: $TestHost`:$TestPort"
  
  $results = @()
  $testCount = 0
  $fourSecondDrops = 0
  $remoteResets = 0
  $timeouts = 0
  $cleanCloses = 0
  
  for ($i = 1; $i -le 5; $i++) {
    $testCount++
    $currentTime = Get-Date
    
    & $WriteLog "Connection test $testCount/5..."
    
    $connectionResult = @{
      TestNumber = $testCount
      Timestamp = $currentTime
      Host = $TestHost
      Port = $TestPort
      ConnectionEstablished = $false
      ConnectionDuration = $null
      TerminationType = $null
      ErrorCode = $null
      SocketError = $null
      RemoteReset = $false
      LocalReset = $false
      TimeoutOccurred = $false
      CleanClose = $false
      DetailedError = $null
    }
    
    try {
      # Create TCP client with detailed error handling
      $tcpClient = New-Object System.Net.Sockets.TcpClient
      $tcpClient.ReceiveTimeout = 8000  # 8 second timeout to catch 4.1s drops
      $tcpClient.SendTimeout = 8000
      
      # Establish connection
      $tcpClient.Connect($TestHost, $TestPort)
      
      if ($tcpClient.Connected) {
        $connectionResult.ConnectionEstablished = $true
        
        # Monitor connection for 6 seconds to catch 4.1s drops
        $monitorDuration = 6
        $monitorStart = Get-Date
        $monitorEnd = $monitorStart.AddSeconds($monitorDuration)
        
        $connectionStable = $true
        $disconnectionTime = $null
        
        while ((Get-Date) -lt $monitorEnd -and $connectionStable) {
          try {
            # Test connection health
            $stream = $tcpClient.GetStream()
            $stream.ReadTimeout = 1000
            
            # Send minimal HTTP request
            $request = "HEAD / HTTP/1.1`r`nHost: $TestHost`r`nConnection: close`r`n`r`n"
            $requestBytes = [System.Text.Encoding]::ASCII.GetBytes($request)
            $stream.Write($requestBytes, 0, $requestBytes.Length)
            
            # Try to read response (simplified for quick version)
            # $buffer = New-Object byte[] 1024  # Not used in quick version
            # $bytesRead = $stream.Read($buffer, 0, $buffer.Length)  # Not used in quick version
            
          } catch {
            $connectionStable = $false
            $disconnectionTime = [Math]::Round(((Get-Date) - $monitorStart).TotalSeconds, 1)
            $errorException = $_.Exception
            
            # Analyze error type
            if ($errorException -is [System.Net.Sockets.SocketException]) {
              $socketError = $errorException.SocketErrorCode
              $connectionResult.SocketError = $socketError.ToString()
              $connectionResult.ErrorCode = $errorException.ErrorCode
              
              # Detect specific error patterns
              switch ($socketError) {
                'ConnectionReset' {
                  $connectionResult.RemoteReset = $true
                  $connectionResult.TerminationType = "REMOTE_RESET"
                  $remoteResets++
                }
                'ConnectionAborted' {
                  $connectionResult.LocalReset = $true
                  $connectionResult.TerminationType = "LOCAL_ABORT"
                }
                'TimedOut' {
                  $connectionResult.TimeoutOccurred = $true
                  $connectionResult.TerminationType = "TIMEOUT"
                  $timeouts++
                }
                'ConnectionRefused' {
                  $connectionResult.TerminationType = "CONNECTION_REFUSED"
                }
                'HostUnreachable' {
                  $connectionResult.TerminationType = "HOST_UNREACHABLE"
                }
                default {
                  $connectionResult.TerminationType = "SOCKET_ERROR"
                }
              }
            } else {
              $connectionResult.TerminationType = "GENERAL_ERROR"
            }
            
            $connectionResult.DetailedError = $errorException.Message
          }
        }
        
        # Close connection cleanly if still connected
        if ($tcpClient.Connected) {
          try {
            $tcpClient.Close()
            $connectionResult.CleanClose = $true
            $connectionResult.TerminationType = "CLEAN_CLOSE"
            $connectionResult.ConnectionDuration = $monitorDuration
            $cleanCloses++
          } catch {
            $connectionResult.DetailedError = "Error during close: $($_.Exception.Message)"
          }
        } else {
          $connectionResult.ConnectionDuration = if ($disconnectionTime) { $disconnectionTime } else { $monitorDuration }
          
          # Check for 4.1-second pattern
          if ($disconnectionTime -and $disconnectionTime -ge 3.5 -and $disconnectionTime -le 4.5) {
            $fourSecondDrops++
          }
        }
        
      } else {
        $connectionResult.TerminationType = "CONNECTION_FAILED"
      }
      
    } catch {
      $errorException = $_.Exception
      $connectionResult.TerminationType = "CONNECTION_EXCEPTION"
      $connectionResult.DetailedError = $errorException.Message
      
      if ($errorException -is [System.Net.Sockets.SocketException]) {
        $connectionResult.SocketError = $errorException.SocketErrorCode.ToString()
        $connectionResult.ErrorCode = $errorException.ErrorCode
      }
    }
    
    $results += $connectionResult
    
    # Small delay between tests
    if ($i -lt 5) {
      Start-Sleep -Seconds 2
    }
  }
  
  # Quick analysis
  $totalTests = $results.Count
  $resetRate = [Math]::Round(($remoteResets / $totalTests) * 100, 1)
  $timeoutRate = [Math]::Round(($timeouts / $totalTests) * 100, 1)
  $fourSecondRate = [Math]::Round(($fourSecondDrops / $totalTests) * 100, 1)
  $cleanCloseRate = [Math]::Round(($cleanCloses / $totalTests) * 100, 1)
  
  & $WriteLog "Quick TCP Reset Detection Results:"
  & $WriteLog "  Total tests: $totalTests"
  & $WriteLog "  Remote resets: $remoteResets ($resetRate%)"
  & $WriteLog "  Timeouts: $timeouts ($timeoutRate%)"
  & $WriteLog "  4-second drops: $fourSecondDrops ($fourSecondRate%)"
  & $WriteLog "  Clean closes: $cleanCloses ($cleanCloseRate%)"
  
  # Quick diagnosis
  $diagnosis = ""
  if ($fourSecondDrops -gt 0) {
    $diagnosis = "FOUR_SECOND_TIMEOUT_PATTERN"
    & $WriteLog "  *** 4.1-SECOND DROP PATTERN DETECTED: $fourSecondRate% of connections ***"
    & $WriteLog "  This suggests CGNAT connection tracking timeout or ISP rate limiting"
  } elseif ($resetRate -gt 50) {
    $diagnosis = "SEVERE_RESET_PATTERN"
    & $WriteLog "  *** SEVERE RST PACKET PATTERN: $resetRate% of connections ***"
    & $WriteLog "  ISP or CGNAT is actively resetting connections"
  } elseif ($timeoutRate -gt 30) {
    $diagnosis = "HIGH_TIMEOUT_RATE"
    & $WriteLog "  *** HIGH TIMEOUT RATE: $timeoutRate% of connections ***"
    & $WriteLog "  Network path or routing issues detected"
  } else {
    $diagnosis = "CONNECTION_STABILITY_OK"
    & $WriteLog "  Connection stability appears normal"
  }
  
  return @{
    TotalTests = $totalTests
    ResetRate = $resetRate
    TimeoutRate = $timeoutRate
    FourSecondRate = $fourSecondRate
    CleanCloseRate = $cleanCloseRate
    FourSecondDrops = $fourSecondDrops
    Diagnosis = $diagnosis
    Results = $results
  }
}

Export-ModuleMember -Function *
