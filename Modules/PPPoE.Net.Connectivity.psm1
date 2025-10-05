# PPPoE.Net.Connectivity.psm1 - Network connectivity testing functions

Set-StrictMode -Version 3.0

function Test-DNSResolution {
  param([string]$InterfaceAlias, [scriptblock]$WriteLog)
  
  $dnsTests = @(
    @{ Name = "Google DNS (8.8.8.8)"; Server = "8.8.8.8"; Query = "google.com" },
    @{ Name = "Cloudflare DNS (1.1.1.1)"; Server = "1.1.1.1"; Query = "cloudflare.com" },
    @{ Name = "Quad9 DNS (9.9.9.9)"; Server = "9.9.9.9"; Query = "quad9.net" }
  )
  
  $results = @()
  foreach ($test in $dnsTests) {
    try {
      & $WriteLog "Testing DNS resolution via $($test.Name)..."
      $result = Resolve-DnsName -Name $test.Query -Server $test.Server -ErrorAction Stop
      if ($result -and $result[0].IPAddress) {
        $ip = $result[0].IPAddress
        & $WriteLog "DNS OK: $($test.Query) -> $ip via $($test.Server)"
        $results += @{ Test = $test.Name; Status = "OK"; Result = "$($test.Query) -> $ip" }
      }
    } catch {
      & $WriteLog "DNS FAIL: $($test.Name) - $($_.Exception.Message)"
      $results += @{ Test = $test.Name; Status = "FAIL"; Result = $_.Exception.Message }
    }
  }
  return $results
}

function Test-PacketLoss {
  param([string]$TargetIP, [int]$Count = 20, [scriptblock]$WriteLog)
  
  & $WriteLog "Testing packet loss to $TargetIP ($Count packets)..."
  $results = @()
  
  for ($i = 1; $i -le $Count; $i++) {
    try {
      $ping = Test-Connection -TargetName $TargetIP -Count 1 -TimeoutSeconds 2 -ErrorAction Stop
      if ($ping -and $ping.ResponseTime) {
        $results += @{ Packet = $i; Success = $true; Latency = $ping.ResponseTime }
        & $WriteLog "Packet $($i): OK ($($ping.ResponseTime)ms)"
      }
    } catch {
      $results += @{ Packet = $i; Success = $false; Latency = $null }
      & $WriteLog "Packet $($i): LOST"
    }
    Start-Sleep -Milliseconds 100
  }
  
  $successfulResults = $results | Where-Object { $_.Success }
  $successful = if ($successfulResults) { $successfulResults.Count } else { 0 }
  $lost = $Count - $successful
  $lossPercent = [Math]::Round(($lost / $Count) * 100, 1)
  $avgLatency = if ($successful -gt 0) {
    [Math]::Round(($results | Where-Object { $_.Success } | Measure-Object -Property Latency -Average).Average, 1)
  } else { 0 }
  
  & $WriteLog "Packet loss test complete: $successful/$Count packets received ($lossPercent% loss), avg latency: $($avgLatency)ms"
  return @{ 
    TotalPackets = $Count; 
    SuccessfulPackets = $successful; 
    LostPackets = $lost; 
    LossPercent = $lossPercent; 
    AvgLatency = $avgLatency;
    Results = $results 
  }
}

