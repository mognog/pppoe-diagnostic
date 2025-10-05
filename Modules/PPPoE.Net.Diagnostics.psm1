# PPPoE.Net.Diagnostics.psm1 - Network diagnostic functions

Set-StrictMode -Version 3.0

function Test-ONTAvailability {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing ONT (Optical Network Terminal) management interface..."
  & $WriteLog "NOTE: This tests if ONT management is accessible - many ONTs don't expose this"
  
  # Common ONT management IP addresses
  $ontIPs = @('192.168.1.1', '192.168.100.1', '192.168.0.1', '10.0.0.1')
  $ontResults = @()
  
  foreach ($ip in $ontIPs) {
    try {
      & $WriteLog "Testing ONT management at $ip... (testing 4 common addresses)"
      $ping = Test-Connection -TargetName $ip -Count 2 -TimeoutSeconds 3 -ErrorAction Stop
      if ($ping -and $ping.Count -gt 0) {
        $avgLatency = [Math]::Round(($ping | Measure-Object -Property Latency -Average).Average, 1)
        & $WriteLog "  ONT at $ip`: REACHABLE (${avgLatency}ms avg)"
        $ontResults += @{ IP = $ip; Status = "REACHABLE"; Latency = $avgLatency }
      } else {
        & $WriteLog "  ONT at $ip`: Not accessible"
        $ontResults += @{ IP = $ip; Status = "UNREACHABLE"; Latency = $null }
      }
    } catch {
      & $WriteLog "  ONT at $ip`: Not accessible"
      $ontResults += @{ IP = $ip; Status = "UNREACHABLE"; Latency = $null }
    }
  }
  
  # Check if any ONT is reachable
  $reachableONTs = $ontResults | Where-Object { $_.Status -eq "REACHABLE" }
  if ($reachableONTs -and $reachableONTs -is [array] -and $reachableONTs.Count -gt 0) {
    & $WriteLog "ONT Management: Accessible at $($reachableONTs.Count) address(es)"
    return @{ Status = "OK"; ReachableONTs = $reachableONTs; AllResults = $ontResults }
  } else {
    & $WriteLog "ONT Management: Not accessible (this is normal for many ONTs - check LED status instead)"
    return @{ Status = "FAIL"; ReachableONTs = @(); AllResults = $ontResults }
  }
}

function Show-ONTLEDReminder {
  param([scriptblock]$WriteLog)
  
  # Handle null WriteLog
  if (-not $WriteLog) {
    $WriteLog = { param($msg) Write-Host $msg }
  }
  
  & $WriteLog ""
  & $WriteLog "=== ONT LED STATUS CHECK ==="
  & $WriteLog "Please visually check your ONT (Optical Network Terminal) LEDs:"
  & $WriteLog ""
  & $WriteLog "Expected LED States (ONT models vary, check what you have):"
  & $WriteLog "  PON/Online: SOLID GREEN (most important - shows fiber sync)"
  & $WriteLog "  LAN: SOLID GREEN (when connected to router/computer)"
  & $WriteLog "  Power: SOLID GREEN (if present)"
  & $WriteLog "  LOS/Alarm: OFF (if present - shows no signal loss)"
  & $WriteLog ""
  & $WriteLog "If you see problems:"
  & $WriteLog "  - PON/Online not solid green: ONT not syncing with fiber network"
  & $WriteLog "  - Blinking red LOS/Alarm: Fiber cable issue or Openreach fault"
  & $WriteLog "  - All LEDs off: Power issue"
  & $WriteLog "  - LAN not green: Check Ethernet cable connection"
  & $WriteLog ""
  & $WriteLog "Press Enter to continue after checking LEDs..."
  $null = Read-Host
}

