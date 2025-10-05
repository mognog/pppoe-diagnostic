# PPPoE.HealthChecks.psm1 - Health checking orchestration functions

Set-StrictMode -Version 3.0

function Invoke-BasicSystemChecks {
  param(
    [hashtable]$Health,
    [scriptblock]$WriteLog
  )
  
  # [1] PowerShell 7+
  if (Test-PwshVersion7Plus) {
    $Health = Add-Health $Health 'PowerShell version' "OK ($($PSVersionTable.PSVersion))" 1
  } else {
    $Health = Add-Health $Health 'PowerShell version' "FAIL ($($PSVersionTable.PSVersion))" 1
  }
  
  # [2] Check for existing PPPoE connections
  $pppoeConnections = @()
  $testConnections = @('Rise PPPoE', 'PPPoE', 'Broadband Connection', 'Ransomeware_6G 2')
  
  foreach ($connName in $testConnections) {
    try {
      # Try to connect to see if the connection exists
      $result = & rasdial.exe $connName 2>&1
      $output = $result -join ' '
      
      # If we get error 651 (modem error) or similar, the connection exists but can't connect
      if ($output -match 'error (651|619|678|691)') {
        $pppoeConnections += $connName
        
        # Check if we have a physical adapter and its link state to provide better context
        $adapterContext = ""
        try {
          $testNic = Get-RecommendedAdapter
          if ($testNic) {
            if ($testNic.LinkSpeed -eq 0 -or $testNic.Status -ne 'Up') {
              $adapterContext = " (no physical link)"
            } else {
              $adapterContext = " (physical link present)"
            }
          }
        } catch {
          # Ignore adapter check errors
        }
        
        # Determine the likely cause based on the error code
        $reason = switch -regex ($output) {
          'error 651' { 'device/link error' }
          'error 619' { 'connection timeout' }
          'error 678' { 'no answer from remote' }
          'error 691' { 'authentication failed' }
          default { 'connection issue' }
        }
        & $WriteLog "Found PPPoE connection: $connName (exists but cannot connect - $reason)$adapterContext"
      }
    } catch {
      # Connection doesn't exist or other error
    }
  }
  
  if ($pppoeConnections.Count -gt 0) {
    & $WriteLog "Found existing PPPoE connections: $($pppoeConnections -join ', ')"
    $Health = Add-Health $Health 'PPPoE connections configured' "OK ($($pppoeConnections.Count) found: $($pppoeConnections -join ', '))" 2
    & $WriteLog "Credential sources available: Windows saved, credentials.ps1 file, script parameters"
  } else {
    & $WriteLog "No PPPoE connections configured in Windows"
    $Health = Add-Health $Health 'PPPoE connections configured' 'WARN (none found)' 2
    $Health = Add-Health $Health 'Credentials source' 'N/A' 3
    & $WriteLog "Tested connection names: $($testConnections -join ', ')"
    & $WriteLog "Available network connections:"
    try {
      $allConnections = Get-NetConnectionProfile | Select-Object -ExpandProperty Name
      & $WriteLog "$($allConnections -join ', ')"
    } catch {
      & $WriteLog "Could not retrieve network connections list"
    }
  }
  
  return @{
    Health = $Health
    PPPoEConnections = $pppoeConnections
  }
}