function Test-RouteStability {
  param([string]$TargetIP, [int]$Count = 10, [scriptblock]$WriteLog)
  
  & $WriteLog "Testing route stability to $TargetIP ($Count traces)..."
  $routes = @()
  
  for ($i = 1; $i -le $Count; $i++) {
    try {
      & $WriteLog "Route trace $i/$Count..."
      $trace = tracert -d -h 5 $TargetIP 2>$null
      $hops = $trace | Where-Object { $_ -match '^\s*\d+\s+' } | ForEach-Object {
        if ($_ -match '^\s*\d+\s+.*?\s+(\d+\.\d+\.\d+\.\d+)') {
          $matches[1]
        }
      }
      $routes += $hops
      & $WriteLog "Route $($i): $($hops -join ' -> ')"
    } catch {
      & $WriteLog "Route trace $($i) failed: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 2
  }
  
  # Analyze route consistency
  $uniqueRoutes = $routes | Group-Object | Sort-Object Count -Descending
  $mostCommon = $uniqueRoutes[0]
  $consistency = [Math]::Round(($mostCommon.Count / $Count) * 100, 1)
  
  & $WriteLog "Route analysis: $consistency% consistency (most common: $($mostCommon.Name) - $($mostCommon.Count)/$Count times)"
  return @{ 
    TotalTraces = $Count; 
    Consistency = $consistency; 
    MostCommonRoute = $mostCommon.Name; 
    AllRoutes = $routes 
  }
}

function Get-InterfaceStatistics {
  param([string]$InterfaceName, [scriptblock]$WriteLog)
  
  try {
    $stats = Get-NetAdapterStatistics -Name $InterfaceName -ErrorAction Stop
    $errors = Get-NetAdapterAdvancedProperty -Name $InterfaceName -RegistryKeyword "*Error*" -ErrorAction SilentlyContinue
    
    & $WriteLog "Interface statistics for $($InterfaceName):"
    & $WriteLog "  Bytes sent: $($stats.BytesSent)"
    & $WriteLog "  Bytes received: $($stats.BytesReceived)"
    & $WriteLog "  Packets sent: $($stats.PacketsSent)"
    & $WriteLog "  Packets received: $($stats.PacketsReceived)"
    
    if ($errors) {
      foreach ($err in $errors) {
        if ($err.DisplayValue -and $err.DisplayValue -ne "0") {
          & $WriteLog "  $($err.DisplayName): $($err.DisplayValue)"
        }
      }
    }
    
    return @{
      BytesSent = $stats.BytesSent;
      BytesReceived = $stats.BytesReceived;
      PacketsSent = $stats.PacketsSent;
      PacketsReceived = $stats.PacketsReceived;
      Errors = $errors
    }
  } catch {
    & $WriteLog "Could not retrieve interface statistics: $($_.Exception.Message)"
    return $null
  }
}

function Test-ConnectionStability {
  param([string]$TargetIP, [int]$DurationSeconds = 60, [scriptblock]$WriteLog)
  
  & $WriteLog "Starting $DurationSeconds second stability test to $TargetIP..."
  $startTime = Get-Date
  $endTime = $startTime.AddSeconds($DurationSeconds)
  $results = @()
  
  while ((Get-Date) -lt $endTime) {
    $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    try {
      $ping = Test-Connection -TargetName $TargetIP -Count 1 -TimeoutSeconds 2 -ErrorAction Stop
      if ($ping -and $ping.ResponseTime) {
        $results += @{ Time = $elapsed; Success = $true; Latency = $ping.ResponseTime }
        & $WriteLog "[$($elapsed)s] OK ($($ping.ResponseTime)ms)"
      }
    } catch {
      $results += @{ Time = $elapsed; Success = $false; Latency = $null }
      & $WriteLog "[$($elapsed)s] FAIL"
    }
    Start-Sleep -Seconds 5
  }
  
  $successfulResults = $results | Where-Object { $_.Success }
  $successful = if ($successfulResults) { $successfulResults.Count } else { 0 }
  $total = $results.Count
  $uptime = [Math]::Round(($successful / $total) * 100, 1)
  $avgLatency = if ($successful -gt 0) {
    [Math]::Round(($results | Where-Object { $_.Success } | Measure-Object -Property Latency -Average).Average, 1)
  } else { 0 }
  
  & $WriteLog "Stability test complete: $uptime% uptime ($successful/$total tests passed), avg latency: $($avgLatency)ms"
  return @{ 
    DurationSeconds = $DurationSeconds; 
    UptimePercent = $uptime; 
    SuccessfulTests = $successful; 
    TotalTests = $total; 
    AvgLatency = $avgLatency;
    Results = $results 
  }
}

function Test-ConnectionJitter {
  param([string]$TargetIP, [int]$Count = 15, [scriptblock]$WriteLog)
  
  & $WriteLog "Testing connection jitter to $TargetIP ($Count packets)..."
  $results = @()
  
  for ($i = 1; $i -le $Count; $i++) {
    try {
      $ping = Test-Connection -TargetName $TargetIP -Count 1 -TimeoutSeconds 2 -ErrorAction Stop
      if ($ping -and $ping.ResponseTime) {
        $results += @{ Packet = $i; Latency = $ping.ResponseTime; Success = $true }
        & $WriteLog "Packet $($i): OK (${ping.ResponseTime}ms)"
      }
    } catch {
      $results += @{ Packet = $i; Latency = $null; Success = $false }
      & $WriteLog "Packet $($i): LOST"
    }
    Start-Sleep -Milliseconds 100
  }
  
  $successfulResults = $results | Where-Object { $_.Success }
  $successful = if ($successfulResults) { $successfulResults.Count } else { 0 }
  $lost = $Count - $successful
  
  if ($successful -gt 1) {
    $latencies = $successfulResults | ForEach-Object { $_.Latency }
    $avgLatency = [Math]::Round(($latencies | Measure-Object -Average).Average, 1)
    $minLatency = ($latencies | Measure-Object -Minimum).Minimum
    $maxLatency = ($latencies | Measure-Object -Maximum).Maximum
    $jitter = $maxLatency - $minLatency
    
    & $WriteLog "Jitter test complete: $successful/$Count packets received, avg: ${avgLatency}ms, jitter: ${jitter}ms (min: ${minLatency}ms, max: ${maxLatency}ms)"
    
    return @{
      TotalPackets = $Count;
      SuccessfulPackets = $successful;
      LostPackets = $lost;
      AvgLatency = $avgLatency;
      MinLatency = $minLatency;
      MaxLatency = $maxLatency;
      Jitter = $jitter;
      Results = $results
    }
  } else {
    & $WriteLog "Jitter test failed: insufficient successful packets for analysis"
    return @{
      TotalPackets = $Count;
      SuccessfulPackets = $successful;
      LostPackets = $lost;
      AvgLatency = 0;
      MinLatency = 0;
      MaxLatency = 0;
      Jitter = 0;
      Results = $results
    }
  }
}

function Test-BurstConnectivity {
  param([string]$TargetIP, [int]$BurstSize = 5, [int]$BurstCount = 3, [scriptblock]$WriteLog)
  
  & $WriteLog "Testing burst connectivity to $TargetIP ($BurstCount bursts of $BurstSize packets each)..."
  $burstResults = @()
  
  for ($burst = 1; $burst -le $BurstCount; $burst++) {
    & $WriteLog "Burst $burst/$BurstCount starting..."
    $burstSuccess = 0
    
    for ($i = 1; $i -le $BurstSize; $i++) {
      try {
      $ping = Test-Connection -TargetName $TargetIP -Count 1 -TimeoutSeconds 1 -ErrorAction Stop
      if ($ping -and $ping.ResponseTime) {
        $burstSuccess++
      }
      } catch {
        # Packet lost
      }
    }
    
    $burstPercent = [Math]::Round(($burstSuccess / $BurstSize) * 100, 1)
    $burstResults += @{ Burst = $burst; Successful = $burstSuccess; Total = $BurstSize; Percent = $burstPercent }
    & $WriteLog "Burst $burst complete: $burstSuccess/$BurstSize packets received ($burstPercent%)"
    
    if ($burst -lt $BurstCount) {
      Start-Sleep -Seconds 1
    }
  }
  
  $avgBurstSuccess = [Math]::Round(($burstResults | Measure-Object -Property Percent -Average).Average, 1)
  $minBurstSuccess = ($burstResults | Measure-Object -Property Percent -Minimum).Minimum
  $maxBurstSuccess = ($burstResults | Measure-Object -Property Percent -Maximum).Maximum
  
  & $WriteLog "Burst test complete: avg success $avgBurstSuccess% (range: $minBurstSuccess% - $maxBurstSuccess%)"
  
  return @{
    BurstResults = $burstResults;
    AvgBurstSuccess = $avgBurstSuccess;
    MinBurstSuccess = $minBurstSuccess;
    MaxBurstSuccess = $maxBurstSuccess;
    BurstVariability = $maxBurstSuccess - $minBurstSuccess
  }
}

function Test-QuickConnectivityCheck {
  param([string]$TargetIP, [scriptblock]$WriteLog)
  
  & $WriteLog "Quick connectivity check (5 rapid tests)..."
  $results = @()
  
  for ($i = 1; $i -le 5; $i++) {
    try {
      $ping = Test-Connection -TargetName $TargetIP -Count 1 -TimeoutSeconds 1 -ErrorAction Stop
      if ($ping -and $ping.ResponseTime) {
        $results += @{ Test = $i; Success = $true; Latency = $ping.ResponseTime }
        & $WriteLog "  Test $($i): OK ($($ping.ResponseTime)ms)"
      }
    } catch {
      $results += @{ Test = $i; Success = $false; Latency = $null }
      & $WriteLog "  Test $($i): FAIL"
    }
    Start-Sleep -Milliseconds 50
  }
  
  # Safe array handling - Where-Object returns null when no matches found
  $successfulResults = $results | Where-Object { $_.Success }
  $successful = if ($successfulResults) { $successfulResults.Count } else { 0 }
  $successRate = [Math]::Round(($successful / 5) * 100, 1)
  
  & $WriteLog "Quick check complete: $successful/5 tests passed ($successRate%)"
  
  return @{
    SuccessRate = $successRate;
    SuccessfulTests = $successful;
    TotalTests = 5;
    Results = $results
  }
}

function Test-ProviderSpecificDiagnostics {
  param([string]$InterfaceAlias, [scriptblock]$WriteLog)
  
  & $WriteLog "Running provider-specific diagnostics..."
  $diagnostics = @()
  
  # Test common ISP DNS servers
  $ispDnsTests = @(
    @{ Name = "Rise Broadband DNS"; Server = "8.8.8.8"; Query = "google.com" },
    @{ Name = "OpenDNS"; Server = "208.67.222.222"; Query = "opendns.com" },
    @{ Name = "Quad9"; Server = "9.9.9.9"; Query = "quad9.net" }
  )
  
  foreach ($test in $ispDnsTests) {
    try {
      & $WriteLog "Testing $($test.Name) ($($test.Server))..."
      $result = Resolve-DnsName -Name $test.Query -Server $test.Server -ErrorAction Stop
      if ($result) {
        $diagnostics += @{ Test = $test.Name; Status = "OK"; Result = "DNS resolution successful" }
        & $WriteLog "  $($test.Name): OK"
      }
    } catch {
      $diagnostics += @{ Test = $test.Name; Status = "FAIL"; Result = $_.Exception.Message }
      & $WriteLog "  $($test.Name): FAIL - $($_.Exception.Message)"
    }
  }
  
  # Test different packet sizes to detect MTU issues
  $mtuTests = @(64, 512, 1472)
  & $WriteLog "Testing MTU with different packet sizes..."
  
  foreach ($size in $mtuTests) {
    try {
      $ping = Test-Connection -TargetName '1.1.1.1' -Count 1 -BufferSize $size -TimeoutSeconds 2 -ErrorAction Stop
      if ($ping) {
        $diagnostics += @{ Test = "MTU-$size"; Status = "OK"; Result = "Packet size $size successful" }
        & $WriteLog "  MTU test $size bytes: OK"
      }
    } catch {
      $diagnostics += @{ Test = "MTU-$size"; Status = "FAIL"; Result = "Packet size $size failed" }
      & $WriteLog "  MTU test $size bytes: FAIL"
    }
  }
  
  # Test connection to ISP-specific endpoints
  $ispEndpoints = @(
    @{ Name = "Cloudflare"; IP = "1.1.1.1" },
    @{ Name = "Google DNS"; IP = "8.8.8.8" }
  )
  
  & $WriteLog "Testing connectivity to various endpoints..."
  foreach ($endpoint in $ispEndpoints) {
    try {
      $ping = Test-Connection -TargetName $endpoint.IP -Count 2 -TimeoutSeconds 1 -ErrorAction Stop
      if ($ping) {
        $avgLatency = [Math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 1)
        $diagnostics += @{ Test = "Connectivity-$($endpoint.Name)"; Status = "OK"; Result = "Avg latency: ${avgLatency}ms" }
        & $WriteLog "  $($endpoint.Name) ($($endpoint.IP)): OK (${avgLatency}ms avg)"
      }
    } catch {
      $diagnostics += @{ Test = "Connectivity-$($endpoint.Name)"; Status = "FAIL"; Result = "Connection failed" }
      & $WriteLog "  $($endpoint.Name) ($($endpoint.IP)): FAIL"
    }
  }
  
  return $diagnostics
}

function Test-TCPConnectivity {
  param([string]$TargetIP, [int]$Port, [scriptblock]$WriteLog)
  
  try {
    & $WriteLog "Testing TCP connectivity to $TargetIP`:$Port..."
    
    $result = Test-NetConnection -ComputerName $TargetIP -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($result) {
      & $WriteLog "TCP connection to $TargetIP`:$Port`: SUCCESS"
      return @{ Status = "SUCCESS"; Target = "$TargetIP`:$Port" }
    } else {
      & $WriteLog "TCP connection to $TargetIP`:$Port`: FAILED"
      return @{ Status = "FAILED"; Target = "$TargetIP`:$Port" }
    }
  } catch {
    & $WriteLog "Error testing TCP connectivity to $TargetIP`:$Port`: $($_.Exception.Message)"
    return @{ Status = "ERROR"; Target = "$TargetIP`:$Port"; Error = $_.Exception.Message }
  }
}

function Test-MultiDestinationRouting {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing routing to multiple destinations..."
  
  $destinations = @(
    @{ Name = "Google DNS"; IP = "8.8.8.8" },
    @{ Name = "Cloudflare DNS"; IP = "1.1.1.1" },
    @{ Name = "Quad9 DNS"; IP = "9.9.9.9" },
    @{ Name = "OpenDNS"; IP = "208.67.222.222" }
  )
  
  $results = @()
  
  foreach ($dest in $destinations) {
    try {
      & $WriteLog "Testing route to $($dest.Name) ($($dest.IP))..."
      
      # Test with tracert to see where traffic stops
      $trace = tracert -d -h 8 -w 2000 $dest.IP 2>$null
      $hops = $trace | Where-Object { $_ -match '^\s*\d+\s+' } | ForEach-Object {
        if ($_ -match '^\s*\d+\s+.*?\s+(\d+\.\d+\.\d+\.\d+)') {
          $matches[1]
        }
      }
      
      if ($hops -and $hops.Count -gt 0) {
        $lastHop = $hops[-1]
        if ($lastHop -eq $dest.IP) {
          & $WriteLog "  Route to $($dest.Name): COMPLETE (reached destination)"
          $results += @{ Destination = $dest.Name; IP = $dest.IP; Status = "COMPLETE"; LastHop = $lastHop }
        } else {
          & $WriteLog "  Route to $($dest.Name): PARTIAL (stopped at $lastHop)"
          $results += @{ Destination = $dest.Name; IP = $dest.IP; Status = "PARTIAL"; LastHop = $lastHop }
        }
      } else {
        & $WriteLog "  Route to $($dest.Name): FAILED (no response)"
        $results += @{ Destination = $dest.Name; IP = $dest.IP; Status = "FAILED"; LastHop = $null }
      }
    } catch {
      & $WriteLog "  Route to $($dest.Name): ERROR - $($_.Exception.Message)"
      $results += @{ Destination = $dest.Name; IP = $dest.IP; Status = "ERROR"; LastHop = $null; Error = $_.Exception.Message }
    }
  }
  
  return $results
}

function Test-IPv6FallbackDelay {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing IPv6 fallback delay patterns..."
  & $WriteLog "This test measures time difference between IPv6-first attempts vs IPv4-only connections"
  
  $testHosts = @(
    @{ Name = "Netflix"; Domain = "netflix.com" },
    @{ Name = "Apple TV"; Domain = "tv.apple.com" },
    @{ Name = "YouTube"; Domain = "youtube.com" },
    @{ Name = "Google"; Domain = "google.com" }
  )
  
  $results = @()
  
  foreach ($testHost in $testHosts) {
    & $WriteLog "Testing $($testHost.Name) ($($testHost.Domain))..."
    
    # Test IPv6-first resolution and connection
    $ipv6Time = $null
    $ipv4FallbackTime = $null
    $ipv6Success = $false
    $ipv4Success = $false
    
    try {
      # Get IPv6 addresses first
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $ipv6Addresses = Resolve-DnsName -Name $testHost.Domain -Type AAAA -ErrorAction SilentlyContinue
      $sw.Stop()
      $ipv6ResolveTime = $sw.ElapsedMilliseconds
      
      if ($ipv6Addresses -and $ipv6Addresses.Count -gt 0) {
        & $WriteLog "  IPv6 addresses found: $($ipv6Addresses.Count) addresses"
        
        # Try to connect to IPv6 address
        $sw.Restart()
        try {
          $tcpClient = New-Object System.Net.Sockets.TcpClient
          $firstAddr = $ipv6Addresses[0]
          if ($firstAddr -and ($firstAddr.PSObject.Properties['IPAddress'] -and $firstAddr.IPAddress)) {
            $tcpClient.Connect($firstAddr.IPAddress, 443)
            $ipv6Success = $tcpClient.Connected
          } elseif ($firstAddr -is [string]) {
            $tcpClient.Connect($firstAddr, 443)
            $ipv6Success = $tcpClient.Connected
          } else {
            $ipv6Success = $false
          }
          $tcpClient.Close()
        } catch {
          $ipv6Success = $false
        }
        $sw.Stop()
        $ipv6Time = $sw.ElapsedMilliseconds
        
        if ($ipv6Success) {
          & $WriteLog "  IPv6 connection: SUCCESS (${ipv6Time}ms)"
        } else {
          & $WriteLog "  IPv6 connection: FAILED (${ipv6Time}ms) - will fallback to IPv4"
        }
      } else {
        & $WriteLog "  No IPv6 addresses found - direct IPv4 fallback"
        $ipv6Time = 0
      }
      
      # Test IPv4-only connection (forced fallback)
      $sw.Restart()
      try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($testHost.Domain, 443)
        $ipv4Success = $tcpClient.Connected
        $tcpClient.Close()
      } catch {
        $ipv4Success = $false
      }
      $sw.Stop()
      $ipv4FallbackTime = $sw.ElapsedMilliseconds
      
      if ($ipv4Success) {
        & $WriteLog "  IPv4 fallback: SUCCESS (${ipv4FallbackTime}ms)"
      } else {
        & $WriteLog "  IPv4 fallback: FAILED (${ipv4FallbackTime}ms)"
      }
      
      # Calculate delay
      $totalDelay = if ($ipv6Time -gt 0) { $ipv6Time + $ipv4FallbackTime } else { $ipv4FallbackTime }
      $ipv6Overhead = if ($ipv6Time -gt 0 -and -not $ipv6Success) { $ipv6Time } else { 0 }
      
      $results += @{
        Host = $testHost.Name
        Domain = $testHost.Domain
        IPv6Addresses = if ($ipv6Addresses -and ($ipv6Addresses -is [array] -or $ipv6Addresses.PSObject.Properties['Count'])) { $ipv6Addresses.Count } else { 0 }
        IPv6ResolveTime = $ipv6ResolveTime
        IPv6ConnectionTime = $ipv6Time
        IPv6Success = $ipv6Success
        IPv4FallbackTime = $ipv4FallbackTime
        IPv4Success = $ipv4Success
        TotalDelay = $totalDelay
        IPv6Overhead = $ipv6Overhead
      }
      
      & $WriteLog "  Summary: Total delay ${totalDelay}ms, IPv6 overhead ${ipv6Overhead}ms"
      
    } catch {
      & $WriteLog "  Error testing $($testHost.Name): $($_.Exception.Message)"
      $results += @{
        Host = $testHost.Name
        Domain = $testHost.Domain
        IPv6Addresses = 0
        IPv6ResolveTime = 0
        IPv6ConnectionTime = 0
        IPv6Success = $false
        IPv4FallbackTime = 0
        IPv4Success = $false
        TotalDelay = 0
        IPv6Overhead = 0
        Error = $_.Exception.Message
      }
    }
    
    Start-Sleep -Milliseconds 500
  }
  
  # Analyze results
  $successfulResults = $results | Where-Object { -not $_.Error }
  $avgDelay = if ($successfulResults -and $successfulResults.Count -gt 0) {
    [Math]::Round(($successfulResults | Measure-Object -Property TotalDelay -Average).Average, 1)
  } else { 0 }
  
  $avgIPv6Overhead = if ($successfulResults -and $successfulResults.Count -gt 0) {
    [Math]::Round(($successfulResults | Where-Object { $_.IPv6Overhead -gt 0 } | Measure-Object -Property IPv6Overhead -Average).Average, 1)
  } else { 0 }
  
  $ipv6Failures = if ($successfulResults) { 
    ($successfulResults | Where-Object { $_.IPv6Overhead -gt 0 }).Count 
  } else { 0 }
  
  & $WriteLog "IPv6 Fallback Analysis:"
  & $WriteLog "  Average total delay: ${avgDelay}ms"
  & $WriteLog "  Average IPv6 overhead: ${avgIPv6Overhead}ms"
  & $WriteLog "  Services with IPv6 failures: $ipv6Failures/$($testHosts.Count)"
  
  if ($avgIPv6Overhead -gt 1000) {
    & $WriteLog "  DIAGNOSIS: Significant IPv6 timeout delays detected - disabling IPv6 may improve performance"
  } elseif ($avgIPv6Overhead -gt 500) {
    & $WriteLog "  DIAGNOSIS: Moderate IPv6 timeout delays - consider IPv6 configuration review"
  } else {
    & $WriteLog "  DIAGNOSIS: IPv6 fallback performance is acceptable"
  }
  
  return @{
    AverageDelay = $avgDelay
    AverageIPv6Overhead = $avgIPv6Overhead
    IPv6FailureCount = $ipv6Failures
    TotalServices = $testHosts.Count
    Results = $results
    Diagnosis = if ($avgIPv6Overhead -gt 1000) { "SIGNIFICANT_DELAYS" } elseif ($avgIPv6Overhead -gt 500) { "MODERATE_DELAYS" } else { "ACCEPTABLE" }
  }
}