function Get-PPPGatewayInfo {
  param([string]$InterfaceAlias, [scriptblock]$WriteLog)
  
  try {
    & $WriteLog "Checking PPP gateway information for interface: $InterfaceAlias"
    
    # Get IP configuration for the PPP interface
    $ipConfig = Get-NetIPConfiguration -InterfaceAlias $InterfaceAlias -ErrorAction SilentlyContinue
    if ($ipConfig) {
      & $WriteLog "PPP Interface Configuration:"
      & $WriteLog "  IPv4 Address: $($ipConfig.IPv4Address.IPAddress)"
      & $WriteLog "  Subnet Mask: $($ipConfig.IPv4Address.PrefixLength)"
      & $WriteLog "  Gateway: $($ipConfig.IPv4DefaultGateway.NextHop)"
      
      # Check if gateway is reachable
      if ($ipConfig.IPv4DefaultGateway.NextHop) {
        $gateway = $ipConfig.IPv4DefaultGateway.NextHop
        try {
          $ping = Test-Connection -TargetName $gateway -Count 2 -TimeoutSeconds 2 -ErrorAction Stop
          if ($ping) {
            $avgLatency = [Math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 1)
            & $WriteLog "  Gateway Reachability: OK (${avgLatency}ms avg)"
            return @{ 
              Status = "OK"; 
              IPv4Address = $ipConfig.IPv4Address.IPAddress; 
              Gateway = $gateway; 
              GatewayLatency = $avgLatency 
            }
          } else {
            & $WriteLog "  Gateway Reachability: FAILED"
            return @{ 
              Status = "FAIL"; 
              IPv4Address = $ipConfig.IPv4Address.IPAddress; 
              Gateway = $gateway; 
              GatewayLatency = $null 
            }
          }
        } catch {
          & $WriteLog "  Gateway Reachability: ERROR - $($_.Exception.Message)"
          return @{ 
            Status = "ERROR"; 
            IPv4Address = $ipConfig.IPv4Address.IPAddress; 
            Gateway = $gateway; 
            GatewayLatency = $null; 
            Error = $_.Exception.Message 
          }
        }
      } else {
        & $WriteLog "  Gateway: NOT ASSIGNED"
        return @{ 
          Status = "NO_GATEWAY"; 
          IPv4Address = $ipConfig.IPv4Address.IPAddress; 
          Gateway = $null; 
          GatewayLatency = $null 
        }
      }
    } else {
      & $WriteLog "Could not retrieve IP configuration for $InterfaceAlias"
      return $null
    }
    
  } catch {
    & $WriteLog "Error checking PPP gateway info: $($_.Exception.Message)"
    return $null
  }
}

function Test-FirewallState {
  param([scriptblock]$WriteLog)
  
  try {
    & $WriteLog "Checking Windows Firewall state..."
    
    $firewallProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    $firewallResults = @()
    
    foreach ($firewallProfile in $firewallProfiles) {
      $status = if ($firewallProfile.Enabled) { "ENABLED" } else { "DISABLED" }
      & $WriteLog "  $($firewallProfile.Name) Profile: $status"
      $firewallResults += @{ Profile = $firewallProfile.Name; Enabled = $firewallProfile.Enabled }
    }
    
    # Check for ICMP (ping) firewall rules
    & $WriteLog "Checking ICMP firewall rules..."
    $icmpRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
      $_.DisplayName -match "ICMP|ICMPv4|Echo|Ping" -or
      $_.Name -match "ICMP|Echo"
    }
    
    if ($icmpRules) {
      $icmpInbound = $icmpRules | Where-Object { $_.Direction -eq "Inbound" -and $_.Enabled }
      $icmpOutbound = $icmpRules | Where-Object { $_.Direction -eq "Outbound" -and $_.Enabled }
      
      if ($icmpInbound) {
        # Safe array handling - Where-Object returns null when no matches found
        $allowResults = $icmpInbound | Where-Object { $_.Action -eq "Allow" }
        $blockResults = $icmpInbound | Where-Object { $_.Action -eq "Block" }
        $allowCount = if ($allowResults) { $allowResults.Count } else { 0 }
        $blockCount = if ($blockResults) { $blockResults.Count } else { 0 }
        & $WriteLog "  ICMP Inbound: $($icmpInbound.Count) active rules ($allowCount allow, $blockCount block)"
        
        # Show first few blocking rules
        if ($blockResults) {
          foreach ($rule in $blockResults | Select-Object -First 2) {
            & $WriteLog "    BLOCKING: $($rule.DisplayName) [$($rule.Profile)]"
          }
        }
      } else {
        & $WriteLog "  ICMP Inbound: No active rules (default policy applies)"
      }
      
      if ($icmpOutbound) {
        # Safe array handling
        $allowResults = $icmpOutbound | Where-Object { $_.Action -eq "Allow" }
        $blockResults = $icmpOutbound | Where-Object { $_.Action -eq "Block" }
        $allowCount = if ($allowResults) { $allowResults.Count } else { 0 }
        $blockCount = if ($blockResults) { $blockResults.Count } else { 0 }
        & $WriteLog "  ICMP Outbound: $($icmpOutbound.Count) active rules ($allowCount allow, $blockCount block)"
      } else {
        & $WriteLog "  ICMP Outbound: No active rules (default policy applies)"
      }
    } else {
      & $WriteLog "  ICMP Rules: No explicit ICMP rules found"
    }
    
    # Check for PPP-specific firewall rules
    $pppRules = Get-NetFirewallRule -DisplayName "*PPP*" -ErrorAction SilentlyContinue
    if ($pppRules) {
      & $WriteLog "Found $($pppRules.Count) PPP-related firewall rules"
      foreach ($rule in $pppRules | Select-Object -First 3) {
        $action = if ($rule.Action -eq "Allow") { "ALLOW" } else { "BLOCK" }
        & $WriteLog "  Rule: $($rule.DisplayName) - $action"
      }
    } else {
      & $WriteLog "No PPP-specific firewall rules found"
    }
    
    return @{
      Profiles = $firewallResults
      PPPRules = $pppRules
      ICMPRules = $icmpRules
    }
    
  } catch {
    & $WriteLog "Error checking firewall state: $($_.Exception.Message)"
    return $null
  }
}

