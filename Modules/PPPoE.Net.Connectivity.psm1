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
      if ($result) {
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
      if ($ping) {
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
      if ($ping) {
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
      if ($ping) {
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
        if ($ping) {
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
      if ($ping) {
        $results += @{ Test = $i; Success = $true; Latency = $ping.ResponseTime }
        & $WriteLog "  Test $($i): OK ($($ping.ResponseTime)ms)"
      }
    } catch {
      $results += @{ Test = $i; Success = $false; Latency = $null }
      & $WriteLog "  Test $($i): FAIL"
    }
    Start-Sleep -Milliseconds 50
  }
  
  $successful = ($results | Where-Object { $_.Success }).Count
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

Export-ModuleMember -Function *