function Invoke-NetworkAdapterChecks {
  param(
    [hashtable]$Health,
    [string]$TargetAdapter,
    [scriptblock]$WriteLog
  )
  
  # [3] NIC selection
  $nic = $null
  if ($TargetAdapter) {
    try { 
      $nic = Get-NetAdapter -Name $TargetAdapter -ErrorAction Stop 
      & $WriteLog "Using specified adapter: $($nic.Name) / $($nic.InterfaceDescription) @ $($nic.LinkSpeed)"
    } catch { 
      & $WriteLog "Specified adapter '$TargetAdapter' not found, will show selection menu"
      $nic = $null 
    }
  }
  
  if (-not $nic) { 
    $nic = Select-NetworkAdapter -WriteLog $WriteLog
  }

  if ($null -eq $nic) {
    & $WriteLog "No Ethernet adapters detected"
    $Health = Add-Health $Health 'Physical adapter detected' 'FAIL (none found)' 3
    return @{
      Health = $Health
      Adapter = $null
      LinkDown = $true
    }
  } else {
    & $WriteLog "Selected adapter: $($nic.Name) / $($nic.InterfaceDescription) @ $($nic.LinkSpeed)"
    $Health = Add-Health $Health 'Physical adapter detected' "OK ($($nic.InterfaceDescription) @ $($nic.LinkSpeed))" 3
  }

  # [4] Link state gate
  if (Test-LinkUp -AdapterName $nic.Name) {
    $Health = Add-Health $Health 'Ethernet link state' 'OK (Up)' 4
    
    # [4.1] Hardware & Link-Layer Verification
    & $WriteLog ""
    & $WriteLog "=== HARDWARE & LINK-LAYER VERIFICATION ==="
    $linkHealth = Get-LinkHealth -NicName $nic.Name -WriteLog $WriteLog
    if ($linkHealth) {
      if ($linkHealth.ReceivedErrors -eq 0 -and $linkHealth.TransmitErrors -eq 0) {
        $Health = Add-Health $Health 'Link error counters' 'OK (No errors detected)' 4.1
      } elseif ($linkHealth.ReceivedErrors -lt 10 -and $linkHealth.TransmitErrors -lt 10) {
        $Health = Add-Health $Health 'Link error counters' "WARN (Rx:$($linkHealth.ReceivedErrors) Tx:$($linkHealth.TransmitErrors))" 4.1
      } else {
        $Health = Add-Health $Health 'Link error counters' "FAIL (Rx:$($linkHealth.ReceivedErrors) Tx:$($linkHealth.TransmitErrors))" 4.1
      }
    } else {
      $Health = Add-Health $Health 'Link error counters' 'FAIL (Could not retrieve stats)' 4.1
    }
    
    # [4.2] Driver Information
    $driverInfo = Get-AdapterDriverInfo -NicName $nic.Name -WriteLog $WriteLog
    if ($driverInfo -and $driverInfo.DeviceStatus -eq "OK") {
      $Health = Add-Health $Health 'Adapter driver' "OK ($($driverInfo.DriverProvider))" 4.2
    } else {
      $Health = Add-Health $Health 'Adapter driver' 'WARN (Driver status unknown)' 4.2
    }
    
    # [4.3] ONT Management Interface Check (optional - many ONTs don't expose this)
    $ontStatus = Test-ONTAvailability -WriteLog $WriteLog
    if ($ontStatus.Status -eq "OK") {
      $Health = Add-Health $Health 'ONT management' "OK ($($ontStatus.ReachableONTs.Count) accessible)" 4.3
    } else {
      $Health = Add-Health $Health 'ONT management' 'INFO (Not accessible - check LED status)' 4.3
    }
    
    # [4.4] ONT LED Reminder
    Show-ONTLEDReminder -WriteLog $WriteLog
    
    return @{
      Health = $Health
      Adapter = $nic
      LinkDown = $false
    }
    
  } else {
    & $WriteLog "Ethernet link is down (0 bps / Disconnected)"
    $Health = Add-Health $Health 'Ethernet link state' 'FAIL (Down)' 4
    $Health = Add-Health $Health 'Link error counters' 'N/A' 4.1
    $Health = Add-Health $Health 'Adapter driver' 'N/A' 4.2
    $Health = Add-Health $Health 'ONT availability' 'N/A' 4.3
    & $WriteLog "No physical connection, authentication aborted"
    
    # Skip PPP attempt if link is down - set all remaining checks to N/A
    $Health = Add-Health $Health 'Credentials source' 'N/A' 11
    $Health = Add-Health $Health 'PPPoE authentication' 'N/A' 12
    $Health = Add-Health $Health 'PPP interface present' 'N/A' 13
    $Health = Add-Health $Health 'PPP IPv4 assignment' 'N/A' 14
    $Health = Add-Health $Health 'Default route via PPP' 'N/A' 15
    $Health = Add-Health $Health 'PPPoE service status' 'N/A' 15.1
    $Health = Add-Health $Health 'PPP gateway assignment' 'N/A' 15.2
    $Health = Add-Health $Health 'Public IP classification' 'N/A' 16
    $Health = Add-Health $Health 'Gateway reachability' 'N/A' 17
    $Health = Add-Health $Health 'Ping (1.1.1.1) via PPP' 'N/A' 18
    $Health = Add-Health $Health 'Ping (8.8.8.8) via PPP' 'N/A' 19
    $Health = Add-Health $Health 'TCP connectivity' 'N/A' 19.1
    $Health = Add-Health $Health 'Multi-destination routing' 'N/A' 19.2
    $Health = Add-Health $Health 'Windows Firewall' 'N/A' 19.3
    $Health = Add-Health $Health 'MTU probe (DF)' 'N/A' 20
    
    return @{
      Health = $Health
      Adapter = $nic
      LinkDown = $true
    }
  }
}