function Test-StreamingServiceDNSAndTCP {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing streaming service DNS resolution and TCP connectivity..."
  & $WriteLog "This test performs complete connection flow for Netflix, Apple TV, YouTube specifically"
  
  $streamingServices = @(
    @{ Name = "Netflix"; Domain = "netflix.com"; Port = 443 },
    @{ Name = "Apple TV"; Domain = "tv.apple.com"; Port = 443 },
    @{ Name = "YouTube"; Domain = "youtube.com"; Port = 443 }
  )
  
  $results = @()
  
  foreach ($service in $streamingServices) {
    & $WriteLog "Testing $($service.Name) complete connection flow..."
    
    $serviceResult = @{
      Service = $service.Name
      Domain = $service.Domain
      Port = $service.Port
      DNSResolution = $null
      IPv4Addresses = @()
      IPv6Addresses = @()
      TCPConnection = $null
      Error = $null
    }
    
    # Step 1: DNS Resolution (both IPv4 and IPv6)
    try {
      & $WriteLog "  Step 1: DNS resolution for $($service.Domain)..."
      
      # IPv4 resolution
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $ipv4Resolution = Resolve-DnsName -Name $service.Domain -Type A -ErrorAction SilentlyContinue
      $sw.Stop()
      $ipv4ResolveTime = $sw.ElapsedMilliseconds
      
      if ($ipv4Resolution -and $ipv4Resolution.Count -gt 0) {
        $ipv4Addresses = $ipv4Resolution | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }
        $serviceResult.IPv4Addresses = $ipv4Addresses
        if ($ipv4Addresses.Count -gt 0) {
          & $WriteLog "    IPv4: $($ipv4Addresses.Count) addresses (${ipv4ResolveTime}ms) - $($ipv4Addresses -join ', ')"
        } else {
          & $WriteLog "    IPv4: No valid addresses resolved"
        }
      } else {
        & $WriteLog "    IPv4: No addresses resolved"
      }
      
      # IPv6 resolution
      $sw.Restart()
      $ipv6Resolution = Resolve-DnsName -Name $service.Domain -Type AAAA -ErrorAction SilentlyContinue
      $sw.Stop()
      $ipv6ResolveTime = $sw.ElapsedMilliseconds
      
      if ($ipv6Resolution -and $ipv6Resolution.Count -gt 0) {
        $ipv6Addresses = $ipv6Resolution | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }
        $serviceResult.IPv6Addresses = $ipv6Addresses
        if ($ipv6Addresses.Count -gt 0) {
          & $WriteLog "    IPv6: $($ipv6Addresses.Count) addresses (${ipv6ResolveTime}ms) - $($ipv6Addresses -join ', ')"
        } else {
          & $WriteLog "    IPv6: No valid addresses resolved"
        }
      } else {
        & $WriteLog "    IPv6: No addresses resolved"
      }
      
      $serviceResult.DNSResolution = @{
        IPv4ResolveTime = $ipv4ResolveTime
        IPv6ResolveTime = $ipv6ResolveTime
        IPv4Count = if ($ipv4Addresses) { $ipv4Addresses.Count } else { 0 }
        IPv6Count = if ($ipv6Addresses) { $ipv6Addresses.Count } else { 0 }
      }
      
    } catch {
      & $WriteLog "    DNS resolution error: $($_.Exception.Message)"
      $serviceResult.Error = "DNS resolution failed: $($_.Exception.Message)"
    }
    
    # Step 2: TCP Connection Test
    if (-not $serviceResult.Error) {
      try {
        & $WriteLog "  Step 2: TCP connection test to $($service.Domain):$($service.Port)..."
        
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = 5000
        $tcpClient.SendTimeout = 5000
        
        $tcpClient.Connect($service.Domain, $service.Port)
        $sw.Stop()
        
        if ($tcpClient.Connected) {
          $connectionTime = $sw.ElapsedMilliseconds
          $remoteEndPoint = $tcpClient.Client.RemoteEndPoint
          
          & $WriteLog "    TCP connection: SUCCESS (${connectionTime}ms) to $remoteEndPoint"
          
          $serviceResult.TCPConnection = @{
            Success = $true
            ConnectionTime = $connectionTime
            RemoteEndpoint = $remoteEndPoint
            Error = $null
          }
          
          $tcpClient.Close()
        } else {
          & $WriteLog "    TCP connection: FAILED - Not connected"
          $serviceResult.TCPConnection = @{
            Success = $false
            ConnectionTime = $sw.ElapsedMilliseconds
            RemoteEndpoint = $null
            Error = "Connection not established"
          }
        }
        
      } catch {
        $sw.Stop()
        $connectionTime = $sw.ElapsedMilliseconds
        & $WriteLog "    TCP connection: FAILED (${connectionTime}ms) - $($_.Exception.Message)"
        
        $serviceResult.TCPConnection = @{
          Success = $false
          ConnectionTime = $connectionTime
          RemoteEndpoint = $null
          Error = $_.Exception.Message
        }
      }
    }
    
    # Step 3: Analysis and diagnosis
    $overallSuccess = $false
    $diagnosis = ""
    
    if ($serviceResult.Error) {
      $overallSuccess = $false
      $diagnosis = "DNS resolution failed"
    } elseif ($serviceResult.TCPConnection -and $serviceResult.TCPConnection.Success) {
      $overallSuccess = $true
      $diagnosis = "Complete connection flow successful"
    } elseif ($serviceResult.DNSResolution -and $serviceResult.DNSResolution.IPv4Count -gt 0) {
      $overallSuccess = $false
      $diagnosis = "DNS works but TCP connection failed"
    } else {
      $overallSuccess = $false
      $diagnosis = "Both DNS and TCP failed"
    }
    
    $serviceResult.OverallSuccess = $overallSuccess
    $serviceResult.Diagnosis = $diagnosis
    
    $results += $serviceResult
    
    & $WriteLog "  Summary: $diagnosis"
    
    Start-Sleep -Seconds 1
  }
  
  # Overall analysis
  $successfulServices = $results | Where-Object { $_.OverallSuccess }
  $dnsIssues = $results | Where-Object { $_.Error -and $_.Error -match "DNS" }
  $tcpIssues = $results | Where-Object { $_.TCPConnection -and -not $_.TCPConnection.Success }
  
  $avgConnectionTime = if ($successfulServices -and $successfulServices.Count -gt 0) {
    [Math]::Round(($successfulServices | ForEach-Object { $_.TCPConnection.ConnectionTime } | Measure-Object -Average).Average, 1)
  } else { 0 }
  
  & $WriteLog "Streaming Service Analysis:"
  & $WriteLog "  Successful services: $($successfulServices.Count)/$($streamingServices.Count)"
  & $WriteLog "  DNS issues: $($dnsIssues.Count)/$($streamingServices.Count)"
  & $WriteLog "  TCP issues: $($tcpIssues.Count)/$($streamingServices.Count)"
  & $WriteLog "  Average connection time: ${avgConnectionTime}ms"
  
  # Service-specific analysis
  foreach ($result in $results) {
    $status = if ($result.OverallSuccess) { "✓ SUCCESS" } else { "✗ FAILED" }
    & $WriteLog "  $($result.Service): $status - $($result.Diagnosis)"
    
    if ($result.TCPConnection -and $result.TCPConnection.Error) {
      & $WriteLog "    TCP Error: $($result.TCPConnection.Error)"
    }
  }
  
  # Diagnosis and recommendations
  if ($successfulServices.Count -eq 0) {
    & $WriteLog "  DIAGNOSIS: All streaming services have connection issues"
    & $WriteLog "  IMPACT: No streaming services will work"
    & $WriteLog "  RECOMMENDATION: Check internet connectivity and DNS configuration"
  } elseif ($dnsIssues.Count -gt 0) {
    & $WriteLog "  DIAGNOSIS: DNS resolution issues affecting some services"
    & $WriteLog "  IMPACT: Affected services will show 'can't connect' errors"
    & $WriteLog "  RECOMMENDATION: Check DNS settings or try different DNS servers"
  } elseif ($tcpIssues.Count -gt 0) {
    & $WriteLog "  DIAGNOSIS: TCP connection issues affecting some services"
    & $WriteLog "  IMPACT: Affected services will timeout or fail to load"
    & $WriteLog "  RECOMMENDATION: Check firewall settings or network path to affected services"
  } elseif ($avgConnectionTime -gt 3000) {
    & $WriteLog "  DIAGNOSIS: Slow connection establishment to streaming services"
    & $WriteLog "  IMPACT: Apps may timeout during loading but work once connected"
    & $WriteLog "  RECOMMENDATION: Check network path or increase app timeout settings"
  } else {
    & $WriteLog "  DIAGNOSIS: Streaming service connectivity is working correctly"
    & $WriteLog "  IMPACT: Streaming services should work normally"
    & $WriteLog "  RECOMMENDATION: Service connectivity is not the cause of streaming issues"
  }
  
  return @{
    SuccessfulServices = $successfulServices.Count
    TotalServices = $streamingServices.Count
    DNSIssues = $dnsIssues.Count
    TCPIssues = $tcpIssues.Count
    AverageConnectionTime = $avgConnectionTime
    ServiceResults = $results
    Diagnosis = if ($successfulServices.Count -eq 0) { "ALL_SERVICES_FAILED" } elseif ($dnsIssues.Count -gt 0) { "DNS_ISSUES" } elseif ($tcpIssues.Count -gt 0) { "TCP_ISSUES" } elseif ($avgConnectionTime -gt 3000) { "SLOW_CONNECTIONS" } else { "SERVICES_WORKING" }
  }
}