function Test-ConnectionEstablishmentSpeed {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing connection establishment speed to streaming services..."
  & $WriteLog "This test measures how quickly new TCP connections can be established"
  
  $streamingServices = @(
    @{ Name = "Netflix"; Host = "netflix.com"; Port = 443 },
    @{ Name = "Apple TV"; Host = "tv.apple.com"; Port = 443 },
    @{ Name = "YouTube"; Host = "youtube.com"; Port = 443 },
    @{ Name = "Twitch"; Host = "twitch.tv"; Port = 443 },
    @{ Name = "Disney+"; Host = "disneyplus.com"; Port = 443 }
  )
  
  $results = @()
  
  foreach ($service in $streamingServices) {
    & $WriteLog "Testing $($service.Name) connection speed..."
    
    $connectionTimes = @()
    $successCount = 0
    $failureCount = 0
    
    # Test 5 connection attempts
    for ($i = 1; $i -le 5; $i++) {
      try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        
        # Set a reasonable timeout
        $tcpClient.ReceiveTimeout = 5000
        $tcpClient.SendTimeout = 5000
        
        $tcpClient.Connect($service.Host, $service.Port)
        $sw.Stop()
        
        if ($tcpClient.Connected) {
          $connectionTime = $sw.ElapsedMilliseconds
          $connectionTimes += $connectionTime
          $successCount++
          & $WriteLog "  Attempt $i`: SUCCESS (${connectionTime}ms)"
        } else {
          $failureCount++
          & $WriteLog "  Attempt $i`: FAILED (connection not established)"
        }
        
        $tcpClient.Close()
      } catch {
        $sw.Stop()
        $connectionTime = $sw.ElapsedMilliseconds
        $failureCount++
        & $WriteLog "  Attempt $i`: FAILED (${connectionTime}ms) - $($_.Exception.Message)"
      }
      
      Start-Sleep -Milliseconds 200
    }
    
    # Calculate statistics
    $avgTime = if ($connectionTimes.Count -gt 0) {
      [Math]::Round(($connectionTimes | Measure-Object -Average).Average, 1)
    } else { 0 }
    
    $minTime = if ($connectionTimes.Count -gt 0) {
      ($connectionTimes | Measure-Object -Minimum).Minimum
    } else { 0 }
    
    $maxTime = if ($connectionTimes.Count -gt 0) {
      ($connectionTimes | Measure-Object -Maximum).Maximum
    } else { 0 }
    
    $successRate = [Math]::Round(($successCount / 5) * 100, 1)
    
    $results += @{
      Service = $service.Name
      Host = $service.Host
      SuccessCount = $successCount
      FailureCount = $failureCount
      SuccessRate = $successRate
      AverageTime = $avgTime
      MinTime = $minTime
      MaxTime = $maxTime
      ConnectionTimes = $connectionTimes
    }
    
    & $WriteLog "  Summary: $successRate% success rate, avg ${avgTime}ms (range: ${minTime}-${maxTime}ms)"
    
    # Classify performance
    if ($successRate -eq 100 -and $avgTime -lt 1000) {
      & $WriteLog "  Performance: EXCELLENT"
    } elseif ($successRate -ge 80 -and $avgTime -lt 2000) {
      & $WriteLog "  Performance: GOOD"
    } elseif ($successRate -ge 60 -and $avgTime -lt 5000) {
      & $WriteLog "  Performance: FAIR"
    } else {
      & $WriteLog "  Performance: POOR"
    }
  }
  
  # Overall analysis
  $overallSuccessRate = [Math]::Round(($results | Measure-Object -Property SuccessRate -Average).Average, 1)
  $overallAvgTime = [Math]::Round(($results | Where-Object { $_.AverageTime -gt 0 } | Measure-Object -Property AverageTime -Average).Average, 1)
  $problematicServices = $results | Where-Object { $_.SuccessRate -lt 80 -or $_.AverageTime -gt 3000 }
  
  & $WriteLog "Connection Establishment Speed Analysis:"
  & $WriteLog "  Overall success rate: $overallSuccessRate%"
  & $WriteLog "  Overall average time: ${overallAvgTime}ms"
  & $WriteLog "  Problematic services: $($problematicServices.Count)/$($streamingServices.Count)"
  
  if ($problematicServices.Count -gt 0) {
    & $WriteLog "  Services with issues:"
    foreach ($service in $problematicServices) {
      & $WriteLog "    - $($service.Service): $($service.SuccessRate)% success, ${service.AverageTime}ms avg"
    }
  }
  
  # Diagnosis
  if ($overallSuccessRate -lt 60) {
    & $WriteLog "  DIAGNOSIS: Major connection establishment issues - investigate network path and ISP"
  } elseif ($overallAvgTime -gt 3000) {
    & $WriteLog "  DIAGNOSIS: Slow connection establishment - may cause app timeouts"
  } elseif ($problematicServices.Count -gt 0) {
    & $WriteLog "  DIAGNOSIS: Some services have connection issues - check service-specific routing"
  } else {
    & $WriteLog "  DIAGNOSIS: Connection establishment performance is good"
  }
  
  return @{
    OverallSuccessRate = $overallSuccessRate
    OverallAverageTime = $overallAvgTime
    ProblematicServices = $problematicServices.Count
    TotalServices = $streamingServices.Count
    Results = $results
    Diagnosis = if ($overallSuccessRate -lt 60) { "MAJOR_ISSUES" } elseif ($overallAvgTime -gt 3000) { "SLOW_CONNECTIONS" } elseif ($problematicServices.Count -gt 0) { "SOME_ISSUES" } else { "GOOD" }
  }
}