function Invoke-PPPoEConnectionChecks {
  param(
    [hashtable]$Health,
    [string]$ConnectionNameToUse,
    [string]$UserName,
    [string]$Password,
    [string]$CredentialsFile,
    [scriptblock]$WriteLog
  )
  
  # Clean previous PPP state
  Disconnect-PPP -PppoeName $ConnectionNameToUse

  # Connect with fallback credential attempts
  & $WriteLog "Starting PPPoE connection attempts with fallback credential sources..."
  $res = Connect-PPPWithFallback -PppoeName $ConnectionNameToUse -UserName $UserName -Password $Password -CredentialsFile $CredentialsFile -WriteLog $WriteLog -AddHealth ${function:Add-Health}
  $out = ($res.Output -replace '[^\x00-\x7F]', '?')
  & $WriteLog "Final connection result: Method=$($res.Method), Success=$($res.Success), ExitCode=$($res.Code)"
  & $WriteLog "rasdial output:`n$out"

  # Map rasdial errors and update credentials source
  $authOk = $res.Success
  if ($authOk) { 
    $Health = Add-Health $Health 'PPPoE authentication' 'OK' 12
    # Update credentials source based on the method used
    $credSource = switch ($res.Method) {
      'Windows Saved' { 'OK (Using Windows saved credentials)' }
      'File' { "OK (Using credentials from file for: $($res.CredentialSource -replace 'credentials.ps1 file for user: ', ''))" }
      'Parameters' { "OK (Using script parameters for: $($res.CredentialSource -replace 'script parameters for user: ', ''))" }
      default { "OK (Using $($res.Method))" }
    }
    $Health = Add-Health $Health 'Credentials source' $credSource 11
  } else {
    $reason = switch ($res.Code) {
      691 { '691 bad credentials' }
      651 { '651 modem (device) error' }
      619 { '619 port disconnected' }
      678 { '678 no answer from remote' }
      default { "error $($res.Code)" }
    }
    $Health = Add-Health $Health 'PPPoE authentication' ("FAIL ($reason)") 12
    $Health = Add-Health $Health 'Credentials source' 'FAIL (All credential methods failed)' 11
  }
  
  return @{
    Health = $Health
    ConnectionResult = $res
    AuthenticationOk = $authOk
  }
}

