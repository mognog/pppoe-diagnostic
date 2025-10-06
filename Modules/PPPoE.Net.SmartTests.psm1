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

# Quick Stability Suite (under ~60s) with summarized logging
function Test-QuickStabilitySuite {
  param(
    [string]$Host = 'netflix.com',
    [int]$Port = 443,
    [string]$SmallFileUrl = 'https://httpbin.org/bytes/20480',   # ~20KB
    [string]$LargeFileUrl = 'https://speed.hetzner.de/10MB.bin', # 10MB
    [int]$TimeBudgetSeconds = 60,
    [scriptblock]$WriteLog
  )
  & $WriteLog "Running Quick Stability Suite (<= ${TimeBudgetSeconds}s)..."

  $suiteStart = Get-Date
  $deadline = $suiteStart.AddSeconds($TimeBudgetSeconds)

  $evidence = @{
    IdleHold = $null
    Reuse = $null
    BurstCapacity = $null
    SequentialSpeed = $null
    SmallDownloads = $null
    LargeDownload = $null
    SustainedThroughput = $null
    TLSHandshakes = $null
    HttpTiming = $null
    Diagnosis = ''
  }

  function Limit-LogFailures {
    param([array]$Errors, [int]$Max=3)
    if (-not $Errors) { return @() }
    return @($Errors | Select-Object -First $Max)
  }

  # 1) Idle connection hold: 10 connections, wait ~25s
  $idleStart = Get-Date
  $idleConnections = 10
  $idleErrors = @()
  $alive = 0
  $clients = @()
  try {
    for ($i=1; $i -le $idleConnections; $i++) {
      $c = New-Object System.Net.Sockets.TcpClient
      $c.ReceiveTimeout = 5000
      $c.SendTimeout = 5000
      try { $c.Connect($Host, $Port) } catch { $idleErrors += $_.Exception.Message }
      $clients += $c
    }
    Start-Sleep -Seconds 25
    foreach ($c in $clients) {
      try {
        if ($c.Connected) {
          # probe minimal write/read
          $s = $c.GetStream(); $s.ReadTimeout = 500
          $bytes = [System.Text.Encoding]::ASCII.GetBytes("HEAD / HTTP/1.1`r`nHost: $Host`r`nConnection: keep-alive`r`n`r`n")
          $s.Write($bytes,0,$bytes.Length)
          $alive++
        }
      } catch { $idleErrors += $_.Exception.Message }
    }
  } finally {
    foreach ($c in $clients) { try { $c.Close() } catch {} }
  }
  $evidence.IdleHold = @{ Opened=$idleConnections; Alive=$alive; Failures=$idleConnections-$alive; SampleErrors=(Limit-LogFailures $idleErrors) }
  & $WriteLog "Idle hold: $alive/$idleConnections alive after ~25s"

  # 2) Connection reuse: single connection, 20 requests over ~20s
  $reuseOk = 0; $reuseErr = @();
  try {
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(2)
    for ($i=1; $i -le 20; $i++) {
      try {
        $resp = $client.GetAsync('https://www.cloudflare.com', [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
        if ($resp.IsSuccessStatusCode) { $reuseOk++ }
      } catch { $reuseErr += $_.Exception.Message }
      Start-Sleep -Milliseconds 500
      if ((Get-Date) -gt $deadline) { break }
    }
  } catch { $reuseErr += $_.Exception.Message } finally { if ($client) { $client.Dispose() } }
  $evidence.Reuse = @{ Requests=20; Success=$reuseOk; Failures=20-$reuseOk; SampleErrors=(Limit-LogFailures $reuseErr) }
  & $WriteLog "Connection reuse: $reuseOk/20 successful"

  if ((Get-Date) -gt $deadline) { goto FINISH }

  # 3) Burst capacity: 50 simultaneous connects
  $burstCount = 50; $burstSuccess=0; $burstErr=@()
  $burstTasks = @()
  for ($i=1; $i -le $burstCount; $i++) {
    $burstTasks += [System.Threading.Tasks.Task]::Run({
      try {
        $tc = New-Object System.Net.Sockets.TcpClient
        $tc.ReceiveTimeout = 3000
        $tc.SendTimeout = 3000
        $tc.Connect($Host,$Port)
        $ok = $tc.Connected
        $tc.Close()
        return $ok
      } catch { return $false }
    }.GetNewClosure())
  }
  [System.Threading.Tasks.Task]::WaitAll($burstTasks)
  foreach ($t in $burstTasks) { if ($t.Result) { $burstSuccess++ } }
  $evidence.BurstCapacity = @{ Attempted=$burstCount; Success=$burstSuccess; Failures=$burstCount-$burstSuccess }
  & $WriteLog "Burst capacity: $burstSuccess/$burstCount connections"

  if ((Get-Date) -gt $deadline) { goto FINISH }

  # 4) Sequential connection speed: 30 rapid connects
  $seqCount=30; $seqTimes=@(); $seqFail=0
  for ($i=1; $i -le $seqCount; $i++) {
    $sw=[System.Diagnostics.Stopwatch]::StartNew()
    try {
      $tc=New-Object System.Net.Sockets.TcpClient
      $tc.ReceiveTimeout=3000; $tc.SendTimeout=3000
      $tc.Connect($Host,$Port)
      $sw.Stop()
      if ($tc.Connected) { $seqTimes += $sw.ElapsedMilliseconds } else { $seqFail++ }
      $tc.Close()
    } catch { $sw.Stop(); $seqFail++ }
    Start-Sleep -Milliseconds 100
    if ((Get-Date) -gt $deadline) { break }
  }
  $seqAvg = if ($seqTimes.Count -gt 0) { [Math]::Round(($seqTimes | Measure-Object -Average).Average,1) } else { 0 }
  $evidence.SequentialSpeed = @{ Attempts=$seqCount; Failures=$seqFail; AvgMs=$seqAvg }
  & $WriteLog "Sequential connect: avg ${seqAvg}ms, failures $seqFail/$seqCount"

  if ((Get-Date) -gt $deadline) { goto FINISH }

  # 5) Small file download repetition: 30 times
  $smallTotal=30; $smallOk=0; $smallErr=@()
  for ($i=1; $i -le $smallTotal; $i++) {
    try {
      $resp = Invoke-WebRequest -Uri $SmallFileUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
      if ($resp.StatusCode -eq 200) { $smallOk++ } else { $smallErr += "Status $($resp.StatusCode)" }
    } catch { $smallErr += $_.Exception.Message }
    if ((Get-Date) -gt $deadline) { break }
  }
  $evidence.SmallDownloads = @{ Attempts=$smallTotal; Success=$smallOk; Failures=$smallTotal-$smallOk; SampleErrors=(Limit-LogFailures $smallErr) }
  & $WriteLog "Small downloads: $smallOk/$smallTotal"

  if ((Get-Date) -gt $deadline) { goto FINISH }

  # 6) Single larger download (10MB)
  $largeOk=$false; $largeMs=0; $largeErr=$null
  try {
    $sw=[System.Diagnostics.Stopwatch]::StartNew()
    $resp = Invoke-WebRequest -Uri $LargeFileUrl -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
    $sw.Stop()
    if ($resp.StatusCode -eq 200 -and $resp.Content) { $largeOk=$true; $largeMs=$sw.ElapsedMilliseconds }
  } catch { $largeErr=$_.Exception.Message }
  $evidence.LargeDownload = @{ Success=$largeOk; TimeMs=$largeMs; Error=$largeErr }
  & $WriteLog ("Large download: " + ($(if ($largeOk) { "SUCCESS (${largeMs}ms)" } else { "FAIL" })))

  if ((Get-Date) -gt $deadline) { goto FINISH }

  # 7) Sustained throughput ~20s (shortened to respect budget)
  $sustainSeconds=20; $samples=@(); $sustainErr=@(); $sustainStart=Get-Date
  while (((Get-Date)-$sustainStart).TotalSeconds -lt $sustainSeconds) {
    try {
      $sw=[System.Diagnostics.Stopwatch]::StartNew()
      $r=Invoke-WebRequest -Uri $SmallFileUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
      $sw.Stop()
      if ($r.StatusCode -eq 200 -and $r.Content) {
        $bytes=$r.Content.Length
        $mbps=[Math]::Round((($bytes*8)/($sw.ElapsedMilliseconds/1000))/1000000,2)
        $samples += $mbps
      }
    } catch { $sustainErr += $_.Exception.Message }
    Start-Sleep -Milliseconds 300
    if ((Get-Date) -gt $deadline) { break }
  }
  $avgMbps = if ($samples.Count -gt 0) { [Math]::Round(($samples | Measure-Object -Average).Average,2) } else { 0 }
  $evidence.SustainedThroughput = @{ Duration=$sustainSeconds; AvgMbps=$avgMbps; Samples=$samples.Count; SampleErrors=(Limit-LogFailures $sustainErr) }
  & $WriteLog "Sustained throughput: avg ${avgMbps} Mbps over ${sustainSeconds}s (${samples.Count} samples)"

  if ((Get-Date) -gt $deadline) { goto FINISH }

  # 8) TLS handshake stress: 50 handshakes quickly
  $tlsTotal=50; $tlsOk=0; $tlsErr=@()
  for ($i=1; $i -le $tlsTotal; $i++) {
    try {
      $tcp = New-Object System.Net.Sockets.TcpClient
      $tcp.ReceiveTimeout=3000; $tcp.SendTimeout=3000
      $tcp.Connect($Host,$Port)
      $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { param($s,$c,$ch,$e) $true })
      $ssl.AuthenticateAsClient($Host)
      if ($ssl.IsAuthenticated) { $tlsOk++ }
      $ssl.Close(); $tcp.Close()
    } catch { $tlsErr += $_.Exception.Message }
    if ((Get-Date) -gt $deadline) { break }
  }
  $evidence.TLSHandshakes = @{ Attempts=$tlsTotal; Success=$tlsOk; Failures=$tlsTotal-$tlsOk; SampleErrors=(Limit-LogFailures $tlsErr) }
  & $WriteLog "TLS handshakes: $tlsOk/$tlsTotal"

  if ((Get-Date) -gt $deadline) { goto FINISH }

  # 9) HTTP request timing patterns: 50 rapid HTTPS requests
  $httpTotal=50; $httpTimes=@(); $httpFail=0
  try {
    $hc = New-Object System.Net.Http.HttpClient
    $hc.Timeout=[TimeSpan]::FromSeconds(3)
    for ($i=1; $i -le $httpTotal; $i++) {
      $sw=[System.Diagnostics.Stopwatch]::StartNew()
      try {
        $r=$hc.GetAsync('https://www.youtube.com', [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $sw.Stop()
        if ($r.IsSuccessStatusCode) { $httpTimes += $sw.ElapsedMilliseconds } else { $httpFail++ }
      } catch { $httpFail++ }
      if ((Get-Date) -gt $deadline) { break }
    }
  } catch { $httpFail = $httpTotal } finally { if ($hc) { $hc.Dispose() } }
  $httpAvg = if ($httpTimes.Count -gt 0) { [Math]::Round(($httpTimes | Measure-Object -Average).Average,1) } else { 0 }
  $evidence.HttpTiming = @{ Attempts=$httpTotal; Failures=$httpFail; AvgMs=$httpAvg }
  & $WriteLog "HTTP timing: avg ${$httpAvg}ms, failures $httpFail/$httpTotal"

FINISH:
  # High-signal diagnosis
  $idleDrops = ($evidence.IdleHold.Opened - $evidence.IdleHold.Alive)
  $burstCeiling = ($evidence.BurstCapacity.Success -lt 50)
  $downloadFailures = ($evidence.SmallDownloads.Failures -gt 0 -or -not $evidence.LargeDownload.Success)
  $tlsIssues = ($evidence.TLSHandshakes.Failures -gt 0)
  $reuseIssues = ($evidence.Reuse.Failures -gt 0)

  if ($idleDrops -gt 0) {
    $evidence.Diagnosis = 'IDLE_DROPS_CONFIRMED'
  } elseif ($burstCeiling) {
    $evidence.Diagnosis = 'BURST_CAPACITY_LIMITED'
  } elseif ($downloadFailures) {
    $evidence.Diagnosis = 'DOWNLOAD_INSTABILITY'
  } elseif ($tlsIssues) {
    $evidence.Diagnosis = 'TLS_HANDSHAKE_ISSUES'
  } elseif ($reuseIssues) {
    $evidence.Diagnosis = 'KEEPALIVE_REUSE_FAILS'
  } else {
    $evidence.Diagnosis = 'NO_QUICK_INSTABILITY_DETECTED'
  }

  # Summarized evidence output (no spam)
  & $WriteLog "Quick Stability Evidence: $($evidence.Diagnosis)"
  & $WriteLog "  Idle hold alive: $($evidence.IdleHold.Alive)/$($evidence.IdleHold.Opened)"
  & $WriteLog "  Burst success: $($evidence.BurstCapacity.Success)/$($evidence.BurstCapacity.Attempted)"
  & $WriteLog "  Small downloads: $($evidence.SmallDownloads.Success)/$($evidence.SmallDownloads.Attempts)"
  & $WriteLog "  TLS handshakes: $($evidence.TLSHandshakes.Success)/$($evidence.TLSHandshakes.Attempts)"

  return $evidence
}