function Test-ICMPRateLimiting {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing ICMP rate limiting patterns..."
  & $WriteLog "This test compares burst vs sustained ICMP packet success rates"
  
  $testIP = '1.1.1.1'
  
  # Test 1: Burst ICMP (rapid fire)
  & $WriteLog "Test 1: Burst ICMP test (10 rapid pings)..."
  $burstResults = @()
  $burstSuccess = 0
  
  for ($i = 1; $i -le 10; $i++) {
    try {
      $ping = Test-Connection -TargetName $testIP -Count 1 -TimeoutSeconds 1 -ErrorAction Stop
      if ($ping -and ($ping.PSObject.Properties['ResponseTime'] -or $ping.PSObject.Properties['Latency'])) {
        $latency = if ($ping.PSObject.Properties['ResponseTime']) { $ping.ResponseTime } else { $ping.Latency }
        $burstResults += @{ Packet = $i; Success = $true; Latency = $latency }
        $burstSuccess++
        & $WriteLog "  Burst ping $i`: SUCCESS (${latency}ms)"
      } else {
        $burstResults += @{ Packet = $i; Success = $false; Latency = $null }
        & $WriteLog "  Burst ping $i`: FAILED"
      }
    } catch {
      $burstResults += @{ Packet = $i; Success = $false; Latency = $null }
      & $WriteLog "  Burst ping $i`: FAILED - $($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 50  # Very short delay for burst test
  }
  
  $burstSuccessRate = [Math]::Round(($burstSuccess / 10) * 100, 1)
  & $WriteLog "Burst test result: $burstSuccessRate% success rate"
  
  # Wait between tests to avoid interference
  Start-Sleep -Seconds 2
  
  # Test 2: Sustained ICMP (spaced out)
  & $WriteLog "Test 2: Sustained ICMP test (10 pings with 1-second intervals)..."
  $sustainedResults = @()
  $sustainedSuccess = 0
  
  for ($i = 1; $i -le 10; $i++) {
    try {
      $ping = Test-Connection -TargetName $testIP -Count 1 -TimeoutSeconds 2 -ErrorAction Stop
      if ($ping -and ($ping.PSObject.Properties['ResponseTime'] -or $ping.PSObject.Properties['Latency'])) {
        $latency = if ($ping.PSObject.Properties['ResponseTime']) { $ping.ResponseTime } else { $ping.Latency }
        $sustainedResults += @{ Packet = $i; Success = $true; Latency = $latency }
        $sustainedSuccess++
        & $WriteLog "  Sustained ping $i`: SUCCESS (${latency}ms)"
      } else {
        $sustainedResults += @{ Packet = $i; Success = $false; Latency = $null }
        & $WriteLog "  Sustained ping $i`: FAILED"
      }
    } catch {
      $sustainedResults += @{ Packet = $i; Success = $false; Latency = $null }
      & $WriteLog "  Sustained ping $i`: FAILED - $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 1  # 1-second delay for sustained test
  }
  
  $sustainedSuccessRate = [Math]::Round(($sustainedSuccess / 10) * 100, 1)
  & $WriteLog "Sustained test result: $sustainedSuccessRate% success rate"
  
  # Test 3: Single ICMP after delay
  & $WriteLog "Test 3: Single ICMP test after 5-second delay..."
  Start-Sleep -Seconds 5
  
  $singleSuccess = $false
  try {
    $ping = Test-Connection -TargetName $testIP -Count 1 -TimeoutSeconds 2 -ErrorAction Stop
    if ($ping -and ($ping.PSObject.Properties['ResponseTime'] -or $ping.PSObject.Properties['Latency'])) {
      $latency = if ($ping.PSObject.Properties['ResponseTime']) { $ping.ResponseTime } else { $ping.Latency }
      $singleSuccess = $true
      & $WriteLog "Single ping: SUCCESS (${latency}ms)"
    } else {
      & $WriteLog "Single ping: FAILED"
    }
  } catch {
    & $WriteLog "Single ping: FAILED - $($_.Exception.Message)"
  }
  
  # Analyze patterns
  $rateLimitingDetected = $false
  $rateLimitPattern = ""
  
  if ($burstSuccessRate -lt $sustainedSuccessRate -and $sustainedSuccessRate -gt 50) {
    $rateLimitingDetected = $true
    $rateLimitPattern = "Burst packets are being rate-limited"
    & $WriteLog "RATE LIMITING DETECTED: Burst packets ($burstSuccessRate%) perform worse than sustained ($sustainedSuccessRate%)"
  } elseif ($burstSuccessRate -eq 0 -and $sustainedSuccessRate -gt 0) {
    $rateLimitingDetected = $true
    $rateLimitPattern = "Severe burst rate limiting detected"
    & $WriteLog "SEVERE RATE LIMITING: All burst packets failed, but sustained packets succeeded"
  } elseif ($burstSuccessRate -gt $sustainedSuccessRate) {
    $rateLimitPattern = "No rate limiting detected - burst performs better"
    & $WriteLog "NO RATE LIMITING: Burst packets ($burstSuccessRate%) perform better than sustained ($sustainedSuccessRate%)"
  } else {
    $rateLimitPattern = "Inconclusive - similar performance patterns"
    & $WriteLog "INCONCLUSIVE: Similar performance between burst ($burstSuccessRate%) and sustained ($sustainedSuccessRate%)"
  }
  
  # Calculate latency differences
  $burstLatencies = $burstResults | Where-Object { $_.Success } | ForEach-Object { $_.Latency }
  $sustainedLatencies = $sustainedResults | Where-Object { $_.Success } | ForEach-Object { $_.Latency }
  
  $burstAvgLatency = if ($burstLatencies.Count -gt 0) {
    [Math]::Round(($burstLatencies | Measure-Object -Average).Average, 1)
  } else { 0 }
  
  $sustainedAvgLatency = if ($sustainedLatencies.Count -gt 0) {
    [Math]::Round(($sustainedLatencies | Measure-Object -Average).Average, 1)
  } else { 0 }
  
  & $WriteLog "ICMP Rate Limiting Analysis:"
  & $WriteLog "  Burst success rate: $burstSuccessRate% (avg latency: ${burstAvgLatency}ms)"
  & $WriteLog "  Sustained success rate: $sustainedSuccessRate% (avg latency: ${sustainedAvgLatency}ms)"
  & $WriteLog "  Single ping success: $(if ($singleSuccess) { 'YES' } else { 'NO' })"
  & $WriteLog "  Rate limiting detected: $(if ($rateLimitingDetected) { 'YES' } else { 'NO' })"
  
  # Diagnosis and recommendations
  if ($rateLimitingDetected) {
    if ($singleSuccess) {
      & $WriteLog "  DIAGNOSIS: ISP is rate-limiting ICMP burst traffic but allows individual packets"
      & $WriteLog "  IMPACT: Path MTU Discovery may fail during high-traffic periods"
      & $WriteLog "  RECOMMENDATION: Monitor for MTU-related issues during streaming"
    } else {
      & $WriteLog "  DIAGNOSIS: ISP is blocking or severely rate-limiting ICMP traffic"
      & $WriteLog "  IMPACT: Path MTU Discovery and some diagnostic tools will not work"
      & $WriteLog "  RECOMMENDATION: Use TCP-based diagnostics instead of ping tests"
    }
  } else {
    & $WriteLog "  DIAGNOSIS: ICMP traffic is not being rate-limited by ISP"
    & $WriteLog "  IMPACT: Normal ICMP functionality available"
    & $WriteLog "  RECOMMENDATION: ICMP-based diagnostics should work normally"
  }
  
  return @{
    RateLimitingDetected = $rateLimitingDetected
    BurstSuccessRate = $burstSuccessRate
    SustainedSuccessRate = $sustainedSuccessRate
    SinglePingSuccess = $singleSuccess
    BurstAvgLatency = $burstAvgLatency
    SustainedAvgLatency = $sustainedAvgLatency
    RateLimitPattern = $rateLimitPattern
    BurstResults = $burstResults
    SustainedResults = $sustainedResults
    Diagnosis = if ($rateLimitingDetected) { if ($singleSuccess) { "BURST_RATE_LIMITED" } else { "SEVERELY_RATE_LIMITED" } } else { "NO_RATE_LIMITING" }
  }
}

function Test-CGNATConnectionCapacity {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing CGNAT connection capacity..."
  & $WriteLog "This test opens 20 simultaneous connections to different hosts to detect CGNAT limits"
  
  # Test hosts with different IP ranges to test CGNAT connection limits
  $testHosts = @(
    @{ Name = "Google DNS"; Host = "8.8.8.8"; Port = 53 },
    @{ Name = "Cloudflare DNS"; Host = "1.1.1.1"; Port = 53 },
    @{ Name = "Quad9 DNS"; Host = "9.9.9.9"; Port = 53 },
    @{ Name = "OpenDNS"; Host = "208.67.222.222"; Port = 53 },
    @{ Name = "Google HTTPS"; Host = "google.com"; Port = 443 },
    @{ Name = "Cloudflare HTTPS"; Host = "cloudflare.com"; Port = 443 },
    @{ Name = "GitHub"; Host = "github.com"; Port = 443 },
    @{ Name = "StackOverflow"; Host = "stackoverflow.com"; Port = 443 },
    @{ Name = "Reddit"; Host = "reddit.com"; Port = 443 },
    @{ Name = "Wikipedia"; Host = "wikipedia.org"; Port = 443 },
    @{ Name = "Netflix"; Host = "netflix.com"; Port = 443 },
    @{ Name = "YouTube"; Host = "youtube.com"; Port = 443 },
    @{ Name = "Apple"; Host = "apple.com"; Port = 443 },
    @{ Name = "Microsoft"; Host = "microsoft.com"; Port = 443 },
    @{ Name = "Amazon"; Host = "amazon.com"; Port = 443 },
    @{ Name = "Facebook"; Host = "facebook.com"; Port = 443 },
    @{ Name = "Twitter"; Host = "twitter.com"; Port = 443 },
    @{ Name = "LinkedIn"; Host = "linkedin.com"; Port = 443 },
    @{ Name = "Instagram"; Host = "instagram.com"; Port = 443 },
    @{ Name = "Spotify"; Host = "spotify.com"; Port = 443 }
  )
  
  $results = @()
  $successfulConnections = @()
  $failedConnections = @()
  
  & $WriteLog "Attempting to establish $($testHosts.Count) simultaneous connections..."
  
  # Create all connection attempts simultaneously
  $connectionTasks = @()
  
  foreach ($testHost in $testHosts) {
    # Capture the current testHost in a local variable for the closure
    $currentHost = $testHost
    
    $task = [System.Threading.Tasks.Task]::Run({
      $hostInfo = $currentHost
      
      try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = 5000
        $tcpClient.SendTimeout = 5000
        
        # Attempt connection with timeout
        $connectTask = $tcpClient.ConnectAsync($hostInfo.Host, $hostInfo.Port)
        $timeoutTask = [System.Threading.Tasks.Task]::Delay(5000)
        
        $completedTask = [System.Threading.Tasks.Task]::WaitAny($connectTask, $timeoutTask)
        
        if ($completedTask -eq 0 -and $tcpClient.Connected) {
          $tcpClient.Close()
          return @{
            Host = $hostInfo.Name
            Target = "$($hostInfo.Host):$($hostInfo.Port)"
            Success = $true
            Error = $null
          }
        } else {
          $tcpClient.Close()
          return @{
            Host = $hostInfo.Name
            Target = "$($hostInfo.Host):$($hostInfo.Port)"
            Success = $false
            Error = if ($completedTask -eq 1) { "Connection timeout" } else { "Connection failed" }
          }
        }
      } catch {
        return @{
          Host = $hostInfo.Name
          Target = "$($hostInfo.Host):$($hostInfo.Port)"
          Success = $false
          Error = $_.Exception.Message
        }
      }
    }.GetNewClosure())
    
    $connectionTasks += $task
  }
  
  # Wait for all connections to complete
  & $WriteLog "Waiting for all connection attempts to complete..."
  [System.Threading.Tasks.Task]::WaitAll($connectionTasks)
  
  # Collect results
  foreach ($task in $connectionTasks) {
    $result = $task.Result
    $results += $result
    
    if ($result.Success) {
      $successfulConnections += $result
      & $WriteLog "  ✓ $($result.Host): SUCCESS"
    } else {
      $failedConnections += $result
      & $WriteLog "  ✗ $($result.Host): FAILED - $($result.Error)"
    }
  }
  
  # Analyze results
  $totalConnections = $testHosts.Count
  $successCount = $successfulConnections.Count
  $failureCount = $failedConnections.Count
  $successRate = [Math]::Round(($successCount / $totalConnections) * 100, 1)
  
  & $WriteLog "CGNAT Connection Capacity Analysis:"
  & $WriteLog "  Total connections attempted: $totalConnections"
  & $WriteLog "  Successful connections: $successCount"
  & $WriteLog "  Failed connections: $failureCount"
  & $WriteLog "  Success rate: $successRate%"
  
  # Analyze failure patterns
  $timeoutFailures = ($failedConnections | Where-Object { $_.Error -eq "Connection timeout" }).Count
  $connectionFailures = ($failedConnections | Where-Object { $_.Error -ne "Connection timeout" }).Count
  
  & $WriteLog "  Timeout failures: $timeoutFailures"
  & $WriteLog "  Connection failures: $connectionFailures"
  
  # Determine if CGNAT limits are being hit
  $cgnatLimitsDetected = $false
  $cgnatPattern = ""
  
  if ($successRate -lt 50) {
    $cgnatLimitsDetected = $true
    $cgnatPattern = "Severe connection capacity limits detected"
    & $WriteLog "  SEVERE CGNAT LIMITS: Less than 50% of connections succeeded"
  } elseif ($successRate -lt 80 -and $timeoutFailures -gt $connectionFailures) {
    $cgnatLimitsDetected = $true
    $cgnatPattern = "Moderate CGNAT connection limits with timeout pattern"
    & $WriteLog "  MODERATE CGNAT LIMITS: Timeout failures exceed connection failures"
  } elseif ($timeoutFailures -gt 0 -and $timeoutFailures -gt ($totalConnections * 0.3)) {
    $cgnatLimitsDetected = $true
    $cgnatPattern = "CGNAT timeout pattern detected"
    & $WriteLog "  CGNAT TIMEOUT PATTERN: High number of timeout failures detected"
  } else {
    $cgnatPattern = "No CGNAT connection limits detected"
    & $WriteLog "  NO CGNAT LIMITS: Connection capacity appears normal"
  }
  
  # Diagnosis and recommendations
  if ($cgnatLimitsDetected) {
    if ($successRate -lt 50) {
      & $WriteLog "  DIAGNOSIS: CGNAT has severe connection limits - may explain multi-stream failures"
      & $WriteLog "  IMPACT: Simultaneous connections to multiple services will fail"
      & $WriteLog "  RECOMMENDATION: Contact ISP about CGNAT connection limits or request static IP"
    } elseif ($timeoutFailures -gt $connectionFailures) {
      & $WriteLog "  DIAGNOSIS: CGNAT timeout issues - connections fail due to timeouts"
      & $WriteLog "  IMPACT: Apps may show 'something went wrong' errors during peak usage"
      & $WriteLog "  RECOMMENDATION: Monitor connection patterns and consider connection pooling"
    } else {
      & $WriteLog "  DIAGNOSIS: Some CGNAT connection issues detected"
      & $WriteLog "  IMPACT: Occasional multi-stream service failures"
      & $WriteLog "  RECOMMENDATION: Monitor and document specific failure patterns"
    }
  } else {
    & $WriteLog "  DIAGNOSIS: CGNAT connection capacity is adequate"
    & $WriteLog "  IMPACT: No CGNAT-related connection issues expected"
    & $WriteLog "  RECOMMENDATION: CGNAT is not the cause of connection issues"
  }
  
  return @{
    TotalConnections = $totalConnections
    SuccessfulConnections = $successCount
    FailedConnections = $failureCount
    SuccessRate = $successRate
    TimeoutFailures = $timeoutFailures
    ConnectionFailures = $connectionFailures
    CGNATLimitsDetected = $cgnatLimitsDetected
    CGNATPattern = $cgnatPattern
    Results = $results
    Diagnosis = if ($successRate -lt 50) { "SEVERE_LIMITS" } elseif ($cgnatLimitsDetected) { "MODERATE_LIMITS" } else { "NO_LIMITS" }
  }
}

function Test-DNSServerPerformance {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing DNS server performance for streaming domains..."
  & $WriteLog "This test measures resolution speed across different DNS servers"
  
  $dnsServers = @(
    @{ Name = "Google DNS"; Server = "8.8.8.8" },
    @{ Name = "Cloudflare DNS"; Server = "1.1.1.1" },
    @{ Name = "Quad9 DNS"; Server = "9.9.9.9" },
    @{ Name = "OpenDNS"; Server = "208.67.222.222" },
    @{ Name = "Comodo DNS"; Server = "8.26.56.26" }
  )
  
  $streamingDomains = @(
    @{ Name = "Netflix"; Domain = "netflix.com" },
    @{ Name = "Apple TV"; Domain = "tv.apple.com" },
    @{ Name = "YouTube"; Domain = "youtube.com" },
    @{ Name = "Twitch"; Domain = "twitch.tv" },
    @{ Name = "Disney+"; Domain = "disneyplus.com" },
    @{ Name = "Amazon Prime"; Domain = "primevideo.com" },
    @{ Name = "Hulu"; Domain = "hulu.com" },
    @{ Name = "HBO Max"; Domain = "hbomax.com" }
  )
  
  $results = @()
  
  foreach ($dnsServer in $dnsServers) {
    & $WriteLog "Testing $($dnsServer.Name) ($($dnsServer.Server))..."
    
    $serverResults = @()
    $totalTime = 0
    $successCount = 0
    $failureCount = 0
    $slowQueries = 0
    
    foreach ($domain in $streamingDomains) {
      try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resolution = Resolve-DnsName -Name $domain.Domain -Server $dnsServer.Server -ErrorAction Stop -DnsOnly
        $sw.Stop()
        
        if ($resolution -and $resolution.Count -gt 0) {
          $responseTime = $sw.ElapsedMilliseconds
          $totalTime += $responseTime
          $successCount++
          
          if ($responseTime -gt 500) {
            $slowQueries++
            & $WriteLog "  $($domain.Name) ($($domain.Domain)): SLOW (${responseTime}ms)"
          } else {
            & $WriteLog "  $($domain.Name) ($($domain.Domain)): OK (${responseTime}ms)"
          }
          
          $serverResults += @{
            Domain = $domain.Name
            Hostname = $domain.Domain
            ResponseTime = $responseTime
            Success = $true
            IPAddresses = $resolution.Count
            Error = $null
          }
        } else {
          $failureCount++
          $serverResults += @{
            Domain = $domain.Name
            Hostname = $domain.Domain
            ResponseTime = $null
            Success = $false
            IPAddresses = 0
            Error = "No resolution returned"
          }
          & $WriteLog "  $($domain.Name) ($($domain.Domain)): FAILED - No resolution"
        }
      } catch {
        $failureCount++
        $serverResults += @{
          Domain = $domain.Name
          Hostname = $domain.Domain
          ResponseTime = $null
          Success = $false
          IPAddresses = 0
          Error = $_.Exception.Message
        }
        & $WriteLog "  $($domain.Name) ($($domain.Domain)): FAILED - $($_.Exception.Message)"
      }
      
      Start-Sleep -Milliseconds 100
    }
    
    # Calculate server statistics
    $avgResponseTime = if ($successCount -gt 0) {
      [Math]::Round($totalTime / $successCount, 1)
    } else { 0 }
    
    $successRate = [Math]::Round(($successCount / $streamingDomains.Count) * 100, 1)
    $slowQueryPercent = [Math]::Round(($slowQueries / $successCount) * 100, 1)
    
    $results += @{
      DNSServer = $dnsServer.Name
      ServerIP = $dnsServer.Server
      AverageResponseTime = $avgResponseTime
      SuccessRate = $successRate
      SlowQueries = $slowQueries
      SlowQueryPercent = $slowQueryPercent
      TotalQueries = $streamingDomains.Count
      SuccessfulQueries = $successCount
      FailedQueries = $failureCount
      DomainResults = $serverResults
    }
    
    & $WriteLog "  Summary: $successRate% success, ${avgResponseTime}ms avg, $slowQueries slow queries"
    
    # Classify performance
    if ($successRate -eq 100 -and $avgResponseTime -lt 100) {
      & $WriteLog "  Performance: EXCELLENT"
    } elseif ($successRate -ge 95 -and $avgResponseTime -lt 200) {
      & $WriteLog "  Performance: GOOD"
    } elseif ($successRate -ge 80 -and $avgResponseTime -lt 500) {
      & $WriteLog "  Performance: FAIR"
    } else {
      & $WriteLog "  Performance: POOR"
    }
    
    Start-Sleep -Seconds 1
  }
  
  # Overall analysis
  $bestServer = if ($results -and $results.Count -gt 0) { 
    $results | Sort-Object { $_.AverageResponseTime + (100 - $_.SuccessRate) } | Select-Object -First 1 
  } else { $null }
  $worstServer = if ($results -and $results.Count -gt 0) { 
    $results | Sort-Object { $_.AverageResponseTime + (100 - $_.SuccessRate) } | Select-Object -Last 1 
  } else { $null }
  
  $overallAvgTime = if ($results -and $results.Count -gt 0) {
    $validResults = $results | Where-Object { $_.AverageResponseTime -gt 0 }
    if ($validResults -and $validResults.Count -gt 0) {
      [Math]::Round(($validResults | Measure-Object -Property AverageResponseTime -Average).Average, 1)
    } else { 0 }
  } else { 0 }
  
  $overallSuccessRate = if ($results -and $results.Count -gt 0) {
    [Math]::Round(($results | Measure-Object -Property SuccessRate -Average).Average, 1)
  } else { 0 }
  
  & $WriteLog "DNS Server Performance Analysis:"
  & $WriteLog "  Overall average response time: ${overallAvgTime}ms"
  & $WriteLog "  Overall success rate: $overallSuccessRate%"
  
  if ($bestServer -and $bestServer.PSObject.Properties['DNSServer'] -and $bestServer.PSObject.Properties['AverageResponseTime']) {
    & $WriteLog "  Best performing server: $($bestServer.DNSServer) ($($bestServer.AverageResponseTime)ms avg)"
  } else {
    & $WriteLog "  Best performing server: No valid data available"
  }
  
  if ($worstServer -and $worstServer.PSObject.Properties['DNSServer'] -and $worstServer.PSObject.Properties['AverageResponseTime']) {
    & $WriteLog "  Worst performing server: $($worstServer.DNSServer) ($($worstServer.AverageResponseTime)ms avg)"
  } else {
    & $WriteLog "  Worst performing server: No valid data available"
  }
  
  # Check for DNS issues
  $dnsIssues = @()
  if ($overallAvgTime -gt 500) {
    $dnsIssues += "Slow DNS resolution (>500ms average)"
  }
  if ($overallSuccessRate -lt 90) {
    $dnsIssues += "High DNS failure rate (<90% success)"
  }
  
  $serversWithSlowQueries = @($results | Where-Object { $_.SlowQueryPercent -gt 50 }).Count
  if ($serversWithSlowQueries -gt 0) {
    $dnsIssues += "$serversWithSlowQueries DNS servers have >50% slow queries"
  }
  
  if ($dnsIssues.Count -gt 0) {
    & $WriteLog "  DNS Issues Detected:"
    foreach ($issue in $dnsIssues) {
      & $WriteLog "    - $issue"
    }
    & $WriteLog "  DIAGNOSIS: DNS performance issues may cause app timeouts"
    & $WriteLog "  RECOMMENDATION: Switch to faster DNS servers or investigate DNS configuration"
  } else {
    & $WriteLog "  DIAGNOSIS: DNS performance is acceptable"
    & $WriteLog "  RECOMMENDATION: DNS is not likely causing connection issues"
  }
  
  return @{
    OverallAverageTime = $overallAvgTime
    OverallSuccessRate = $overallSuccessRate
    BestServer = $bestServer
    WorstServer = $worstServer
    DNSIssues = $dnsIssues
    ServerResults = $results
    Diagnosis = if ($dnsIssues.Count -gt 0) { "DNS_PERFORMANCE_ISSUES" } else { "DNS_PERFORMANCE_OK" }
  }
}