function Invoke-PPPInterfaceChecks {
  param(
    [hashtable]$Health,
    [string]$ConnectionNameToUse,
    [scriptblock]$WriteLog
  )
  
  # [13-15] PPP Interface and Routing
  try {
    $pppIf = Get-PppInterface -PppoeName $ConnectionNameToUse
    if ($pppIf) {
      & $WriteLog "PPP interface detected: IfIndex $($pppIf.InterfaceIndex), '$($pppIf.InterfaceAlias)'"
      $Health = Add-Health $Health 'PPP interface present' ("OK (IfIndex $($pppIf.InterfaceIndex), '$($pppIf.InterfaceAlias)')") 13
      
      # [14] PPP IPv4 Assignment
      $pppIP = Get-PppIPv4 -IfIndex $pppIf.InterfaceIndex
      if ($pppIP) {
        $Health = Add-Health $Health 'PPP IPv4 assignment' ("OK ($($pppIP.IPAddress)/$($pppIP.PrefixLength))") 14
      } else {
        $Health = Add-Health $Health 'PPP IPv4 assignment' ("FAIL (no non-APIPA IPv4)") 14
      }
      
      # [15] Default Route via PPP
      if (Test-DefaultRouteVia -IfIndex $pppIf.InterfaceIndex) {
        $Health = Add-Health $Health 'Default route via PPP' 'OK' 15
      } else {
        $Health = Add-Health $Health 'Default route via PPP' 'WARN (still via other interface)' 15
        
        # [15.5] Try to adjust route metrics
        & $WriteLog "Attempting to adjust route metrics to prefer PPP interface..."
        if (Set-RouteMetrics -PppInterfaceIndex $pppIf.InterfaceIndex -WriteLog $WriteLog) {
          $Health = Add-Health $Health 'Route metric adjustment' 'OK (PPP interface preferred)' 15.5
        } else {
          $Health = Add-Health $Health 'Route metric adjustment' 'WARN (Could not adjust metrics)' 15.5
        }
      }
      
      # [15.1] PPPoE Service Status
      $pppoeSessionInfo = Get-PPPoESessionInfo -PppoeName $ConnectionNameToUse -WriteLog $WriteLog
      if ($pppoeSessionInfo -and $pppoeSessionInfo.ServiceStatus -eq "Running") {
        $Health = Add-Health $Health 'PPPoE service status' 'OK (RasMan running)' 15.1
      } else {
        $Health = Add-Health $Health 'PPPoE service status' 'WARN (Service status unknown)' 15.1
      }
      
      # [15.2] PPP Gateway Assignment
      $gatewayInfo = Get-PPPGatewayInfo -InterfaceAlias $pppIf.InterfaceAlias -WriteLog $WriteLog
      if ($gatewayInfo) {
        switch ($gatewayInfo.Status) {
          "OK" { $Health = Add-Health $Health 'PPP gateway assignment' "OK ($($gatewayInfo.Gateway))" 15.2 }
          "NO_GATEWAY" { $Health = Add-Health $Health 'PPP gateway assignment' 'FAIL (No gateway assigned)' 15.2 }
          "FAIL" { $Health = Add-Health $Health 'PPP gateway assignment' "FAIL (Gateway unreachable: $($gatewayInfo.Gateway))" 15.2 }
          default { $Health = Add-Health $Health 'PPP gateway assignment' "WARN ($($gatewayInfo.Status))" 15.2 }
        }
      } else {
        $Health = Add-Health $Health 'PPP gateway assignment' 'FAIL (Could not retrieve gateway info)' 15.2
      }
      
      return @{
        Health = $Health
        PPPInterface = $pppIf
        PPPIP = $pppIP
      }
      
    } else {
      $Health = Add-Health $Health 'PPP interface present' 'FAIL (not created/connected)' 13
      $Health = Add-Health $Health 'PPP IPv4 assignment' 'FAIL (no interface)' 14
      $Health = Add-Health $Health 'Default route via PPP' 'FAIL (no interface)' 15
      
      return @{
        Health = $Health
        PPPInterface = $null
        PPPIP = $null
      }
    }
  } catch {
    & $WriteLog "Error detecting PPP interface: $($_.Exception.Message)"
    $Health = Add-Health $Health 'PPP interface present' 'FAIL (error detecting interface)' 13
    $Health = Add-Health $Health 'PPP IPv4 assignment' 'FAIL (error detecting interface)' 14
    $Health = Add-Health $Health 'Default route via PPP' 'FAIL (error detecting interface)' 15
    
    return @{
      Health = $Health
      PPPInterface = $null
      PPPIP = $null
    }
  }
}

