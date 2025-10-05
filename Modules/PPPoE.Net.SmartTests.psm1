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

Export-ModuleMember -Function *