function Test-SustainedConnection {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing sustained connection stability..."
  & $WriteLog "This test holds TCP connections open for 10+ seconds to simulate streaming"
  
  $streamingServices = @(
    @{ Name = "Netflix"; Host = "netflix.com"; Port = 443 },
    @{ Name = "Apple TV"; Host = "tv.apple.com"; Port = 443 },
    @{ Name = "YouTube"; Host = "youtube.com"; Port = 443 },
    @{ Name = "Twitch"; Host = "twitch.tv"; Port = 443 },
    @{ Name = "Disney+"; Host = "disneyplus.com"; Port = 443 }
  )
  
  $results = @()
  
  foreach ($service in $streamingServices) {
    & $WriteLog "Testing sustained connection to $($service.Name)..."
    
    $connectionResults = @()
    $totalTestTime = 15  # seconds
    
    try {
      $tcpClient = New-Object System.Net.Sockets.TcpClient
      $tcpClient.ReceiveTimeout = 10000
      $tcpClient.SendTimeout = 10000
      
      # Establish connection
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $tcpClient.Connect($service.Host, $service.Port)
      $connectionTime = $sw.ElapsedMilliseconds
      
      if ($tcpClient.Connected) {
        & $WriteLog "  Connection established: ${connectionTime}ms"
        
        # Monitor connection for sustained period
        $startTime = Get-Date
        $endTime = $startTime.AddSeconds($totalTestTime)
        $checkInterval = 2  # Check every 2 seconds
        
        $connectionStable = $true
        $disconnectionTime = $null
        
        while ((Get-Date) -lt $endTime -and $connectionStable) {
          try {
            # Test if connection is still alive by checking if we can read/write
            $stream = $tcpClient.GetStream()
            
            # Send a small keep-alive-like data (HTTP HEAD request)
            $request = "HEAD / HTTP/1.1`r`nHost: $($service.Host)`r`nConnection: keep-alive`r`n`r`n"
            $requestBytes = [System.Text.Encoding]::ASCII.GetBytes($request)
            
            $stream.Write($requestBytes, 0, $requestBytes.Length)
            
            # Try to read response (with short timeout)
            $stream.ReadTimeout = 2000
            $buffer = New-Object byte[] 1024
            $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
            
            $elapsedSeconds = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
            & $WriteLog "  [$($elapsedSeconds)s] Connection stable (${bytesRead} bytes received)"
            
            $connectionResults += @{
              Time = $elapsedSeconds
              Status = "STABLE"
              BytesReceived = $bytesRead
              Error = $null
            }
            
          } catch {
            $connectionStable = $false
            $disconnectionTime = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
            & $WriteLog "  [$($disconnectionTime)s] Connection lost: $($_.Exception.Message)"
            
            $connectionResults += @{
              Time = $disconnectionTime
              Status = "LOST"
              BytesReceived = 0
              Error = $_.Exception.Message
            }
          }
          
          Start-Sleep -Seconds $checkInterval
        }
        
        # Close connection
        $tcpClient.Close()
        
        # Analyze sustained connection results
        $totalDuration = if ($disconnectionTime) { $disconnectionTime } else { $totalTestTime }
        $stableDuration = if ($disconnectionTime) { $disconnectionTime - 2 } else { $totalTestTime }
        $stabilityPercent = [Math]::Round(($stableDuration / $totalTestTime) * 100, 1)
        
        $results += @{
          Service = $service.Name
          Host = $service.Host
          ConnectionTime = $connectionTime
          TotalDuration = $totalDuration
          StableDuration = $stableDuration
          StabilityPercent = $stabilityPercent
          ConnectionLost = if ($disconnectionTime) { $true } else { $false }
          DisconnectionTime = $disconnectionTime
          ConnectionResults = $connectionResults
        }
        
        & $WriteLog "  Summary: $stabilityPercent% stable over ${totalDuration}s"
        
        # Classify stability
        if ($stabilityPercent -eq 100) {
          & $WriteLog "  Stability: EXCELLENT"
        } elseif ($stabilityPercent -ge 90) {
          & $WriteLog "  Stability: GOOD"
        } elseif ($stabilityPercent -ge 70) {
          & $WriteLog "  Stability: FAIR"
        } else {
          & $WriteLog "  Stability: POOR"
        }
        
      } else {
        & $WriteLog "  Failed to establish connection"
        $results += @{
          Service = $service.Name
          Host = $service.Host
          ConnectionTime = $connectionTime
          TotalDuration = 0
          StableDuration = 0
          StabilityPercent = 0
          ConnectionLost = $true
          DisconnectionTime = 0
          ConnectionResults = @()
          Error = "Failed to establish initial connection"
        }
      }
      
    } catch {
      & $WriteLog "  Connection error: $($_.Exception.Message)"
      $results += @{
        Service = $service.Name
        Host = $service.Host
        ConnectionTime = $null
        TotalDuration = 0
        StableDuration = 0
        StabilityPercent = 0
        ConnectionLost = $true
        DisconnectionTime = 0
        ConnectionResults = @()
        Error = $_.Exception.Message
      }
    }
    
    Start-Sleep -Seconds 2
  }
  
  # Overall analysis
  $stableConnections = $results | Where-Object { $_.StabilityPercent -ge 90 }
  $failedConnections = $results | Where-Object { $_.ConnectionLost -eq $true -or $_.StabilityPercent -lt 70 }
  
  $avgStability = [Math]::Round(($results | Where-Object { $_.StabilityPercent -gt 0 } | Measure-Object -Property StabilityPercent -Average).Average, 1)
  $avgConnectionTime = [Math]::Round(($results | Where-Object { $null -ne $_.ConnectionTime } | Measure-Object -Property ConnectionTime -Average).Average, 1)
  
  & $WriteLog "Sustained Connection Analysis:"
  & $WriteLog "  Average stability: $avgStability%"
  & $WriteLog "  Average connection time: ${avgConnectionTime}ms"
  & $WriteLog "  Stable connections: $($stableConnections.Count)/$($streamingServices.Count)"
  & $WriteLog "  Failed/problematic connections: $($failedConnections.Count)/$($streamingServices.Count)"
  
  if ($failedConnections.Count -gt 0) {
    & $WriteLog "  Services with connection issues:"
    foreach ($service in $failedConnections) {
      $issue = if ($service.PSObject.Properties['Error'] -and $null -ne $service.Error) { $service.Error } else { "$($service.StabilityPercent)% stability" }
      & $WriteLog "    - $($service.Service): $issue"
    }
  }
  
  # Diagnosis
  if ($avgStability -lt 70) {
    & $WriteLog "  DIAGNOSIS: Major sustained connection issues - connections drop during streaming"
    & $WriteLog "  IMPACT: Streaming services will frequently disconnect or show errors"
    & $WriteLog "  RECOMMENDATION: Investigate network stability, ISP connection limits, or router issues"
  } elseif ($failedConnections.Count -gt ($streamingServices.Count * 0.3)) {
    & $WriteLog "  DIAGNOSIS: Multiple services have sustained connection problems"
    & $WriteLog "  IMPACT: Some streaming services will be unreliable"
    & $WriteLog "  RECOMMENDATION: Check for service-specific routing issues or DNS problems"
  } elseif ($avgConnectionTime -gt 3000) {
    & $WriteLog "  DIAGNOSIS: Slow connection establishment but stable once connected"
    & $WriteLog "  IMPACT: Apps may timeout during initial connection but work once connected"
    & $WriteLog "  RECOMMENDATION: Increase app timeout settings or investigate connection path"
  } else {
    & $WriteLog "  DIAGNOSIS: Sustained connection performance is good"
    & $WriteLog "  IMPACT: Streaming services should work reliably"
    & $WriteLog "  RECOMMENDATION: Connection stability is not the cause of streaming issues"
  }
  
  return @{
    AverageStability = $avgStability
    AverageConnectionTime = $avgConnectionTime
    StableConnections = $stableConnections.Count
    FailedConnections = $failedConnections.Count
    TotalServices = $streamingServices.Count
    ServiceResults = $results
    Diagnosis = if ($avgStability -lt 70) { "MAJOR_STABILITY_ISSUES" } elseif ($failedConnections.Count -gt ($streamingServices.Count * 0.3)) { "MULTIPLE_SERVICE_ISSUES" } elseif ($avgConnectionTime -gt 3000) { "SLOW_CONNECTION_ESTABLISHMENT" } else { "GOOD_STABILITY" }
  }
}