function Invoke-ConnectivityChecks {
  param(
    [hashtable]$Health,
    [object]$PPPInterface,
    [object]$PPPIP,
    [scriptblock]$WriteLog
  )
  
  if (-not $PPPIP) {
    return $Health
  }
  
  # Public IP classification & gateway reachability
  $cls = Get-IpClass -IPv4 $PPPIP.IPAddress
  switch ($cls) {
    'PUBLIC' { $Health = Add-Health $Health 'Public IP classification' 'OK (Public)' 16 }
    'CGNAT'  { $Health = Add-Health $Health 'Public IP classification' 'WARN (CGNAT 100.64/10)' 16 }
    'PRIVATE'{ $Health = Add-Health $Health 'Public IP classification' 'WARN (Private RFC1918)' 16 }
    'APIPA'  { $Health = Add-Health $Health 'Public IP classification' 'FAIL (APIPA)' 16 }
    default  { $Health = Add-Health $Health 'Public IP classification' "WARN ($cls)" 16 }
  }

  # Gateway (peer) reachability: ping default gateway of PPP if present
  $route = Get-NetRoute -InterfaceIndex $PPPInterface.InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
           Sort-Object -Property RouteMetric |
           Select-Object -First 1
  $gw = if ($route) { $route.NextHop } else { $null }
  if ($gw) {
    $okGw = Test-PingHost -TargetName $gw -Count 2 -TimeoutMs 1000 -Source $PPPIP.IPAddress
    if ($okGw) { $Health = Add-Health $Health 'Gateway reachability' 'OK' 17 }
    else { $Health = Add-Health $Health 'Gateway reachability' 'FAIL (unreachable)' 17 }
  } else {
    $Health = Add-Health $Health 'Gateway reachability' 'WARN (no default route record)' 17
  }

  # External ping via PPP (grouped together)
  $ok11 = Test-PingHost -TargetName '1.1.1.1' -Count 2 -TimeoutMs 1000 -Source $PPPIP.IPAddress
  $Health = Add-Health $Health 'Ping (1.1.1.1) via PPP' ($ok11 ? 'OK' : 'FAIL') 18
  
  $ok88 = Test-PingHost -TargetName '8.8.8.8' -Count 2 -TimeoutMs 1000 -Source $PPPIP.IPAddress
  $Health = Add-Health $Health 'Ping (8.8.8.8) via PPP' ($ok88 ? 'OK' : 'FAIL') 19
  
  # [19.1] TCP Connectivity Tests
  & $WriteLog ""
  & $WriteLog "=== TCP CONNECTIVITY TESTS ==="
  $tcpTests = @(
    @{ Name = "HTTPS (Cloudflare)"; IP = "1.1.1.1"; Port = 443 },
    @{ Name = "HTTPS (Google)"; IP = "8.8.8.8"; Port = 443 },
    @{ Name = "HTTP (Cloudflare)"; IP = "1.1.1.1"; Port = 80 }
  )
  
  $tcpSuccessCount = 0
  foreach ($test in $tcpTests) {
    $tcpResult = Test-TCPConnectivity -TargetIP $test.IP -Port $test.Port -WriteLog $WriteLog
    if ($tcpResult.Status -eq "SUCCESS") {
      $tcpSuccessCount++
    }
  }
  
  if ($tcpSuccessCount -eq $tcpTests.Count) {
    $Health = Add-Health $Health 'TCP connectivity' "OK ($tcpSuccessCount/$($tcpTests.Count) tests passed)" 19.1
  } elseif ($tcpSuccessCount -gt 0) {
    $Health = Add-Health $Health 'TCP connectivity' "WARN ($tcpSuccessCount/$($tcpTests.Count) tests passed)" 19.1
  } else {
    $Health = Add-Health $Health 'TCP connectivity' "FAIL (0/$($tcpTests.Count) tests passed)" 19.1
  }
  
  # [19.2] Multi-Destination Routing Analysis
  & $WriteLog ""
  & $WriteLog "=== MULTI-DESTINATION ROUTING ANALYSIS ==="
  $routingResults = Test-MultiDestinationRouting -WriteLog $WriteLog
  $completeRoutes = ($routingResults | Where-Object { $_.Status -eq "COMPLETE" }).Count
  $totalRoutes = $routingResults.Count
  
  if ($completeRoutes -eq $totalRoutes) {
    $Health = Add-Health $Health 'Multi-destination routing' "OK ($completeRoutes/$totalRoutes complete)" 19.2
  } elseif ($completeRoutes -gt 0) {
    $Health = Add-Health $Health 'Multi-destination routing' "WARN ($completeRoutes/$totalRoutes complete)" 19.2
  } else {
    $Health = Add-Health $Health 'Multi-destination routing' "FAIL (0/$totalRoutes complete)" 19.2
  }
  
  # [19.3] Firewall State Check
  & $WriteLog ""
  & $WriteLog "=== FIREWALL STATE CHECK ==="
  $firewallState = Test-FirewallState -WriteLog $WriteLog
  if ($firewallState) {
    $enabledProfiles = ($firewallState.Profiles | Where-Object { $_.Enabled }).Count
    if ($enabledProfiles -gt 0) {
      $Health = Add-Health $Health 'Windows Firewall' "WARN ($enabledProfiles profiles enabled)" 19.3
    } else {
      $Health = Add-Health $Health 'Windows Firewall' 'OK (All profiles disabled)' 19.3
    }
  } else {
    $Health = Add-Health $Health 'Windows Firewall' 'WARN (Could not check firewall state)' 19.3
  }

  # MTU probe (rough)
  # We try payload 1472 with DF; if success -> ~1492 MTU on PPP
  try {
    Test-Connection -TargetName '1.1.1.1' -Count 1 -DontFragment -BufferSize 1472 -TimeoutSeconds 2 -ErrorAction Stop | Out-Null
    $Health = Add-Health $Health 'MTU probe (DF)' 'OK (~1492, payload 1472)' 20
  } catch {
    $Health = Add-Health $Health 'MTU probe (DF)' 'WARN (payload 1472 blocked; lower MTU)' 20
  }

  # DNS Resolution Tests
  & $WriteLog "Testing DNS resolution capabilities..."
  $dnsResults = Test-DNSResolution -InterfaceAlias $PPPInterface.InterfaceAlias -WriteLog $WriteLog
  $dnsSuccess = ($dnsResults | Where-Object { $_.Status -eq 'OK' }).Count
  $dnsTotal = $dnsResults.Count
  if ($dnsSuccess -eq $dnsTotal) {
    $Health = Add-Health $Health 'DNS resolution' 'OK (All DNS servers working)' 21
  } elseif ($dnsSuccess -gt 0) {
    $Health = Add-Health $Health 'DNS resolution' "WARN ($dnsSuccess/$dnsTotal DNS servers working)" 21
  } else {
    $Health = Add-Health $Health 'DNS resolution' 'FAIL (No DNS servers working)' 21
  }

  # Packet Loss Test
  & $WriteLog "Testing packet loss to 1.1.1.1..."
  $packetLoss = Test-PacketLoss -TargetIP '1.1.1.1' -Count 20 -WriteLog $WriteLog
  if ($packetLoss.LossPercent -eq 0) {
    $Health = Add-Health $Health 'Packet loss test' "OK (0% loss, $($packetLoss.AvgLatency)ms avg)" 22
  } elseif ($packetLoss.LossPercent -le 2) {
    $Health = Add-Health $Health 'Packet loss test' "WARN ($($packetLoss.LossPercent)% loss, $($packetLoss.AvgLatency)ms avg)" 22
  } else {
    $Health = Add-Health $Health 'Packet loss test' "FAIL ($($packetLoss.LossPercent)% loss, $($packetLoss.AvgLatency)ms avg)" 22
  }

  # Route Stability Test
  & $WriteLog "Testing route stability to 8.8.8.8..."
  $routeStability = Test-RouteStability -TargetIP '8.8.8.8' -Count 5 -WriteLog $WriteLog
  if ($routeStability.Consistency -ge 80) {
    $Health = Add-Health $Health 'Route stability' "OK ($($routeStability.Consistency)% consistent)" 23
  } elseif ($routeStability.Consistency -ge 60) {
    $Health = Add-Health $Health 'Route stability' "WARN ($($routeStability.Consistency)% consistent)" 23
  } else {
    $Health = Add-Health $Health 'Route stability' "FAIL ($($routeStability.Consistency)% consistent)" 23
  }

  # Interface Statistics
  & $WriteLog "Checking PPP interface statistics..."
  $interfaceStats = Get-InterfaceStatistics -InterfaceName $PPPInterface.InterfaceAlias -WriteLog $WriteLog
  if ($interfaceStats -and $interfaceStats.Errors.Count -eq 0) {
    $Health = Add-Health $Health 'Interface statistics' 'OK (No errors detected)' 24
  } elseif ($interfaceStats) {
    $Health = Add-Health $Health 'Interface statistics' 'WARN (Some errors detected)' 24
  } else {
    $Health = Add-Health $Health 'Interface statistics' 'FAIL (Could not retrieve stats)' 24
  }

  return $Health
}