function Test-IPv6Interference {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing IPv6 interference on PPPoE interface..."
  & $WriteLog "This test checks if IPv6 is enabled but non-functional on the PPPoE interface"
  
  $results = @{
    SystemIPv6Enabled = $false
    InterfaceIPv6Enabled = $false
    IPv6AddressesPresent = $false
    IPv6Connectivity = $false
    LinkLocalAddresses = @()
    GlobalAddresses = @()
    Issues = @()
    Diagnosis = ""
  }
  
  # Check system-wide IPv6 status
  try {
    & $WriteLog "Checking system-wide IPv6 configuration..."
    
    $ipv6Enabled = Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    if ($ipv6Enabled) {
      $enabledAdapters = $ipv6Enabled | Where-Object { $_.Enabled -eq $true }
      $results.SystemIPv6Enabled = $enabledAdapters.Count -gt 0
      
      if ($results.SystemIPv6Enabled) {
        & $WriteLog "  System IPv6: ENABLED on $($enabledAdapters.Count) adapter(s)"
      } else {
        & $WriteLog "  System IPv6: DISABLED on all adapters"
      }
    } else {
      & $WriteLog "  System IPv6: Cannot determine status"
    }
  } catch {
    & $WriteLog "  System IPv6 check failed: $($_.Exception.Message)"
    $results.Issues += "Could not check system IPv6 status"
  }
  
  # Check PPPoE interface specifically
  try {
    & $WriteLog "Checking PPPoE interface IPv6 configuration..."
    
    $pppInterfaces = Get-NetAdapter -Name "*PPP*" -ErrorAction SilentlyContinue
    if ($pppInterfaces) {
      foreach ($interface in $pppInterfaces) {
        & $WriteLog "  Checking interface: $($interface.Name)"
        
        # Check if IPv6 is enabled on this interface
        $ipv6Binding = Get-NetAdapterBinding -Name $interface.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        if ($ipv6Binding) {
          $results.InterfaceIPv6Enabled = $ipv6Binding.Enabled
          & $WriteLog "    IPv6 binding: $(if ($ipv6Binding.Enabled) { 'ENABLED' } else { 'DISABLED' })"
        }
        
        # Check IPv6 addresses on this interface
        $ipv6Addresses = Get-NetIPAddress -InterfaceAlias $interface.Name -AddressFamily IPv6 -ErrorAction SilentlyContinue
        if ($ipv6Addresses -and $ipv6Addresses.Count -gt 0) {
          $results.IPv6AddressesPresent = $true
          
          foreach ($addr in $ipv6Addresses) {
            if ($addr.IPAddress -match '^fe80::') {
              $results.LinkLocalAddresses += $addr.IPAddress
              & $WriteLog "    Link-local address: $($addr.IPAddress)"
            } else {
              $results.GlobalAddresses += $addr.IPAddress
              & $WriteLog "    Global address: $($addr.IPAddress)"
            }
          }
        } else {
          & $WriteLog "    IPv6 addresses: NONE"
        }
      }
    } else {
      & $WriteLog "  No PPP interfaces found"
    }
  } catch {
    & $WriteLog "  PPP interface IPv6 check failed: $($_.Exception.Message)"
    $results.Issues += "Could not check PPP interface IPv6 configuration"
  }
  
  # Test IPv6 connectivity
  try {
    & $WriteLog "Testing IPv6 connectivity..."
    
    # Test with common IPv6 hosts
    $ipv6Hosts = @(
      @{ Name = "Google IPv6"; Address = "2001:4860:4860::8888" },
      @{ Name = "Cloudflare IPv6"; Address = "2606:4700:4700::1111" }
    )
    
    $ipv6ConnectivitySuccess = 0
    
    foreach ($ipv6Host in $ipv6Hosts) {
      try {
        $ping = Test-Connection -TargetName $ipv6Host.Address -Count 1 -TimeoutSeconds 3 -ErrorAction Stop
        if ($ping -and $ping.ResponseTime) {
          $ipv6ConnectivitySuccess++
          & $WriteLog "  $($ipv6Host.Name): SUCCESS (${ping.ResponseTime}ms)"
        } else {
          & $WriteLog "  $($ipv6Host.Name): FAILED - No response"
        }
      } catch {
        & $WriteLog "  $($ipv6Host.Name): FAILED - $($_.Exception.Message)"
      }
    }
    
    $results.IPv6Connectivity = $ipv6ConnectivitySuccess -gt 0
    
  } catch {
    & $WriteLog "  IPv6 connectivity test failed: $($_.Exception.Message)"
    $results.Issues += "Could not test IPv6 connectivity"
  }
  
  # Analyze for interference patterns
  $interferenceDetected = $false
  $interferenceIssues = @()
  
  if ($results.SystemIPv6Enabled -and $results.InterfaceIPv6Enabled -and -not $results.IPv6Connectivity) {
    $interferenceDetected = $true
    $interferenceIssues += "IPv6 enabled but no connectivity - apps may attempt IPv6 and timeout"
  }
  
  if ($results.LinkLocalAddresses.Count -gt 0 -and $results.GlobalAddresses.Count -eq 0 -and $results.SystemIPv6Enabled) {
    $interferenceDetected = $true
    $interferenceIssues += "Only link-local IPv6 addresses - incomplete IPv6 configuration"
  }
  
  if ($results.IPv6AddressesPresent -and -not $results.IPv6Connectivity) {
    $interferenceDetected = $true
    $interferenceIssues += "IPv6 addresses configured but no IPv6 connectivity"
  }
  
  # Determine diagnosis
  if ($interferenceDetected) {
    $results.Diagnosis = "IPv6 interference detected"
    & $WriteLog "IPv6 Interference Analysis:"
    & $WriteLog "  Status: INTERFERENCE DETECTED"
    & $WriteLog "  Issues:"
    foreach ($issue in $interferenceIssues) {
      & $WriteLog "    - $issue"
    }
    & $WriteLog "  DIAGNOSIS: IPv6 is configured but not working properly"
    & $WriteLog "  IMPACT: Applications may attempt IPv6 connections that timeout, causing delays"
    & $WriteLog "  RECOMMENDATION: Disable IPv6 on PPPoE interface or fix IPv6 configuration"
  } elseif ($results.SystemIPv6Enabled -and $results.IPv6Connectivity) {
    $results.Diagnosis = "IPv6 working correctly"
    & $WriteLog "IPv6 Interference Analysis:"
    & $WriteLog "  Status: NO INTERFERENCE - IPv6 working correctly"
    & $WriteLog "  DIAGNOSIS: IPv6 is properly configured and functional"
    & $WriteLog "  IMPACT: IPv6 should not cause connection issues"
    & $WriteLog "  RECOMMENDATION: IPv6 is not the cause of streaming problems"
  } elseif (-not $results.SystemIPv6Enabled) {
    $results.Diagnosis = "IPv6 disabled - no interference"
    & $WriteLog "IPv6 Interference Analysis:"
    & $WriteLog "  Status: NO INTERFERENCE - IPv6 is disabled"
    & $WriteLog "  DIAGNOSIS: IPv6 is disabled, so no interference possible"
    & $WriteLog "  IMPACT: Applications will only use IPv4"
    & $WriteLog "  RECOMMENDATION: IPv6 is not causing any issues"
  } else {
    $results.Diagnosis = "IPv6 status unclear"
    & $WriteLog "IPv6 Interference Analysis:"
    & $WriteLog "  Status: UNCLEAR - Could not fully determine IPv6 status"
    & $WriteLog "  DIAGNOSIS: IPv6 status could not be fully determined"
    & $WriteLog "  IMPACT: Unknown impact on application behavior"
    & $WriteLog "  RECOMMENDATION: Manually check IPv6 configuration if issues persist"
  }
  
  return $results
}