function Test-LargePacketHandling {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing large packet handling with Don't Fragment flag..."
  & $WriteLog "This test validates MTU configuration with different packet sizes"
  
  $testHost = '1.1.1.1'
  $packetSizes = @(64, 128, 256, 512, 1024, 1472, 1492)
  $results = @()
  
  foreach ($size in $packetSizes) {
    & $WriteLog "Testing packet size: $size bytes..."
    
    $success = $false
    $latency = $null
    $errorMessage = $null
    
    try {
      # Test with specific buffer size
      $ping = Test-Connection -TargetName $testHost -Count 1 -BufferSize $size -TimeoutSeconds 3 -ErrorAction Stop
      
      if ($ping -and ($ping.PSObject.Properties['ResponseTime'] -or $ping.PSObject.Properties['Latency'])) {
        $success = $true
        $latency = if ($ping.PSObject.Properties['ResponseTime']) { $ping.ResponseTime } else { $ping.Latency }
        & $WriteLog "  $size bytes: SUCCESS (${latency}ms)"
      } else {
        $errorMessage = "No response received"
        & $WriteLog "  $size bytes: FAILED - No response"
      }
    } catch {
      $errorMessage = $_.Exception.Message
      
      # Check for specific MTU-related errors
      if ($_.Exception.Message -match "fragment|MTU|too large") {
        & $WriteLog "  $size bytes: FAILED - MTU/Fragmentation issue: $errorMessage"
      } else {
        & $WriteLog "  $size bytes: FAILED - $errorMessage"
      }
    }
    
    $results += @{
      PacketSize = $size
      Success = $success
      Latency = $latency
      Error = $errorMessage
      MTUIssue = if ($errorMessage -and $errorMessage -match "fragment|MTU|too large") { $true } else { $false }
    }
    
    Start-Sleep -Milliseconds 500
  }
  
  # Analyze results
  $successfulSizes = $results | Where-Object { $_.Success }
  $failedSizes = $results | Where-Object { -not $_.Success }
  $mtuIssues = $results | Where-Object { $_.MTUIssue }
  
  $maxSuccessfulSize = if ($successfulSizes) { ($successfulSizes | Measure-Object -Property PacketSize -Maximum).Maximum } else { 0 }
  $minFailedSize = if ($failedSizes) { ($failedSizes | Measure-Object -Property PacketSize -Minimum).Minimum } else { 0 }
  
  & $WriteLog "Large Packet Handling Analysis:"
  & $WriteLog "  Successful packet sizes: $($successfulSizes.Count)/$($packetSizes.Count)"
  & $WriteLog "  Maximum successful size: $maxSuccessfulSize bytes"
  & $WriteLog "  Failed packet sizes: $($failedSizes.Count)"
  & $WriteLog "  MTU-related failures: $($mtuIssues.Count)"
  
  if ($mtuIssues.Count -gt 0) {
    & $WriteLog "  MTU Issues Detected:"
    foreach ($issue in $mtuIssues) {
      & $WriteLog "    - $($issue.PacketSize) bytes: $($issue.Error)"
    }
  }
  
  # Determine MTU configuration
  $mtuConfigured = $false
  
  if ($maxSuccessfulSize -ge 1472 -and $failedSizes.Count -eq 0) {
    $mtuConfigured = $true
    & $WriteLog "  MTU Status: OPTIMAL - All packet sizes work correctly"
  } elseif ($maxSuccessfulSize -ge 1024 -and $mtuIssues.Count -eq 0) {
    $mtuConfigured = $true
    & $WriteLog "  MTU Status: ADEQUATE - Most packet sizes work correctly"
  } elseif ($mtuIssues.Count -gt 0) {
    $mtuConfigured = $false
    & $WriteLog "  MTU Status: FRAGMENTATION ISSUES - Some large packets fail"
  } elseif ($maxSuccessfulSize -lt 512) {
    $mtuConfigured = $false
    & $WriteLog "  MTU Status: SEVERE LIMITATIONS - Only small packets work"
  } else {
    $mtuConfigured = $true
    & $WriteLog "  MTU Status: ACCEPTABLE - Reasonable packet size support"
  }
  
  # Calculate recommended MTU
  $recommendedMTU = if ($maxSuccessfulSize -gt 0) { $maxSuccessfulSize + 28 } else { 576 }
  
  # Diagnosis and recommendations
  if (-not $mtuConfigured) {
    if ($mtuIssues.Count -gt 0) {
      & $WriteLog "  DIAGNOSIS: MTU fragmentation issues - large packets are being fragmented or dropped"
      & $WriteLog "  IMPACT: Streaming video may have quality issues or frequent buffering"
      & $WriteLog "  RECOMMENDATION: Configure MTU to $recommendedMTU or enable PMTUD"
    } else {
      & $WriteLog "  DIAGNOSIS: Severe packet size limitations - only small packets work"
      & $WriteLog "  IMPACT: Streaming services may fail to load or have poor quality"
      & $WriteLog "  RECOMMENDATION: Contact ISP about network configuration or try different connection"
    }
  } else {
    & $WriteLog "  DIAGNOSIS: MTU configuration is working correctly"
    & $WriteLog "  IMPACT: Packet size is not limiting streaming performance"
    & $WriteLog "  RECOMMENDATION: MTU is not the cause of streaming issues"
  }
  
  return @{
    MaxSuccessfulSize = $maxSuccessfulSize
    MinFailedSize = $minFailedSize
    SuccessfulSizes = $successfulSizes.Count
    FailedSizes = $failedSizes.Count
    MTUIssues = $mtuIssues.Count
    MTUConfigured = $mtuConfigured
    RecommendedMTU = $recommendedMTU
    PacketResults = $results
    Diagnosis = if (-not $mtuConfigured) { if ($mtuIssues.Count -gt 0) { "MTU_FRAGMENTATION_ISSUES" } else { "SEVERE_PACKET_LIMITATIONS" } } else { "MTU_CONFIGURATION_OK" }
  }
}

function Test-PortExhaustionDetection {
  <#
  .SYNOPSIS
  Enhanced port exhaustion test to detect CGNAT connection limits
  .DESCRIPTION
  Opens 100+ simultaneous connections to different hosts and tracks which succeed/fail.
  This specifically tests CGNAT port allocation limits that cause streaming failures.
  #>
  param(
    [int]$ConnectionCount = 150,
    [int]$ConnectionTimeoutSeconds = 10,
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Testing CGNAT port exhaustion limits..."
  & $WriteLog "This test opens $ConnectionCount simultaneous connections to detect port limits"
  & $WriteLog "CGNAT shares one public IP among many customers - insufficient ports cause failures"
  
  # Diverse test hosts to test different IP ranges
  $testHosts = @(
    @{ Name = "Google DNS"; Host = "8.8.8.8"; Port = 53 },
    @{ Name = "Cloudflare DNS"; Host = "1.1.1.1"; Port = 53 },
    @{ Name = "Quad9 DNS"; Host = "9.9.9.9"; Port = 53 },
    @{ Name = "OpenDNS"; Host = "208.67.222.222"; Port = 53 },
    @{ Name = "Google HTTPS"; Host = "google.com"; Port = 443 },
    @{ Name = "Cloudflare HTTPS"; Host = "cloudflare.com"; Port = 443 },
    @{ Name = "GitHub"; Host = "github.com"; Port = 443 },
    @{ Name = "StackOverflow"; Host = "stackoverflow.com"; Port = 443 },
    @{ Name = "Reddit"; Host = "reddit.com"; Port = 443 },
    @{ Name = "Wikipedia"; Host = "wikipedia.org"; Port = 443 },
    @{ Name = "Netflix"; Host = "netflix.com"; Port = 443 },
    @{ Name = "YouTube"; Host = "youtube.com"; Port = 443 },
    @{ Name = "Apple"; Host = "apple.com"; Port = 443 },
    @{ Name = "Microsoft"; Host = "microsoft.com"; Port = 443 },
    @{ Name = "Amazon"; Host = "amazon.com"; Port = 443 },
    @{ Name = "Facebook"; Host = "facebook.com"; Port = 443 },
    @{ Name = "Twitter"; Host = "twitter.com"; Port = 443 },
    @{ Name = "LinkedIn"; Host = "linkedin.com"; Port = 443 },
    @{ Name = "Instagram"; Host = "instagram.com"; Port = 443 },
    @{ Name = "Spotify"; Host = "spotify.com"; Port = 443 },
    @{ Name = "Twitch"; Host = "twitch.tv"; Port = 443 },
    @{ Name = "Disney+"; Host = "disneyplus.com"; Port = 443 },
    @{ Name = "HBO Max"; Host = "hbomax.com"; Port = 443 },
    @{ Name = "Hulu"; Host = "hulu.com"; Port = 443 },
    @{ Name = "Prime Video"; Host = "primevideo.com"; Port = 443 },
    @{ Name = "Steam"; Host = "steamcommunity.com"; Port = 443 },
    @{ Name = "Discord"; Host = "discord.com"; Port = 443 },
    @{ Name = "Zoom"; Host = "zoom.us"; Port = 443 },
    @{ Name = "Teams"; Host = "teams.microsoft.com"; Port = 443 },
    @{ Name = "Slack"; Host = "slack.com"; Port = 443 }
  )
  
  $results = @()
  $successfulConnections = @()
  $failedConnections = @()
  
  & $WriteLog "Attempting to establish $ConnectionCount simultaneous connections..."
  
  # Create connection tasks
  $connectionTasks = @()
  $hostIndex = 0
  
  for ($i = 1; $i -le $ConnectionCount; $i++) {
    # Cycle through test hosts
    $testHost = $testHosts[$hostIndex % $testHosts.Count]
    $hostIndex++
    
    # Capture variables in local scope for closure
    $currentHost = $testHost
    $currentNum = $i
    $currentTimeout = $ConnectionTimeoutSeconds
    
    $task = [System.Threading.Tasks.Task]::Run({
      $hostInfo = $currentHost
      $connectionNum = $currentNum
      $timeoutSec = $currentTimeout
      
      try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = $timeoutSec * 1000
        $tcpClient.SendTimeout = $timeoutSec * 1000
        
        # Attempt connection with timeout
        $connectTask = $tcpClient.ConnectAsync($hostInfo.Host, $hostInfo.Port)
        $timeoutTask = [System.Threading.Tasks.Task]::Delay($timeoutSec * 1000)
        
        $completedTask = [System.Threading.Tasks.Task]::WaitAny($connectTask, $timeoutTask)
        
        if ($completedTask -eq 0 -and $tcpClient.Connected) {
          # Connection successful - hold it briefly
          Start-Sleep -Milliseconds 500
          $tcpClient.Close()
          
          return @{
            ConnectionNumber = $connectionNum
            Host = $hostInfo.Name
            Target = "$($hostInfo.Host):$($hostInfo.Port)"
            Success = $true
            Error = $null
            ErrorType = $null
            ConnectionTime = $null
          }
        } else {
          $tcpClient.Close()
          
          $errorType = if ($completedTask -eq 1) { "TIMEOUT" } else { "CONNECTION_FAILED" }
          return @{
            ConnectionNumber = $connectionNum
            Host = $hostInfo.Name
            Target = "$($hostInfo.Host):$($hostInfo.Port)"
            Success = $false
            Error = if ($completedTask -eq 1) { "Connection timeout" } else { "Connection failed" }
            ErrorType = $errorType
            ConnectionTime = $null
          }
        }
      } catch {
        return @{
          ConnectionNumber = $connectionNum
          Host = $hostInfo.Name
          Target = "$($hostInfo.Host):$($hostInfo.Port)"
          Success = $false
          Error = $_.Exception.Message
          ErrorType = "EXCEPTION"
          ConnectionTime = $null
        }
      }
    }.GetNewClosure())
    
    $connectionTasks += $task
  }
  
  # Monitor progress
  & $WriteLog "Waiting for all connection attempts to complete..."
  $completedCount = 0
  $progressInterval = 10  # Report progress every 10 connections
  
  while ($completedCount -lt $ConnectionCount) {
    $completedTasks = $connectionTasks | Where-Object { $_.IsCompleted }
    $newCompleted = $completedTasks.Count - $completedCount
    
    if ($newCompleted -ge $progressInterval -or $completedCount -eq 0) {
      $completedCount = $completedTasks.Count
      $successCount = ($completedTasks | Where-Object { $_.Result.Success }).Count
      $failureCount = $completedCount - $successCount
      
      & $WriteLog "  Progress: $completedCount/$ConnectionCount connections completed ($successCount successful, $failureCount failed)"
    }
    
    Start-Sleep -Milliseconds 500
  }
  
  # Wait for all to complete
  [System.Threading.Tasks.Task]::WaitAll($connectionTasks)
  
  # Collect results
  foreach ($task in $connectionTasks) {
    $result = $task.Result
    $results += $result
    
    if ($result.Success) {
      $successfulConnections += $result
    } else {
      $failedConnections += $result
    }
  }
  
  # Analyze results
  $totalConnections = $results.Count
  $successCount = $successfulConnections.Count
  $failureCount = $failedConnections.Count
  $successRate = [Math]::Round(($successCount / $totalConnections) * 100, 1)
  
  & $WriteLog "Port Exhaustion Test Results:"
  & $WriteLog "  Total connections attempted: $totalConnections"
  & $WriteLog "  Successful connections: $successCount"
  & $WriteLog "  Failed connections: $failureCount"
  & $WriteLog "  Success rate: $successRate%"
  
  # Analyze failure patterns
  $timeoutFailures = ($failedConnections | Where-Object { $_.ErrorType -eq "TIMEOUT" }).Count
  $connectionFailures = ($failedConnections | Where-Object { $_.ErrorType -eq "CONNECTION_FAILED" }).Count
  $exceptionFailures = ($failedConnections | Where-Object { $_.ErrorType -eq "EXCEPTION" }).Count
  
  & $WriteLog "  Failure breakdown:"
  & $WriteLog "    Timeouts: $timeoutFailures"
  & $WriteLog "    Connection failures: $connectionFailures"
  & $WriteLog "    Exceptions: $exceptionFailures"
  
  # Analyze success rate by connection number (detect port exhaustion threshold)
  $connectionsBySuccess = $results | Group-Object Success
  $successfulResults = if ($connectionsBySuccess | Where-Object { $_.Name -eq $true }) { $connectionsBySuccess | Where-Object { $_.Name -eq $true } | Select-Object -First 1 } else { $null }
  $failedResults = if ($connectionsBySuccess | Where-Object { $_.Name -eq $false }) { $connectionsBySuccess | Where-Object { $_.Name -eq $false } | Select-Object -First 1 } else { $null }
  
  if ($successfulResults -and $failedResults) {
    $successfulNumbers = $successfulResults.Group | ForEach-Object { $_.ConnectionNumber } | Sort-Object
    $failedNumbers = $failedResults.Group | ForEach-Object { $_.ConnectionNumber } | Sort-Object
    
    $minSuccessfulNumber = if ($successfulNumbers.Count -gt 0) { ($successfulNumbers | Measure-Object -Minimum).Minimum } else { $null }
    $maxSuccessfulNumber = if ($successfulNumbers.Count -gt 0) { ($successfulNumbers | Measure-Object -Maximum).Maximum } else { $null }
    $minFailedNumber = if ($failedNumbers.Count -gt 0) { ($failedNumbers | Measure-Object -Minimum).Minimum } else { $null }
    
    & $WriteLog "  Connection number analysis:"
    & $WriteLog "    Successful connections: #$minSuccessfulNumber to #$maxSuccessfulNumber"
    & $WriteLog "    First failure: #$minFailedNumber"
    
    # Detect port exhaustion threshold
    if ($minFailedNumber -and $maxSuccessfulNumber -and $minFailedNumber -le $maxSuccessfulNumber + 10) {
      $exhaustionThreshold = $minFailedNumber
      & $WriteLog "    *** PORT EXHAUSTION THRESHOLD: ~$exhaustionThreshold connections ***"
      & $WriteLog "    This suggests CGNAT port limit is reached around $exhaustionThreshold simultaneous connections"
    }
  }
  
  # Determine CGNAT capacity diagnosis
  $cgnatLimitsDetected = $false
  $cgnatPattern = ""
  $diagnosis = ""
  
  if ($successRate -lt 30) {
    $cgnatLimitsDetected = $true
    $cgnatPattern = "SEVERE_PORT_LIMITS"
    $diagnosis = "SEVERE_CGNAT_LIMITS"
    & $WriteLog "  *** SEVERE CGNAT LIMITS DETECTED ***"
    & $WriteLog "  Less than 30% of connections succeeded - CGNAT has very low port allocation"
  } elseif ($successRate -lt 60 -and $timeoutFailures -gt $connectionFailures) {
    $cgnatLimitsDetected = $true
    $cgnatPattern = "MODERATE_PORT_LIMITS_WITH_TIMEOUTS"
    $diagnosis = "MODERATE_CGNAT_LIMITS"
    & $WriteLog "  *** MODERATE CGNAT LIMITS DETECTED ***"
    & $WriteLog "  Timeout failures exceed connection failures - CGNAT port exhaustion with timeout pattern"
  } elseif ($timeoutFailures -gt ($totalConnections * 0.4)) {
    $cgnatLimitsDetected = $true
    $cgnatPattern = "HIGH_TIMEOUT_RATE"
    $diagnosis = "TIMEOUT_ISSUES"
    & $WriteLog "  *** HIGH TIMEOUT RATE DETECTED ***"
    & $WriteLog "  Over 40% of connections timed out - suggests CGNAT connection tracking issues"
  } elseif ($successRate -lt 80) {
    $cgnatLimitsDetected = $true
    $cgnatPattern = "SOME_PORT_LIMITS"
    $diagnosis = "SOME_CGNAT_LIMITS"
    & $WriteLog "  *** SOME CGNAT LIMITS DETECTED ***"
    & $WriteLog "  Success rate below 80% - CGNAT may have port allocation issues"
  } else {
    $cgnatPattern = "NO_SIGNIFICANT_LIMITS"
    $diagnosis = "CGNAT_CAPACITY_OK"
    & $WriteLog "  *** NO SIGNIFICANT CGNAT LIMITS DETECTED ***"
    & $WriteLog "  Success rate above 80% - CGNAT port capacity appears adequate"
  }
  
  # Impact analysis
  & $WriteLog "CGNAT Impact Analysis:"
  if ($cgnatLimitsDetected) {
    if ($diagnosis -eq "SEVERE_CGNAT_LIMITS") {
      & $WriteLog "  DIAGNOSIS: Severe CGNAT port limits - streaming will frequently fail"
      & $WriteLog "  IMPACT: Netflix/Twitch will show 'connection failed' errors constantly"
      & $WriteLog "  RECOMMENDATION: Contact ISP immediately - request static IP or CGNAT port limit increase"
    } elseif ($diagnosis -eq "MODERATE_CGNAT_LIMITS") {
      & $WriteLog "  DIAGNOSIS: Moderate CGNAT limits with timeout pattern"
      & $WriteLog "  IMPACT: Streaming will work but fail during peak usage or with multiple apps"
      & $WriteLog "  RECOMMENDATION: Monitor usage patterns, consider requesting static IP for heavy users"
    } elseif ($diagnosis -eq "TIMEOUT_ISSUES") {
      & $WriteLog "  DIAGNOSIS: CGNAT timeout issues - connection tracking problems"
      & $WriteLog "  IMPACT: Apps will show 'timeout' errors more than 'connection failed'"
      & $WriteLog "  RECOMMENDATION: ISP needs to fix CGNAT connection tracking configuration"
    } else {
      & $WriteLog "  DIAGNOSIS: Some CGNAT port allocation issues detected"
      & $WriteLog "  IMPACT: Occasional streaming failures, especially with multiple simultaneous apps"
      & $WriteLog "  RECOMMENDATION: Monitor and document specific failure scenarios"
    }
  } else {
    & $WriteLog "  DIAGNOSIS: CGNAT port capacity is adequate"
    & $WriteLog "  IMPACT: CGNAT is not limiting streaming performance"
    & $WriteLog "  RECOMMENDATION: Investigate other factors (routing, DNS, bandwidth, etc.)"
  }
  
  return @{
    TotalConnections = $totalConnections
    SuccessfulConnections = $successCount
    FailedConnections = $failureCount
    SuccessRate = $successRate
    TimeoutFailures = $timeoutFailures
    ConnectionFailures = $connectionFailures
    ExceptionFailures = $exceptionFailures
    CGNATLimitsDetected = $cgnatLimitsDetected
    CGNATPattern = $cgnatPattern
    Diagnosis = $diagnosis
    ExhaustionThreshold = if ($minFailedNumber -and $maxSuccessfulNumber -and $minFailedNumber -le $maxSuccessfulNumber + 10) { $minFailedNumber } else { $null }
    Results = $results
  }
}