function Invoke-AdvancedConnectivityChecks {
  param(
    [hashtable]$Health,
    [object]$PPPInterface,
    [scriptblock]$WriteLog
  )
  
  # Advanced Connection Stability Tests
  & $WriteLog ""
  & $WriteLog "=== ADVANCED CONNECTION STABILITY TESTS ==="
  & $WriteLog "These tests will take approximately 15-25 seconds to complete..."
  
  # Quick Connectivity Check (catches very intermittent issues)
  & $WriteLog "Quick connectivity check..."
  $quickCheck = Test-QuickConnectivityCheck -TargetIP '1.1.1.1' -WriteLog $WriteLog
  if ($quickCheck.SuccessRate -eq 100) {
    $Health = Add-Health $Health 'Quick connectivity' "OK (100% success)" 25
  } elseif ($quickCheck.SuccessRate -ge 60) {
    $Health = Add-Health $Health 'Quick connectivity' "WARN ($($quickCheck.SuccessRate)% success)" 25
  } else {
    $Health = Add-Health $Health 'Quick connectivity' "FAIL ($($quickCheck.SuccessRate)% success)" 25
  }
  
  # Connection Jitter Test
  & $WriteLog "Testing connection jitter..."
  $jitterTest = Test-ConnectionJitter -TargetIP '1.1.1.1' -Count 15 -WriteLog $WriteLog
  if ($jitterTest.Jitter -le 10) {
    $Health = Add-Health $Health 'Connection jitter' "OK (${jitterTest.Jitter}ms jitter, ${jitterTest.AvgLatency}ms avg)" 26
  } elseif ($jitterTest.Jitter -le 50) {
    $Health = Add-Health $Health 'Connection jitter' "WARN (${jitterTest.Jitter}ms jitter, ${jitterTest.AvgLatency}ms avg)" 26
  } else {
    $Health = Add-Health $Health 'Connection jitter' "FAIL (${jitterTest.Jitter}ms jitter, ${jitterTest.AvgLatency}ms avg)" 26
  }

  # Burst Connectivity Test
  & $WriteLog "Testing burst connectivity..."
  $burstTest = Test-BurstConnectivity -TargetIP '1.1.1.1' -BurstSize 5 -BurstCount 3 -WriteLog $WriteLog
  if ($burstTest.AvgBurstSuccess -ge 90) {
    $Health = Add-Health $Health 'Burst connectivity' "OK (${burstTest.AvgBurstSuccess}% avg success)" 27
  } elseif ($burstTest.AvgBurstSuccess -ge 70) {
    $Health = Add-Health $Health 'Burst connectivity' "WARN (${burstTest.AvgBurstSuccess}% avg success)" 27
  } else {
    $Health = Add-Health $Health 'Burst connectivity' "FAIL (${burstTest.AvgBurstSuccess}% avg success)" 27
  }

  # Provider-Specific Diagnostics
  & $WriteLog "Running provider-specific diagnostics..."
  $providerDiagnostics = Test-ProviderSpecificDiagnostics -InterfaceAlias $PPPInterface.InterfaceAlias -WriteLog $WriteLog
  $providerSuccess = ($providerDiagnostics | Where-Object { $_.Status -eq 'OK' }).Count
  $providerTotal = $providerDiagnostics.Count
  if ($providerSuccess -eq $providerTotal) {
    $Health = Add-Health $Health 'Provider diagnostics' "OK (All $providerTotal tests passed)" 28
  } elseif ($providerSuccess -gt ($providerTotal * 0.7)) {
    $Health = Add-Health $Health 'Provider diagnostics' "WARN ($providerSuccess/$providerTotal tests passed)" 28
  } else {
    $Health = Add-Health $Health 'Provider diagnostics' "FAIL ($providerSuccess/$providerTotal tests passed)" 28
  }

  return $Health
}