function Test-DefaultRouteVerification {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing default route verification for PPPoE interface..."
  & $WriteLog "This test checks complete routing table including 0.0.0.0/0 routes"
  
  $results = @{
    DefaultRoutes = @()
    PPPoERoutes = @()
    RouteConflicts = @()
    Issues = @()
    Diagnosis = ""
  }
  
  try {
    # Get all routes
    & $WriteLog "Retrieving routing table..."
    $allRoutes = Get-NetRoute -ErrorAction SilentlyContinue
    
    # Find default routes (0.0.0.0/0)
    $defaultRoutes = $allRoutes | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" }
    $results.DefaultRoutes = $defaultRoutes
    
    & $WriteLog "Found $($defaultRoutes.Count) default route(s):"
    foreach ($route in $defaultRoutes) {
      $interfaceName = $route.InterfaceAlias
      $nextHop = $route.NextHop
      $metric = $route.RouteMetric
      $adminDistance = $route.AdminDistance
      
      & $WriteLog "  Interface: $interfaceName, Gateway: $nextHop, Metric: $metric, Distance: $adminDistance"
      
      $results.DefaultRoutes += @{
        Interface = $interfaceName
        Gateway = $nextHop
        Metric = $metric
        AdminDistance = $adminDistance
        IsPPPoE = $interfaceName -match "PPP"
      }
    }
    
    # Find PPP-specific routes
    $pppRoutes = $allRoutes | Where-Object { $_.InterfaceAlias -match "PPP" }
    $results.PPPoERoutes = $pppRoutes
    
    if ($pppRoutes.Count -gt 0) {
      & $WriteLog "Found $($pppRoutes.Count) PPP interface route(s):"
      foreach ($route in $pppRoutes | Select-Object -First 10) {  # Limit output
        & $WriteLog "  $($route.DestinationPrefix) -> $($route.NextHop) via $($route.InterfaceAlias)"
      }
      if ($pppRoutes.Count -gt 10) {
        & $WriteLog "  ... and $($pppRoutes.Count - 10) more PPP routes"
      }
    }
    
    # Analyze routing configuration
    $pppDefaultRoutes = $results.DefaultRoutes | Where-Object { $_.IsPPPoE }
    $nonPppDefaultRoutes = $results.DefaultRoutes | Where-Object { -not $_.IsPPPoE }
    
    # Check for route conflicts
    if ($results.DefaultRoutes.Count -gt 1) {
      & $WriteLog "Multiple default routes detected - checking for conflicts..."
      
      # Find routes with same metric
      $routeGroups = $results.DefaultRoutes | Group-Object Metric
      foreach ($group in $routeGroups) {
        if ($group.Count -gt 1) {
          $conflict = @{
            Type = "Same metric"
            Metric = $group.Name
            Routes = $group.Group
          }
          $results.RouteConflicts += $conflict
          & $WriteLog "  Conflict: Multiple routes with metric $($group.Name)"
        }
      }
      
      # Check for PPP vs non-PPP conflicts
      if ($pppDefaultRoutes.Count -gt 0 -and $nonPppDefaultRoutes.Count -gt 0) {
        $conflict = @{
          Type = "PPPoE vs non-PPPoE"
          PPPRoutes = $pppDefaultRoutes.Count
          NonPPPRoutes = $nonPppDefaultRoutes.Count
        }
        $results.RouteConflicts += $conflict
        & $WriteLog "  Conflict: Both PPP and non-PPP default routes exist"
      }
    }
    
    # Test routing to different destinations
    & $WriteLog "Testing routing to various destinations..."
    
    $testDestinations = @(
      @{ Name = "Google DNS"; IP = "8.8.8.8" },
      @{ Name = "Cloudflare DNS"; IP = "1.1.1.1" },
      @{ Name = "Netflix"; IP = "netflix.com" }
    )
    
    $routingResults = @()
    
    foreach ($dest in $testDestinations) {
      try {
        $route = Get-NetRoute -DestinationPrefix "$($dest.IP)/32" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($route) {
          $routingResults += @{
            Destination = $dest.Name
            IP = $dest.IP
            RouteInterface = $route.InterfaceAlias
            RouteGateway = $route.NextHop
            IsPPPRoute = $route.InterfaceAlias -match "PPP"
          }
          & $WriteLog "  $($dest.Name) ($($dest.IP)): Route via $($route.InterfaceAlias) -> $($route.NextHop)"
        } else {
          $routingResults += @{
            Destination = $dest.Name
            IP = $dest.IP
            RouteInterface = $null
            RouteGateway = $null
            IsPPPRoute = $false
          }
          & $WriteLog "  $($dest.Name) ($($dest.IP)): No specific route found"
        }
      } catch {
        & $WriteLog "  $($dest.Name) ($($dest.IP)): Route lookup failed - $($_.Exception.Message)"
      }
    }
    
    # Analyze routing health
    $pppRoutesWorking = $routingResults | Where-Object { $_.IsPPPRoute -and $_.RouteInterface }
    $routingIssues = @()
    
    if ($pppDefaultRoutes.Count -eq 0) {
      $routingIssues += "No default route via PPP interface"
    }
    
    if ($results.RouteConflicts.Count -gt 0) {
      $routingIssues += "$($results.RouteConflicts.Count) routing conflict(s) detected"
    }
    
    if ($pppRoutesWorking.Count -eq 0 -and $pppDefaultRoutes.Count -gt 0) {
      $routingIssues += "PPPoE default route exists but not being used for destinations"
    }
    
    $results.Issues = $routingIssues
    
    # Determine diagnosis
    if ($routingIssues.Count -eq 0) {
      $results.Diagnosis = "Routing configuration is correct"
      & $WriteLog "Default Route Analysis:"
      & $WriteLog "  Status: ROUTING OK"
      & $WriteLog "  DIAGNOSIS: Default routing is properly configured"
      & $WriteLog "  IMPACT: Traffic should route correctly through PPPoE interface"
      & $WriteLog "  RECOMMENDATION: Routing is not the cause of connectivity issues"
    } elseif ($pppDefaultRoutes.Count -eq 0) {
      $results.Diagnosis = "Missing PPPoE default route"
      & $WriteLog "Default Route Analysis:"
      & $WriteLog "  Status: MISSING DEFAULT ROUTE"
      & $WriteLog "  DIAGNOSIS: No default route via PPPoE interface"
      & $WriteLog "  IMPACT: Internet traffic will not route through PPPoE connection"
      & $WriteLog "  RECOMMENDATION: Check PPPoE connection and routing configuration"
    } elseif ($results.RouteConflicts.Count -gt 0) {
      $results.Diagnosis = "Routing conflicts detected"
      & $WriteLog "Default Route Analysis:"
      & $WriteLog "  Status: ROUTING CONFLICTS"
      & $WriteLog "  DIAGNOSIS: Multiple default routes causing routing conflicts"
      & $WriteLog "  IMPACT: Traffic may route through wrong interface"
      & $WriteLog "  RECOMMENDATION: Resolve routing conflicts or disable competing interfaces"
    } else {
      $results.Diagnosis = "Routing issues detected"
      & $WriteLog "Default Route Analysis:"
      & $WriteLog "  Status: ROUTING ISSUES"
      & $WriteLog "  DIAGNOSIS: Various routing configuration issues detected"
      & $WriteLog "  IMPACT: Traffic routing may be unreliable"
      & $WriteLog "  RECOMMENDATION: Review and fix routing configuration"
    }
    
  } catch {
    & $WriteLog "Default route verification failed: $($_.Exception.Message)"
    $results.Issues += "Could not verify routing configuration"
    $results.Diagnosis = "Routing verification failed"
  }
  
  return $results
}

Export-ModuleMember -Function *