function Test-BandwidthConsistencyAnalysis {
  <#
  .SYNOPSIS
  Tests sustained bandwidth consistency over time
  .DESCRIPTION
  Performs sustained transfers while graphing speed every second to detect:
  - Stable vs fluctuating throughput
  - Active rate limiting patterns
  - Thermal throttling or interference
  #>
  param(
    [int]$TestDurationSeconds = 60,
    [int]$SampleIntervalSeconds = 1,
    [string]$TestHost = 'httpbin.org',
    [string]$TestPath = '/bytes/1048576',  # 1MB chunks
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Testing bandwidth consistency over time..."
  & $WriteLog "Duration: $TestDurationSeconds seconds, sampling every $SampleIntervalSeconds second(s)"
  & $WriteLog "This will detect speed fluctuations, rate limiting, and stability issues"
  
  $results = @()
  $startTime = Get-Date
  $endTime = $startTime.AddSeconds($TestDurationSeconds)
  $sampleCount = 0
  
  # Test URL
  $testUrl = "https://$TestHost$TestPath"
  
  & $WriteLog "Test URL: $testUrl"
  & $WriteLog "Starting sustained bandwidth test..."
  
  while ((Get-Date) -lt $endTime) {
    $sampleCount++
    $currentTime = Get-Date
    $elapsedSeconds = [Math]::Round(($currentTime - $startTime).TotalSeconds, 1)
    
    & $WriteLog "Sample $sampleCount at ${elapsedSeconds}s..."
    
    $sampleResult = @{
      SampleNumber = $sampleCount
      Timestamp = $currentTime
      ElapsedSeconds = $elapsedSeconds
      DownloadSpeedMbps = $null
      DownloadTimeMs = $null
      BytesDownloaded = $null
      Success = $false
      Error = $null
    }
    
    try {
      # Download test chunk with timing
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $response = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
      $sw.Stop()
      
      if ($response.StatusCode -eq 200 -and $response.Content) {
        $downloadTimeMs = $sw.ElapsedMilliseconds
        $bytesDownloaded = $response.Content.Length
        $downloadSpeedMbps = [Math]::Round((($bytesDownloaded * 8) / ($downloadTimeMs / 1000)) / 1000000, 2)
        
        $sampleResult.DownloadSpeedMbps = $downloadSpeedMbps
        $sampleResult.DownloadTimeMs = $downloadTimeMs
        $sampleResult.BytesDownloaded = $bytesDownloaded
        $sampleResult.Success = $true
        
        & $WriteLog "  Download: ${downloadSpeedMbps} Mbps (${downloadTimeMs}ms, ${bytesDownloaded} bytes)"
      } else {
        $sampleResult.Error = "Invalid response: Status $($response.StatusCode)"
        & $WriteLog "  Download: FAILED - Invalid response"
      }
      
    } catch {
      $sampleResult.Error = $_.Exception.Message
      & $WriteLog "  Download: FAILED - $($_.Exception.Message)"
    }
    
    $results += $sampleResult
    
    # Wait for next sample
    $nextSampleTime = $currentTime.AddSeconds($SampleIntervalSeconds)
    if ($nextSampleTime -lt $endTime) {
      $waitMs = [Math]::Round(($nextSampleTime - (Get-Date)).TotalMilliseconds)
      if ($waitMs -gt 0) {
        Start-Sleep -Milliseconds $waitMs
      }
    }
  }
  
  # Analyze bandwidth consistency
  & $WriteLog "Bandwidth Consistency Analysis:"
  
  $successfulSamples = $results | Where-Object { $_.Success -eq $true }
  $totalSamples = $results.Count
  $successRate = if ($totalSamples -gt 0) { [Math]::Round(($successfulSamples.Count / $totalSamples) * 100, 1) } else { 0 }
  
  & $WriteLog "  Total samples: $totalSamples"
  & $WriteLog "  Successful samples: $($successfulSamples.Count)"
  & $WriteLog "  Success rate: $successRate%"
  
  if ($successfulSamples -and $successfulSamples.Count -gt 0) {
    $speeds = $successfulSamples | ForEach-Object { $_.DownloadSpeedMbps } | Where-Object { $_ -ne $null }
    
    if ($speeds -and $speeds.Count -gt 0) {
      $avgSpeed = [Math]::Round(($speeds | Measure-Object -Average).Average, 2)
      $minSpeed = [Math]::Round(($speeds | Measure-Object -Minimum).Minimum, 2)
      $maxSpeed = [Math]::Round(($speeds | Measure-Object -Maximum).Maximum, 2)
      $speedVariation = $maxSpeed - $minSpeed
      $speedVariationPercent = if ($avgSpeed -gt 0) { [Math]::Round(($speedVariation / $avgSpeed) * 100, 1) } else { 0 }
      
      & $WriteLog "  Speed statistics:"
      & $WriteLog "    Average: ${avgSpeed} Mbps"
      & $WriteLog "    Minimum: ${minSpeed} Mbps"
      & $WriteLog "    Maximum: ${maxSpeed} Mbps"
      & $WriteLog "    Variation: ${speedVariation} Mbps (${speedVariationPercent}%)"
      
      # Detect patterns
      $stableSpeed = $false
      $rateLimitingDetected = $false
      $patternType = ""
      
      # Check for rate limiting patterns (speed drops to specific values)
      $speedGroups = $speeds | Group-Object | Sort-Object Count -Descending
      $mostCommonSpeed = if ($speedGroups.Count -gt 0) { $speedGroups[0] } else { $null }
      
      if ($mostCommonSpeed -and $mostCommonSpeed.Count -gt ($speeds.Count * 0.3)) {
        $commonSpeed = [Math]::Round($mostCommonSpeed.Name, 2)
        & $WriteLog "  Most common speed: ${commonSpeed} Mbps ($($mostCommonSpeed.Count)/$($speeds.Count) samples)"
        
        # Check if this suggests rate limiting
        if ($mostCommonSpeed.Count -gt ($speeds.Count * 0.5)) {
          $rateLimitingDetected = $true
          $patternType = "RATE_LIMITING"
          & $WriteLog "  *** RATE LIMITING DETECTED: Speed frequently drops to ${commonSpeed} Mbps ***"
        }
      }
      
      # Check for speed stability
      if ($speedVariationPercent -lt 10) {
        $stableSpeed = $true
        $patternType = "STABLE"
        & $WriteLog "  Speed consistency: STABLE (${speedVariationPercent}% variation)"
      } elseif ($speedVariationPercent -lt 30) {
        $patternType = "MODERATELY_STABLE"
        & $WriteLog "  Speed consistency: MODERATELY STABLE (${speedVariationPercent}% variation)"
      } elseif ($speedVariationPercent -lt 60) {
        $patternType = "UNSTABLE"
        & $WriteLog "  Speed consistency: UNSTABLE (${speedVariationPercent}% variation)"
      } else {
        $patternType = "HIGHLY_VARIABLE"
        & $WriteLog "  Speed consistency: HIGHLY VARIABLE (${speedVariationPercent}% variation)"
      }
      
      # Check for progressive degradation
      $firstQuarter = $speeds | Select-Object -First ($speeds.Count / 4)
      $lastQuarter = $speeds | Select-Object -Last ($speeds.Count / 4)
      
      if ($firstQuarter -and $lastQuarter -and $firstQuarter.Count -gt 0 -and $lastQuarter.Count -gt 0) {
        $firstQuarterAvg = ($firstQuarter | Measure-Object -Average).Average
        $lastQuarterAvg = ($lastQuarter | Measure-Object -Average).Average
        
        if ($lastQuarterAvg -lt ($firstQuarterAvg * 0.7)) {
          $patternType = "PROGRESSIVE_DEGRADATION"
          & $WriteLog "  *** PROGRESSIVE DEGRADATION DETECTED ***"
          & $WriteLog "  First quarter: $([Math]::Round($firstQuarterAvg, 2)) Mbps vs Last quarter: $([Math]::Round($lastQuarterAvg, 2)) Mbps"
        }
      }
      
      # Time-based analysis
      $slowSamples = $successfulSamples | Where-Object { $_.DownloadSpeedMbps -lt ($avgSpeed * 0.5) }
      if ($slowSamples -and $slowSamples.Count -gt 0) {
        & $WriteLog "  Slow samples (<50% of average): $($slowSamples.Count)/$($successfulSamples.Count)"
        
        # Check if slow samples are clustered in time
        $slowTimes = $slowSamples | ForEach-Object { $_.ElapsedSeconds } | Sort-Object
        $clusters = 0
        $currentCluster = 0
        
        for ($i = 1; $i -lt $slowTimes.Count; $i++) {
          if ($slowTimes[$i] - $slowTimes[$i-1] -lt 5) {  # Within 5 seconds
            $currentCluster++
          } else {
            if ($currentCluster -gt 0) { $clusters++ }
            $currentCluster = 0
          }
        }
        if ($currentCluster -gt 0) { $clusters++ }
        
        if ($clusters -gt 0) {
          & $WriteLog "  Slow periods detected: $clusters separate clusters"
        }
      }
      
    } else {
      & $WriteLog "  No valid speed measurements available"
    }
  } else {
    & $WriteLog "  No successful downloads - cannot analyze bandwidth consistency"
  }
  
  # Diagnosis
  if ($successRate -lt 70) {
    & $WriteLog "  DIAGNOSIS: Poor download success rate - network connectivity issues"
    & $WriteLog "  IMPACT: Downloads will frequently fail or timeout"
    & $WriteLog "  RECOMMENDATION: Check network stability and DNS resolution"
  } elseif ($rateLimitingDetected) {
    & $WriteLog "  DIAGNOSIS: ISP rate limiting detected - speeds artificially capped"
    & $WriteLog "  IMPACT: Streaming quality will be limited by ISP throttling"
    & $WriteLog "  RECOMMENDATION: Contact ISP about rate limiting or consider different service plan"
  } elseif ($patternType -eq "PROGRESSIVE_DEGRADATION") {
    & $WriteLog "  DIAGNOSIS: Progressive bandwidth degradation - hardware or thermal issues"
    & $WriteLog "  IMPACT: Performance gets worse over time during sustained usage"
    & $WriteLog "  RECOMMENDATION: Check for overheating, hardware issues, or resource exhaustion"
  } elseif ($patternType -eq "HIGHLY_VARIABLE") {
    & $WriteLog "  DIAGNOSIS: Highly variable bandwidth - network instability or interference"
    & $WriteLog "  IMPACT: Streaming will have quality fluctuations and buffering"
    & $WriteLog "  RECOMMENDATION: Check for interference, unstable connections, or routing issues"
  } elseif ($patternType -eq "STABLE") {
    & $WriteLog "  DIAGNOSIS: Bandwidth is stable and consistent"
    & $WriteLog "  IMPACT: Bandwidth stability is not causing streaming issues"
    & $WriteLog "  RECOMMENDATION: Investigate other factors (connection patterns, protocols, etc.)"
  } else {
    & $WriteLog "  DIAGNOSIS: Bandwidth performance is acceptable with minor variations"
    & $WriteLog "  IMPACT: Minor bandwidth variations should not significantly affect streaming"
    & $WriteLog "  RECOMMENDATION: Monitor for specific usage patterns that cause issues"
  }
  
  return @{
    TotalSamples = $totalSamples
    SuccessfulSamples = $successfulSamples.Count
    SuccessRate = $successRate
    AverageSpeed = if ($successfulSamples) { [Math]::Round(($successfulSamples | Where-Object { $_.DownloadSpeedMbps } | Measure-Object -Property DownloadSpeedMbps -Average).Average, 2) } else { 0 }
    MinSpeed = if ($successfulSamples) { [Math]::Round(($successfulSamples | Where-Object { $_.DownloadSpeedMbps } | Measure-Object -Property DownloadSpeedMbps -Minimum).Minimum, 2) } else { 0 }
    MaxSpeed = if ($successfulSamples) { [Math]::Round(($successfulSamples | Where-Object { $_.DownloadSpeedMbps } | Measure-Object -Property DownloadSpeedMbps -Maximum).Maximum, 2) } else { 0 }
    SpeedVariation = if ($successfulSamples) { $maxSpeed - $minSpeed } else { 0 }
    SpeedVariationPercent = if ($successfulSamples -and $avgSpeed -gt 0) { [Math]::Round(($speedVariation / $avgSpeed) * 100, 1) } else { 0 }
    RateLimitingDetected = $rateLimitingDetected
    PatternType = $patternType
    StableSpeed = $stableSpeed
    Results = $results
  }
}

function Test-PortExhaustionDetectionQuick {
  <#
  .SYNOPSIS
  Quick port exhaustion detection for diagnostic workflow
  .DESCRIPTION
  Optimized version that tests 50 simultaneous connections in ~15 seconds
  to detect CGNAT port allocation limits without taking too long.
  #>
  param(
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Quick port exhaustion detection (50 connections, ~15 seconds)..."
  & $WriteLog "This test will detect CGNAT port allocation limits"
  
  $testHosts = @(
    'httpbin.org', 'google.com', 'cloudflare.com', '1.1.1.1', '8.8.8.8'
  )
  $connectionCount = 50
  $connectionTimeout = 8  # seconds
  
  $tasks = @()
  $successCount = 0
  $timeoutCount = 0
  $resetCount = 0
  $refusedCount = 0
  
  & $WriteLog "Creating $connectionCount simultaneous connection tasks..."
  
  for ($i = 1; $i -le $connectionCount; $i++) {
    $hostIndex = ($i - 1) % $testHosts.Count
    $targetHost = $testHosts[$hostIndex]
    $targetPort = 443
    
    $task = [System.Threading.Tasks.Task]::Run({
      param($targetHost, $targetPort, $timeout)
      
      try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = $timeout * 1000
        $tcpClient.Connect($targetHost, $targetPort)
        
        if ($tcpClient.Connected) {
          $tcpClient.Close()
          return @{ Status = 'SUCCESS'; Error = $null }
        } else {
          return @{ Status = 'FAILED'; Error = 'Connection not established' }
        }
      } catch {
        $errorMsg = $_.Exception.Message
        if ($errorMsg -like '*timeout*') {
          return @{ Status = 'TIMEOUT'; Error = $errorMsg }
        } elseif ($errorMsg -like '*reset*') {
          return @{ Status = 'RESET'; Error = $errorMsg }
        } elseif ($errorMsg -like '*refused*') {
          return @{ Status = 'REFUSED'; Error = $errorMsg }
        } else {
          return @{ Status = 'ERROR'; Error = $errorMsg }
        }
      }
    }, $targetHost, $targetPort, $connectionTimeout)
    
    $tasks += $task
  }
  
  & $WriteLog "Waiting for $connectionCount connections to complete..."
  
  # Wait for all tasks with timeout
  $allTasks = [System.Threading.Tasks.Task]::WaitAll($tasks, ($connectionTimeout + 5) * 1000)
  
  if (-not $allTasks) {
    & $WriteLog "Warning: Not all tasks completed within timeout"
  }
  
  # Collect results
  foreach ($task in $tasks) {
    if ($task.IsCompleted -and $null -ne $task.Result) {
      $result = $task.Result
      switch ($result.Status) {
        'SUCCESS' { $successCount++ }
        'TIMEOUT' { $timeoutCount++ }
        'RESET' { $resetCount++ }
        'REFUSED' { $refusedCount++ }
        default { }
      }
    } else {
      $timeoutCount++
    }
  }
  
  # Quick analysis
  $successRate = [Math]::Round(($successCount / $connectionCount) * 100, 1)
  $timeoutRate = [Math]::Round(($timeoutCount / $connectionCount) * 100, 1)
  $resetRate = [Math]::Round(($resetCount / $connectionCount) * 100, 1)
  $refusedRate = [Math]::Round(($refusedCount / $connectionCount) * 100, 1)
  
  & $WriteLog "Quick Port Exhaustion Detection Results:"
  & $WriteLog "  Total connections: $connectionCount"
  & $WriteLog "  Successful: $successCount ($successRate%)"
  & $WriteLog "  Timeouts: $timeoutCount ($timeoutRate%)"
  & $WriteLog "  Resets: $resetCount ($resetRate%)"
  & $WriteLog "  Refused: $refusedCount ($refusedRate%)"
  
  # Quick diagnosis
  $diagnosis = ""
  if ($timeoutRate -gt 60) {
    $diagnosis = "PORT_EXHAUSTION_LIKELY"
    & $WriteLog "  *** PORT EXHAUSTION DETECTED: $timeoutRate% timeouts ***"
    & $WriteLog "  CGNAT may be limiting concurrent connections"
  } elseif ($resetRate -gt 30) {
    $diagnosis = "HIGH_RESET_RATE"
    & $WriteLog "  *** HIGH RESET RATE: $resetRate% connections reset ***"
    & $WriteLog "  ISP or CGNAT is actively resetting connections"
  } elseif ($successRate -lt 70) {
    $diagnosis = "CONNECTION_ISSUES"
    & $WriteLog "  *** CONNECTION ISSUES: Only $successRate% successful ***"
  } else {
    $diagnosis = "PORT_ALLOCATION_OK"
    & $WriteLog "  Port allocation appears normal"
  }
  
  return @{
    TotalConnections = $connectionCount
    SuccessRate = $successRate
    TimeoutRate = $timeoutRate
    ResetRate = $resetRate
    RefusedRate = $refusedRate
    Diagnosis = $diagnosis
  }
}

function Test-BandwidthConsistencyAnalysisQuick {
  <#
  .SYNOPSIS
  Quick bandwidth consistency analysis for diagnostic workflow
  .DESCRIPTION
  Optimized version that downloads 5 chunks over 30 seconds to detect
  rate limiting and throughput stability without taking too long.
  #>
  param(
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Quick bandwidth consistency analysis (30 seconds, 5 chunks)..."
  & $WriteLog "This test will detect rate limiting and throughput stability"
  
  $testHost = 'httpbin.org'
  $testPath = '/bytes/1048576'  # 1MB chunks
  $chunkCount = 5
  $chunkInterval = 6  # seconds between chunks
  
  $results = @()
  $totalBytes = 0
  $totalTime = 0
  
  for ($i = 1; $i -le $chunkCount; $i++) {
    & $WriteLog "Downloading chunk $i/$chunkCount..."
    
    $chunkStart = Get-Date
    try {
      $webClient = New-Object System.Net.WebClient
      $webClient.Headers.Add('User-Agent', 'PPPoE-Diagnostic-Tool/1.0')
      
      $url = "https://$testHost$testPath"
      $data = $webClient.DownloadData($url)
      
      $chunkEnd = Get-Date
      $chunkDuration = ($chunkEnd - $chunkStart).TotalSeconds
      $chunkSize = $data.Length
      $chunkSpeed = [Math]::Round(($chunkSize / $chunkDuration) / 1024, 2)  # KB/s
      
      $results += @{
        ChunkNumber = $i
        Duration = [Math]::Round($chunkDuration, 2)
        Size = $chunkSize
        SpeedKBps = $chunkSpeed
        Timestamp = $chunkStart
      }
      
      $totalBytes += $chunkSize
      $totalTime += $chunkDuration
      
      & $WriteLog "  Chunk $i`: $chunkSpeed KB/s ($chunkSize bytes in $([Math]::Round($chunkDuration, 1))s)"
      
    } catch {
      & $WriteLog "  Chunk $i failed: $($_.Exception.Message)"
      $results += @{
        ChunkNumber = $i
        Duration = 0
        Size = 0
        SpeedKBps = 0
        Timestamp = Get-Date
        Error = $_.Exception.Message
      }
    }
    
    if ($i -lt $chunkCount) {
      Start-Sleep -Seconds $chunkInterval
    }
  }
  
  # Quick analysis
  $successfulChunks = $results | Where-Object { $_.Size -gt 0 }
  $avgSpeed = if ($successfulChunks) { [Math]::Round(($successfulChunks | Measure-Object -Property SpeedKBps -Average).Average, 2) } else { 0 }
  $minSpeed = if ($successfulChunks) { ($successfulChunks | Measure-Object -Property SpeedKBps -Minimum).Minimum } else { 0 }
  $maxSpeed = if ($successfulChunks) { ($successfulChunks | Measure-Object -Property SpeedKBps -Maximum).Maximum } else { 0 }
  $speedVariation = if ($avgSpeed -gt 0) { [Math]::Round((($maxSpeed - $minSpeed) / $avgSpeed) * 100, 1) } else { 0 }
  
  & $WriteLog "Quick Bandwidth Consistency Analysis Results:"
  & $WriteLog "  Successful chunks: $($successfulChunks.Count)/$chunkCount"
  & $WriteLog "  Average speed: $avgSpeed KB/s"
  & $WriteLog "  Speed range: $minSpeed - $maxSpeed KB/s"
  & $WriteLog "  Speed variation: $speedVariation%"
  
  # Quick diagnosis
  $diagnosis = ""
  if ($successfulChunks.Count -lt 3) {
    $diagnosis = "FREQUENT_FAILURES"
    & $WriteLog "  *** FREQUENT DOWNLOAD FAILURES DETECTED ***"
  } elseif ($speedVariation -gt 50) {
    $diagnosis = "HIGH_SPEED_VARIATION"
    & $WriteLog "  *** HIGH SPEED VARIATION: $speedVariation% ***"
    & $WriteLog "  Possible rate limiting or network instability"
  } elseif ($avgSpeed -lt 100) {
    $diagnosis = "LOW_BANDWIDTH"
    & $WriteLog "  *** LOW BANDWIDTH: $avgSpeed KB/s average ***"
  } else {
    $diagnosis = "BANDWIDTH_CONSISTENT"
    & $WriteLog "  Bandwidth appears consistent"
  }
  
  return @{
    SuccessfulChunks = $successfulChunks.Count
    AverageSpeedKBps = $avgSpeed
    MinSpeedKBps = $minSpeed
    MaxSpeedKBps = $maxSpeed
    SpeedVariationPercent = $speedVariation
    Diagnosis = $diagnosis
    Results = $results
  }
}

Export-ModuleMember -Function *