function Invoke-TracerouteDiagnostics {
  param(
    [hashtable]$Health,
    [scriptblock]$WriteLog
  )
  
  # Traceroute diagnostics (may take up to ~60s each)
  & $WriteLog "Starting traceroute to 1.1.1.1 (may take up to 60s)..."
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c tracert -d -4 -w 1000 -h 20 1.1.1.1"
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    while (-not $proc.StandardOutput.EndOfStream) {
      $line = $proc.StandardOutput.ReadLine()
      & $WriteLog "[tracert 1.1.1.1] $line"
    }
    $proc.WaitForExit()
    $Health = Add-Health $Health 'Traceroute (1.1.1.1)' 'DONE' 29
  } catch {
    & $WriteLog "Traceroute 1.1.1.1 error: $($_.Exception.Message)"
    $Health = Add-Health $Health 'Traceroute (1.1.1.1)' 'ERROR' 29
  }

  & $WriteLog "Starting traceroute to 8.8.8.8 (may take up to 60s)..."
  try {
    $psi2 = New-Object System.Diagnostics.ProcessStartInfo
    $psi2.FileName = "cmd.exe"
    $psi2.Arguments = "/c tracert -d -4 -w 1000 -h 20 8.8.8.8"
    $psi2.RedirectStandardOutput = $true
    $psi2.UseShellExecute = $false
    $proc2 = [System.Diagnostics.Process]::Start($psi2)
    while (-not $proc2.StandardOutput.EndOfStream) {
      $line2 = $proc2.StandardOutput.ReadLine()
      & $WriteLog "[tracert 8.8.8.8] $line2"
    }
    $proc2.WaitForExit()
    $Health = Add-Health $Health 'Traceroute (8.8.8.8)' 'DONE' 30
  } catch {
    & $WriteLog "Traceroute 8.8.8.8 error: $($_.Exception.Message)"
    $Health = Add-Health $Health 'Traceroute (8.8.8.8)' 'ERROR' 30
  }
  
  return $Health
}

function Invoke-OptionalStabilityTest {
  param(
    [hashtable]$Health,
    [scriptblock]$WriteLog
  )
  
  # Optional: Connection Stability Test (60 seconds)
  & $WriteLog ""
  & $WriteLog "Would you like to run a 60-second connection stability test? (y/N)"
  $stabilityChoice = Read-Host
  if ($stabilityChoice -match '^[yY]') {
    $stabilityTest = Test-ConnectionStability -TargetIP '1.1.1.1' -DurationSeconds 60 -WriteLog $WriteLog
    if ($stabilityTest.UptimePercent -ge 95) {
      $Health = Add-Health $Health 'Connection stability' "OK ($($stabilityTest.UptimePercent)% uptime)" 31
    } elseif ($stabilityTest.UptimePercent -ge 90) {
      $Health = Add-Health $Health 'Connection stability' "WARN ($($stabilityTest.UptimePercent)% uptime)" 31
    } else {
      $Health = Add-Health $Health 'Connection stability' "FAIL ($($stabilityTest.UptimePercent)% uptime)" 31
    }
  } else {
    $Health = Add-Health $Health 'Connection stability' 'SKIP (User declined)' 31
  }
  
  return $Health
}

Export-ModuleMember -Function *
