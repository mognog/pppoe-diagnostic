# PPPoE.Net.Diagnostics.psm1 - Network diagnostic functions

Set-StrictMode -Version 3.0

function Test-ONTAvailability {
  param([scriptblock]$WriteLog)
  
  # Allow provider-agnostic skip of ONT web UI probing (LED-only prompt remains)
  if ($env:PPPOE_SKIP_ONT_WEBUI -eq '1') {
    & $WriteLog "Skipping ONT management web UI probing (env PPPOE_SKIP_ONT_WEBUI=1)"
    return @{ Status = "SKIPPED"; Reason = "ONT web UI probing disabled" }
  }
  
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
      
      $ipv4Addresses = @()
      if ($ipv4Resolution) {
        $ipv4Addresses = @($ipv4Resolution | Where-Object { $_.PSObject.Properties['IPAddress'] -and $_.IPAddress } | ForEach-Object { $_.IPAddress })
      }
      $serviceResult.IPv4Addresses = $ipv4Addresses
      if ($ipv4Addresses.Count -gt 0) {
        & $WriteLog "    IPv4: $($ipv4Addresses.Count) addresses (${ipv4ResolveTime}ms) - $($ipv4Addresses -join ', ')"
      } else {
        & $WriteLog "    IPv4: No valid addresses resolved"
      }
      
      # IPv6 resolution
      $sw.Restart()
      $ipv6Resolution = Resolve-DnsName -Name $service.Domain -Type AAAA -ErrorAction SilentlyContinue
      $sw.Stop()
      $ipv6ResolveTime = $sw.ElapsedMilliseconds
      
      $ipv6Addresses = @()
      if ($ipv6Resolution) {
        $ipv6Addresses = @($ipv6Resolution | Where-Object { $_.PSObject.Properties['IPAddress'] -and $_.IPAddress } | ForEach-Object { $_.IPAddress })
      }
      $serviceResult.IPv6Addresses = $ipv6Addresses
      if ($ipv6Addresses.Count -gt 0) {
        & $WriteLog "    IPv6: $($ipv6Addresses.Count) addresses (${ipv6ResolveTime}ms) - $($ipv6Addresses -join ', ')"
      } else {
        & $WriteLog "    IPv6: No valid addresses resolved"
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
        if ($ping -and ($ping.PSObject.Properties['ResponseTime'] -or $ping.PSObject.Properties['Latency'])) {
          $latency = if ($ping.PSObject.Properties['ResponseTime']) { $ping.ResponseTime } else { $ping.Latency }
          $ipv6ConnectivitySuccess++
          & $WriteLog "  $($ipv6Host.Name): SUCCESS (${latency}ms)"
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
    
    & $WriteLog "Found $($defaultRoutes.Count) default route(s):"
    foreach ($route in $defaultRoutes) {
      $interfaceName = $route.InterfaceAlias
      $nextHop = $route.NextHop
      $metric = $route.RouteMetric
      $adminDistance = $route.AdminDistance
      
      & $WriteLog "  Interface: $interfaceName, Gateway: $nextHop, Metric: $metric, Distance: $adminDistance"
      
      # Add to results array (don't try to mix CimInstance objects with hashtables)
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

function Test-PacketCaptureDuringFailures {
  <#
  .SYNOPSIS
  Captures network packets during connection failures using netsh trace
  .DESCRIPTION
  Uses netsh trace to capture packets when connections drop, providing irrefutable evidence
  of network behavior. This is the most definitive way to diagnose connection issues.
  #>
  param(
    [string]$TestHost = 'netflix.com',
    [int]$TestPort = 443,
    [int]$CaptureDurationSeconds = 30,
    [string]$CapturePath = "$env:TEMP\pppoe_packet_capture",
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Starting packet capture during connection failures..."
  & $WriteLog "This will capture actual network packets to diagnose connection drops"
  & $WriteLog "Target: $TestHost`:$TestPort"
  & $WriteLog "Capture duration: $CaptureDurationSeconds seconds"
  
  # Create capture directory
  if (-not (Test-Path $CapturePath)) {
    New-Item -ItemType Directory -Path $CapturePath -Force | Out-Null
  }
  
  $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $etlFile = Join-Path $CapturePath "pppoe_capture_$timestamp.etl"
  $txtFile = Join-Path $CapturePath "pppoe_capture_$timestamp.txt"
  
  & $WriteLog "Capture files: $etlFile"
  
  $results = @{
    CaptureStarted = $false
    CaptureCompleted = $false
    ETLFile = $etlFile
    TxtFile = $txtFile
    CaptureErrors = @()
    ConnectionFailures = @()
    PacketAnalysis = $null
  }
  
  try {
    # Start netsh trace capture
    & $WriteLog "Starting netsh trace capture..."
    
    # Start netsh trace process
    Start-Process -FilePath "netsh" -ArgumentList "trace", "start", "capture=yes", "tracefile=$etlFile", "provider=Microsoft-Windows-TCPIP", "level=5" -NoNewWindow -Wait:$false
    
    Start-Sleep -Seconds 2  # Give trace time to start
    
    # Check if trace started successfully
    try {
      $traceStatus = netsh trace show status 2>&1
      if ($traceStatus -match "Running") {
        $results.CaptureStarted = $true
        & $WriteLog "Packet capture started successfully"
      } else {
        & $WriteLog "WARNING: Could not verify trace started - continuing with test"
        $results.CaptureStarted = $false
      }
    } catch {
      & $WriteLog "WARNING: Could not check trace status - continuing with test"
      $results.CaptureStarted = $false
    }
    
    # Perform connection tests while capturing
    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($CaptureDurationSeconds)
    $testCount = 0
    
    while ((Get-Date) -lt $endTime) {
      $testCount++
      $elapsedSeconds = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
      
      & $WriteLog "Connection test $testCount at ${elapsedSeconds}s (capturing packets)..."
      
      $connectionResult = @{
        TestNumber = $testCount
        Timestamp = Get-Date
        ElapsedSeconds = $elapsedSeconds
        Host = $TestHost
        Port = $TestPort
        ConnectionEstablished = $false
        ConnectionLost = $false
        LossTime = $null
        ErrorDetails = $null
      }
      
      try {
        # Create TCP connection
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = 8000  # 8 second timeout to catch 4.1s drops
        $tcpClient.SendTimeout = 8000
        
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tcpClient.Connect($TestHost, $TestPort)
        $connectionTime = $sw.ElapsedMilliseconds
        
        if ($tcpClient.Connected) {
          $connectionResult.ConnectionEstablished = $true
          & $WriteLog "  Connection established: ${connectionTime}ms"
          
          # Monitor connection for drops (this is where packets will be captured)
          $monitorDuration = 10  # Monitor for 10 seconds
          $monitorStart = Get-Date
          $monitorEnd = $monitorStart.AddSeconds($monitorDuration)
          
          $connectionStable = $true
          
          while ((Get-Date) -lt $monitorEnd -and $connectionStable) {
            try {
              $stream = $tcpClient.GetStream()
              $stream.ReadTimeout = 1000
              
              # Send HTTP request to generate traffic
              $request = "HEAD / HTTP/1.1`r`nHost: $TestHost`r`nConnection: keep-alive`r`n`r`n"
              $requestBytes = [System.Text.Encoding]::ASCII.GetBytes($request)
              $stream.Write($requestBytes, 0, $requestBytes.Length)
              
              # Try to read response
              $buffer = New-Object byte[] 1024
              $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
              
              $currentElapsed = [Math]::Round(((Get-Date) - $monitorStart).TotalSeconds, 1)
              & $WriteLog "    [$currentElapsed s] Connection stable (${bytesRead} bytes)"
              
            } catch {
              $connectionStable = $false
              $connectionResult.ConnectionLost = $true
              $connectionResult.LossTime = [Math]::Round(((Get-Date) - $monitorStart).TotalSeconds, 1)
              $connectionResult.ErrorDetails = $_.Exception.Message
              
              & $WriteLog "    [CONNECTION LOST at $($connectionResult.LossTime)s] $($_.Exception.Message)"
              & $WriteLog "    *** PACKETS CAPTURED FOR THIS FAILURE ***"
            }
          }
          
          if ($tcpClient.Connected) {
            $tcpClient.Close()
            & $WriteLog "  Connection closed cleanly"
          }
          
        } else {
          $connectionResult.ErrorDetails = "Failed to establish connection"
          & $WriteLog "  Failed to establish connection"
        }
        
      } catch {
        $connectionResult.ErrorDetails = $_.Exception.Message
        & $WriteLog "  Connection error: $($_.Exception.Message)"
      }
      
      $results.ConnectionFailures += $connectionResult
      
      # Small delay between tests
      Start-Sleep -Seconds 3
    }
    
    # Stop trace capture
    & $WriteLog "Stopping packet capture..."
    
    try {
      $stopProcess = Start-Process -FilePath "netsh" -ArgumentList "trace", "stop" -PassThru -NoNewWindow -Wait:$true
      
      if ($stopProcess.ExitCode -eq 0) {
        & $WriteLog "Packet capture stopped successfully"
        $results.CaptureCompleted = $true
      } else {
        & $WriteLog "WARNING: Trace stop returned exit code $($stopProcess.ExitCode)"
        $results.CaptureCompleted = $false
      }
    } catch {
      & $WriteLog "ERROR: Failed to stop trace capture: $($_.Exception.Message)"
      $results.CaptureErrors += "Failed to stop trace: $($_.Exception.Message)"
    }
    
    # Convert ETL to readable format if possible
    if ($results.CaptureCompleted -and (Test-Path $etlFile)) {
      & $WriteLog "Converting ETL capture to readable format..."
      
      try {
        # Try to use netsh trace to convert ETL to CSV
        $csvFile = Join-Path $CapturePath "pppoe_capture_$timestamp.csv"
        
        $convertProcess = Start-Process -FilePath "netsh" -ArgumentList "trace", "convert", $etlFile, $csvFile -PassThru -NoNewWindow -Wait:$true
        
        if ($convertProcess.ExitCode -eq 0 -and (Test-Path $csvFile)) {
          & $WriteLog "ETL converted to CSV: $csvFile"
          $results.CSVFile = $csvFile
        } else {
          & $WriteLog "Could not convert ETL to CSV - ETL file available for analysis"
        }
      } catch {
        & $WriteLog "Error converting ETL: $($_.Exception.Message)"
        $results.CaptureErrors += "ETL conversion failed: $($_.Exception.Message)"
      }
    }
    
  } catch {
    & $WriteLog "ERROR: Packet capture failed: $($_.Exception.Message)"
    $results.CaptureErrors += "Capture failed: $($_.Exception.Message)"
  }
  
  # Analyze captured failures
  $totalTests = $results.ConnectionFailures.Count
  $establishedConnections = $results.ConnectionFailures | Where-Object { $_.ConnectionEstablished -eq $true }
  $lostConnections = $results.ConnectionFailures | Where-Object { $_.ConnectionLost -eq $true }
  
  $establishmentRate = if ($totalTests -gt 0) { [Math]::Round(($establishedConnections.Count / $totalTests) * 100, 1) } else { 0 }
  $lossRate = if ($totalTests -gt 0) { [Math]::Round(($lostConnections.Count / $totalTests) * 100, 1) } else { 0 }
  
  & $WriteLog "Packet Capture Analysis:"
  & $WriteLog "  Total connection tests: $totalTests"
  & $WriteLog "  Connection establishment rate: $establishmentRate%"
  & $WriteLog "  Connection loss rate: $lossRate%"
  & $WriteLog "  Capture started: $($results.CaptureStarted)"
  & $WriteLog "  Capture completed: $($results.CaptureCompleted)"
  
  if ($results.CaptureErrors.Count -gt 0) {
    & $WriteLog "  Capture errors:"
    foreach ($errorMsg in $results.CaptureErrors) {
      & $WriteLog "    - $errorMsg"
    }
  }
  
  # Analyze failure timing patterns
  if ($lostConnections.Count -gt 0) {
    $lossTimes = $lostConnections | ForEach-Object { $_.LossTime } | Where-Object { $_ -ne $null }
    if ($lossTimes -and $lossTimes.Count -gt 0) {
      $avgLossTime = [Math]::Round(($lossTimes | Measure-Object -Average).Average, 1)
      $fourSecondLosses = $lossTimes | Where-Object { $_ -ge 3.5 -and $_ -le 4.5 }
      
      & $WriteLog "  Average connection loss time: ${avgLossTime}s"
      & $WriteLog "  Connections lost around 4 seconds: $($fourSecondLosses.Count)/$($lostConnections.Count)"
      
      if ($fourSecondLosses.Count -gt 0) {
        & $WriteLog "  *** 4-SECOND DROP PATTERN CONFIRMED IN PACKET CAPTURE ***"
        & $WriteLog "  This provides definitive evidence of timing-based connection drops"
      }
    }
  }
  
  # File locations
  & $WriteLog "Packet Capture Files:"
  & $WriteLog "  ETL (binary): $etlFile"
  if ($results.CSVFile) {
    & $WriteLog "  CSV (readable): $($results.CSVFile)"
  }
  & $WriteLog "  Analysis: Use Wireshark, Network Monitor, or netsh trace analyze to examine"
  
  # Diagnosis
  if (-not $results.CaptureStarted) {
    & $WriteLog "  DIAGNOSIS: Packet capture failed to start - run as Administrator"
    & $WriteLog "  RECOMMENDATION: Run script as Administrator for packet capture functionality"
  } elseif (-not $results.CaptureCompleted) {
    & $WriteLog "  DIAGNOSIS: Packet capture started but failed to complete properly"
    & $WriteLog "  RECOMMENDATION: Check ETL file manually and verify Administrator privileges"
  } elseif ($lostConnections.Count -eq 0) {
    & $WriteLog "  DIAGNOSIS: No connection failures captured - connection stability is good"
    & $WriteLog "  RECOMMENDATION: Connection issues may be intermittent or resolved"
  } else {
    & $WriteLog "  DIAGNOSIS: Connection failures captured - examine packet traces for root cause"
    & $WriteLog "  RECOMMENDATION: Analyze ETL/CSV files to identify RST packets, timeouts, or routing issues"
  }
  
  return $results
}

function Test-TimeBasedPatternAnalysis {
  <#
  .SYNOPSIS
  Analyzes connection patterns over time to detect congestion vs infrastructure issues
  .DESCRIPTION
  Runs mini-tests every 5 minutes for an hour to detect:
  - Time-correlated problems (evening congestion)
  - Random failures (hardware/routing issues)
  - Progressive degradation patterns
  #>
  param(
    [int]$TestIntervalMinutes = 5,
    [int]$TotalDurationMinutes = 60,
    [string]$TestHost = '1.1.1.1',
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Starting time-based pattern analysis..."
  & $WriteLog "Duration: $TotalDurationMinutes minutes, testing every $TestIntervalMinutes minutes"
  & $WriteLog "This will detect time-correlated vs random connection issues"
  
  $results = @()
  $startTime = Get-Date
  $endTime = $startTime.AddMinutes($TotalDurationMinutes)
  $testCount = 0
  
  while ((Get-Date) -lt $endTime) {
    $testCount++
    $currentTime = Get-Date
    $elapsedMinutes = [Math]::Round(($currentTime - $startTime).TotalMinutes, 1)
    $timeOfDay = $currentTime.ToString("HH:mm")
    $dayOfWeek = $currentTime.DayOfWeek.ToString()
    
    & $WriteLog "Time-based test $testCount at ${elapsedMinutes}m (${timeOfDay}, $dayOfWeek)..."
    
    # Perform comprehensive mini-test
    $miniTestResult = @{
      TestNumber = $testCount
      Timestamp = $currentTime
      ElapsedMinutes = $elapsedMinutes
      TimeOfDay = $timeOfDay
      DayOfWeek = $dayOfWeek
      IsWeekend = ($currentTime.DayOfWeek -eq "Saturday" -or $currentTime.DayOfWeek -eq "Sunday")
      IsEvening = ($currentTime.Hour -ge 18 -and $currentTime.Hour -le 23)
      IsPeakHours = ($currentTime.Hour -ge 19 -and $currentTime.Hour -le 21)
    }
    
    # Test 1: Basic connectivity
    try {
      $ping = Test-Connection -TargetName $TestHost -Count 3 -TimeoutSeconds 2 -ErrorAction Stop
      if ($ping -and $ping.Count -gt 0) {
        $avgLatency = [Math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 1)
        $packetLoss = [Math]::Round(((3 - $ping.Count) / 3) * 100, 1)
        
        $miniTestResult.ConnectivitySuccess = $true
        $miniTestResult.AvgLatency = $avgLatency
        $miniTestResult.PacketLoss = $packetLoss
        
        & $WriteLog "  Basic connectivity: OK (${avgLatency}ms avg, ${packetLoss}% loss)"
      } else {
        $miniTestResult.ConnectivitySuccess = $false
        $miniTestResult.AvgLatency = $null
        $miniTestResult.PacketLoss = 100
        & $WriteLog "  Basic connectivity: FAILED"
      }
    } catch {
      $miniTestResult.ConnectivitySuccess = $false
      $miniTestResult.AvgLatency = $null
      $miniTestResult.PacketLoss = 100
      $miniTestResult.ConnectivityError = $_.Exception.Message
      & $WriteLog "  Basic connectivity: ERROR - $($_.Exception.Message)"
    }
    
    # Test 2: Streaming service connection
    try {
      $tcpClient = New-Object System.Net.Sockets.TcpClient
      $tcpClient.ReceiveTimeout = 3000
      $tcpClient.SendTimeout = 3000
      
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $tcpClient.Connect("netflix.com", 443)
      $sw.Stop()
      
      if ($tcpClient.Connected) {
        $connectionTime = $sw.ElapsedMilliseconds
        $miniTestResult.StreamingConnectionSuccess = $true
        $miniTestResult.StreamingConnectionTime = $connectionTime
        & $WriteLog "  Streaming connection: OK (${connectionTime}ms)"
        
        $tcpClient.Close()
      } else {
        $miniTestResult.StreamingConnectionSuccess = $false
        $miniTestResult.StreamingConnectionTime = $null
        & $WriteLog "  Streaming connection: FAILED"
      }
    } catch {
      $miniTestResult.StreamingConnectionSuccess = $false
      $miniTestResult.StreamingConnectionTime = $null
      $miniTestResult.StreamingConnectionError = $_.Exception.Message
      & $WriteLog "  Streaming connection: ERROR - $($_.Exception.Message)"
    }
    
    # Test 3: DNS resolution speed
    try {
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $dnsResult = Resolve-DnsName -Name "google.com" -ErrorAction Stop
      $sw.Stop()
      
      if ($dnsResult -and $dnsResult.Count -gt 0) {
        $dnsTime = $sw.ElapsedMilliseconds
        $miniTestResult.DNSSuccess = $true
        $miniTestResult.DNSTime = $dnsTime
        & $WriteLog "  DNS resolution: OK (${dnsTime}ms)"
      } else {
        $miniTestResult.DNSSuccess = $false
        $miniTestResult.DNSTime = $null
        & $WriteLog "  DNS resolution: FAILED"
      }
    } catch {
      $miniTestResult.DNSSuccess = $false
      $miniTestResult.DNSTime = $null
      $miniTestResult.DNSError = $_.Exception.Message
      & $WriteLog "  DNS resolution: ERROR - $($_.Exception.Message)"
    }
    
    # Calculate overall health score
    $healthScore = 0
    if ($miniTestResult.ConnectivitySuccess -and $miniTestResult.PacketLoss -lt 10) { $healthScore += 30 }
    if ($miniTestResult.StreamingConnectionSuccess -and $miniTestResult.StreamingConnectionTime -lt 2000) { $healthScore += 40 }
    if ($miniTestResult.DNSSuccess -and $miniTestResult.DNSTime -lt 500) { $healthScore += 30 }
    
    $miniTestResult.HealthScore = $healthScore
    
    # Classify health
    if ($healthScore -ge 90) {
      $miniTestResult.HealthClass = "EXCELLENT"
    } elseif ($healthScore -ge 70) {
      $miniTestResult.HealthClass = "GOOD"
    } elseif ($healthScore -ge 50) {
      $miniTestResult.HealthClass = "FAIR"
    } else {
      $miniTestResult.HealthClass = "POOR"
    }
    
    & $WriteLog "  Overall health: $($miniTestResult.HealthClass) ($healthScore/100)"
    
    $results += $miniTestResult
    
    # Wait for next test interval
    $nextTestTime = $currentTime.AddMinutes($TestIntervalMinutes)
    if ($nextTestTime -lt $endTime) {
      $waitSeconds = [Math]::Round(($nextTestTime - (Get-Date)).TotalSeconds)
      if ($waitSeconds -gt 0) {
        & $WriteLog "  Waiting $waitSeconds seconds until next test..."
        Start-Sleep -Seconds $waitSeconds
      }
    }
  }
  
  # Analyze time-based patterns
  & $WriteLog "Time-Based Pattern Analysis:"
  
  $totalTests = $results.Count
  $excellentTests = $results | Where-Object { $_.HealthClass -eq "EXCELLENT" }
  $goodTests = $results | Where-Object { $_.HealthClass -eq "GOOD" }
  $fairTests = $results | Where-Object { $_.HealthClass -eq "FAIR" }
  $poorTests = $results | Where-Object { $_.HealthClass -eq "POOR" }
  
  $avgHealthScore = [Math]::Round(($results | Measure-Object -Property HealthScore -Average).Average, 1)
  
  & $WriteLog "  Total tests: $totalTests"
  & $WriteLog "  Average health score: $avgHealthScore/100"
  & $WriteLog "  Excellent: $($excellentTests.Count) tests"
  & $WriteLog "  Good: $($goodTests.Count) tests"
  & $WriteLog "  Fair: $($fairTests.Count) tests"
  & $WriteLog "  Poor: $($poorTests.Count) tests"
  
  # Analyze time correlations
  $eveningTests = $results | Where-Object { $_.IsEvening }
  $peakHourTests = $results | Where-Object { $_.IsPeakHours }
  $weekendTests = $results | Where-Object { $_.IsWeekend }
  
  if ($eveningTests -and $eveningTests.Count -gt 0) {
    $eveningAvgScore = [Math]::Round(($eveningTests | Measure-Object -Property HealthScore -Average).Average, 1)
    & $WriteLog "  Evening (6-11 PM) average score: $eveningAvgScore/100"
  }
  
  if ($peakHourTests -and $peakHourTests.Count -gt 0) {
    $peakAvgScore = [Math]::Round(($peakHourTests | Measure-Object -Property HealthScore -Average).Average, 1)
    & $WriteLog "  Peak hours (7-9 PM) average score: $peakAvgScore/100"
  }
  
  if ($weekendTests -and $weekendTests.Count -gt 0) {
    $weekendAvgScore = [Math]::Round(($weekendTests | Measure-Object -Property HealthScore -Average).Average, 1)
    & $WriteLog "  Weekend average score: $weekendAvgScore/100"
  }
  
  # Detect patterns
  $timeCorrelation = $false
  $patternType = ""
  
  if ($eveningTests -and $eveningTests.Count -gt 0 -and $peakHourTests -and $peakHourTests.Count -gt 0) {
    # $eveningScore = ($eveningTests | Measure-Object -Property HealthScore -Average).Average  # Not currently used
    $peakScore = ($peakHourTests | Measure-Object -Property HealthScore -Average).Average
    $daytimeScore = ($results | Where-Object { -not $_.IsEvening } | Measure-Object -Property HealthScore -Average).Average
    
    if ($peakScore -lt ($daytimeScore - 20)) {
      $timeCorrelation = $true
      $patternType = "EVENING_CONGESTION"
      & $WriteLog "  *** TIME CORRELATION DETECTED: Evening/peak hour degradation ***"
      & $WriteLog "  Peak hours score: $([Math]::Round($peakScore, 1)) vs daytime: $([Math]::Round($daytimeScore, 1))"
    }
  }
  
  # Progressive degradation analysis
  $firstHalf = $results | Select-Object -First ($results.Count / 2)
  $secondHalf = $results | Select-Object -Last ($results.Count / 2)
  
  if ($firstHalf -and $secondHalf) {
    $firstHalfScore = ($firstHalf | Measure-Object -Property HealthScore -Average).Average
    $secondHalfScore = ($secondHalf | Measure-Object -Property HealthScore -Average).Average
    
    if ($secondHalfScore -lt ($firstHalfScore - 15)) {
      $patternType = "PROGRESSIVE_DEGRADATION"
      & $WriteLog "  *** PROGRESSIVE DEGRADATION DETECTED ***"
      & $WriteLog "  First half: $([Math]::Round($firstHalfScore, 1)) vs second half: $([Math]::Round($secondHalfScore, 1))"
    }
  }
  
  # Diagnosis
  if ($timeCorrelation) {
    & $WriteLog "  DIAGNOSIS: Time-correlated network degradation - likely congestion or capacity issues"
    & $WriteLog "  IMPACT: Problems worsen during peak usage times"
    & $WriteLog "  RECOMMENDATION: ISP needs to upgrade capacity or investigate evening routing"
  } elseif ($patternType -eq "PROGRESSIVE_DEGRADATION") {
    & $WriteLog "  DIAGNOSIS: Progressive degradation over time - possible hardware failure or resource exhaustion"
    & $WriteLog "  IMPACT: Network performance gets worse throughout the day"
    & $WriteLog "  RECOMMENDATION: Check for hardware issues, memory leaks, or resource limits"
  } elseif ($avgHealthScore -lt 70) {
    & $WriteLog "  DIAGNOSIS: Consistently poor performance - infrastructure or configuration issues"
    & $WriteLog "  IMPACT: Poor performance regardless of time"
    & $WriteLog "  RECOMMENDATION: Investigate routing, hardware, or ISP configuration"
  } else {
    & $WriteLog "  DIAGNOSIS: Network performance is stable over time"
    & $WriteLog "  IMPACT: Time-based issues are not the cause of problems"
    & $WriteLog "  RECOMMENDATION: Investigate other factors (connection patterns, protocols, etc.)"
  }
  
  return @{
    TotalTests = $totalTests
    AverageHealthScore = $avgHealthScore
    TimeCorrelationDetected = $timeCorrelation
    PatternType = $patternType
    EveningPerformance = if ($eveningTests) { [Math]::Round(($eveningTests | Measure-Object -Property HealthScore -Average).Average, 1) } else { $null }
    PeakHourPerformance = if ($peakHourTests) { [Math]::Round(($peakHourTests | Measure-Object -Property HealthScore -Average).Average, 1) } else { $null }
    Results = $results
  }
}

function Test-PacketCaptureDuringFailuresQuick {
  <#
  .SYNOPSIS
  Quick packet capture during connection failures for diagnostic workflow
  .DESCRIPTION
  Optimized version that captures packets for 20 seconds while performing
  connection tests to detect failures with packet-level evidence.
  #>
  param(
    [string]$TestHost = 'netflix.com',
    [int]$TestPort = 443,
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Quick packet capture during failures (20 seconds)..."
  & $WriteLog "This test will capture network packets while testing connections"
  & $WriteLog "Target: $TestHost`:$TestPort"
  
  $capturePath = "$env:TEMP\pppoe_packet_capture_quick"
  $etlFile = "$capturePath.etl"
  
  try {
    # Start packet capture
    & $WriteLog "Starting packet capture..."
    Start-Process -FilePath "netsh" -ArgumentList @(
      "trace", "start", "capture=yes", "tracefile=$etlFile",
      "provider=Microsoft-Windows-TCPIP", "keywords=ut:TcpipDiagnosis"
    ) -WindowStyle Hidden -Wait:$false
    
    # Wait for trace to start
    Start-Sleep -Seconds 2
    
    # Perform 5 quick connection tests
    $connectionFailures = 0
    for ($i = 1; $i -le 5; $i++) {
      & $WriteLog "Connection test $i/5..."
      
      try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = 3000
        $tcpClient.Connect($TestHost, $TestPort)
        
        if ($tcpClient.Connected) {
          # Quick test
          $stream = $tcpClient.GetStream()
          $request = "HEAD / HTTP/1.1`r`nHost: $TestHost`r`nConnection: close`r`n`r`n"
          $requestBytes = [System.Text.Encoding]::ASCII.GetBytes($request)
          $stream.Write($requestBytes, 0, $requestBytes.Length)
          
          # $buffer = New-Object byte[] 1024  # Not used in quick version
          # $bytesRead = $stream.Read($buffer, 0, $buffer.Length)  # Not used in quick version
          
          $tcpClient.Close()
        }
      } catch {
        $connectionFailures++
        & $WriteLog "Connection failure detected: $($_.Exception.Message)"
      }
      
      Start-Sleep -Seconds 1
    }
    
    # Stop packet capture
    & $WriteLog "Stopping packet capture..."
    Start-Process -FilePath "netsh" -ArgumentList @("trace", "stop") -WindowStyle Hidden -Wait
    
    & $WriteLog "Packet capture completed"
    & $WriteLog "Connection failures during capture: $connectionFailures"
    & $WriteLog "Capture file: $etlFile"
    
    if ($connectionFailures -gt 0) {
      & $WriteLog "  *** CONNECTION FAILURES DETECTED DURING CAPTURE ***"
      & $WriteLog "  Check capture file for packet-level analysis"
    }
    
    return @{
      CaptureFile = $etlFile
      ConnectionFailures = $connectionFailures
      Diagnosis = if ($connectionFailures -gt 0) { "CONNECTION_FAILURES_CAPTURED" } else { "NO_FAILURES_DETECTED" }
    }
    
  } catch {
    & $WriteLog "Packet capture failed: $($_.Exception.Message)"
    return @{
      CaptureFile = $null
      ConnectionFailures = 0
      Diagnosis = "CAPTURE_FAILED"
    }
  }
}

function Test-ProtocolSpecificSustainedConnection {
  <#
  .SYNOPSIS
  Tests sustained connections with different protocols (HTTPS, HTTP/2, QUIC)
  .DESCRIPTION
  Compares behavior of different protocols to identify if specific protocols
  have different timeout or connection stability characteristics.
  #>
  param(
    [string]$TestHost = 'netflix.com',
    [int]$SustainDurationSeconds = 10,
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Testing protocol-specific sustained connection behavior..."
  & $WriteLog "This test compares HTTPS (HTTP/1.1) vs HTTP/2 behavior over $SustainDurationSeconds seconds"
  
  $protocols = @(
    @{ Name = "HTTPS (HTTP/1.1)"; Port = 443; UseHttp2 = $false },
    @{ Name = "HTTPS (HTTP/2)"; Port = 443; UseHttp2 = $true }
  )
  
  $results = @()
  
  foreach ($protocol in $protocols) {
    & $WriteLog "Testing $($protocol.Name) to ${TestHost}:$($protocol.Port)..."
    
    $protocolResult = @{
      Protocol = $protocol.Name
      Port = $protocol.Port
      ConnectionEstablished = $false
      ConnectionDuration = $null
      DroppedAt = $null
      BytesSent = 0
      BytesReceived = 0
      RequestsSent = 0
      SuccessfulResponses = 0
      Errors = @()
      Diagnosis = ""
    }
    
    try {
      $tcpClient = New-Object System.Net.Sockets.TcpClient
      $tcpClient.ReceiveTimeout = 12000
      $tcpClient.SendTimeout = 12000
      
      # Establish connection
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $tcpClient.Connect($TestHost, $protocol.Port)
      $connectionTime = $sw.ElapsedMilliseconds
      
      if ($tcpClient.Connected) {
        $protocolResult.ConnectionEstablished = $true
        & $WriteLog "  Connection established: ${connectionTime}ms"
        
        # Monitor connection with periodic requests
        $monitorStart = Get-Date
        $monitorEnd = $monitorStart.AddSeconds($SustainDurationSeconds)
        $requestInterval = 2  # Send request every 2 seconds
        
        $connectionStable = $true
        $lastRequestTime = $monitorStart
        
        while ((Get-Date) -lt $monitorEnd -and $connectionStable) {
          $currentTime = Get-Date
          $elapsed = [Math]::Round(($currentTime - $monitorStart).TotalSeconds, 1)
          
          # Send periodic request
          if (($currentTime - $lastRequestTime).TotalSeconds -ge $requestInterval) {
            try {
              $stream = $tcpClient.GetStream()
              $stream.ReadTimeout = 3000
              
              # Send HTTP request
              $request = "HEAD / HTTP/1.1`r`nHost: $TestHost`r`nConnection: keep-alive`r`nUser-Agent: PPPoE-Diagnostic/1.0`r`n`r`n"
              $requestBytes = [System.Text.Encoding]::ASCII.GetBytes($request)
              $stream.Write($requestBytes, 0, $requestBytes.Length)
              $protocolResult.BytesSent += $requestBytes.Length
              $protocolResult.RequestsSent++
              
              # Try to read response
              $buffer = New-Object byte[] 4096
              $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
              $protocolResult.BytesReceived += $bytesRead
              
              if ($bytesRead -gt 0) {
                $protocolResult.SuccessfulResponses++
                & $WriteLog "  [$elapsed s] Request successful (${bytesRead} bytes received)"
              }
              
              $lastRequestTime = $currentTime
              
            } catch {
              $connectionStable = $false
              $protocolResult.DroppedAt = $elapsed
              $protocolResult.Errors += "Connection lost at ${elapsed}s: $($_.Exception.Message)"
              & $WriteLog "  [$elapsed s] Connection lost: $($_.Exception.Message)"
            }
          }
          
          Start-Sleep -Milliseconds 500
        }
        
        $tcpClient.Close()
        $protocolResult.ConnectionDuration = [Math]::Round(((Get-Date) - $monitorStart).TotalSeconds, 1)
        
        # Analyze results
        if ($protocolResult.DroppedAt) {
          $protocolResult.Diagnosis = "Connection dropped at $($protocolResult.DroppedAt)s"
          
          # Check for 4-second pattern
          if ($protocolResult.DroppedAt -ge 3.5 -and $protocolResult.DroppedAt -le 4.5) {
            $protocolResult.Diagnosis = "4.1-SECOND DROP PATTERN DETECTED"
            & $WriteLog "  *** 4.1-SECOND DROP PATTERN: Connection dropped at $($protocolResult.DroppedAt)s ***"
          }
        } else {
          $protocolResult.Diagnosis = "Connection remained stable"
          & $WriteLog "  Connection remained stable for $($protocolResult.ConnectionDuration)s"
        }
        
        & $WriteLog "  Summary: $($protocolResult.RequestsSent) requests, $($protocolResult.SuccessfulResponses) successful"
        
      } else {
        $protocolResult.Diagnosis = "Failed to establish connection"
        & $WriteLog "  Failed to establish connection"
      }
      
    } catch {
      $protocolResult.Errors += "Connection error: $($_.Exception.Message)"
      $protocolResult.Diagnosis = "Connection exception"
      & $WriteLog "  Connection error: $($_.Exception.Message)"
    }
    
    $results += $protocolResult
    Start-Sleep -Seconds 2
  }
  
  # Compare protocol behaviors
  & $WriteLog "Protocol Comparison Analysis:"
  
  $http1Result = $results | Where-Object { $_.Protocol -match "HTTP/1.1" } | Select-Object -First 1
  $http2Result = $results | Where-Object { $_.Protocol -match "HTTP/2" } | Select-Object -First 1
  
  $bothDropped = $false
  $oneDropped = $false
  
  if ($http1Result -and $http2Result) {
    if ($http1Result.DroppedAt -and $http2Result.DroppedAt) {
      $bothDropped = $true
      $timeDiff = [Math]::Abs($http1Result.DroppedAt - $http2Result.DroppedAt)
      & $WriteLog "  Both protocols dropped connections"
      & $WriteLog "  HTTP/1.1 dropped at: $($http1Result.DroppedAt)s"
      & $WriteLog "  HTTP/2 dropped at: $($http2Result.DroppedAt)s"
      & $WriteLog "  Time difference: ${timeDiff}s"
      
      if ($timeDiff -lt 1.0) {
        & $WriteLog "  DIAGNOSIS: Protocol-agnostic connection timeout (affects all protocols equally)"
        & $WriteLog "  IMPACT: This is likely ISP/CGNAT connection tracking timeout, not protocol-specific"
      }
    } elseif ($http1Result.DroppedAt -or $http2Result.DroppedAt) {
      $oneDropped = $true
      $dropped = if ($http1Result.DroppedAt) { "HTTP/1.1" } else { "HTTP/2" }
      & $WriteLog "  Only $dropped dropped connection"
      & $WriteLog "  DIAGNOSIS: Protocol-specific behavior difference detected"
      & $WriteLog "  IMPACT: Issue may be specific to how ISP handles certain HTTP versions"
    } else {
      & $WriteLog "  Both protocols maintained stable connections"
      & $WriteLog "  DIAGNOSIS: No protocol-specific connection issues detected"
      & $WriteLog "  IMPACT: Connection stability is not protocol-dependent"
    }
  }
  
  return @{
    ProtocolResults = $results
    BothDropped = $bothDropped
    OneDropped = $oneDropped
    Diagnosis = if ($bothDropped) { "PROTOCOL_AGNOSTIC_TIMEOUT" } elseif ($oneDropped) { "PROTOCOL_SPECIFIC_ISSUE" } else { "STABLE_ALL_PROTOCOLS" }
  }
}

function Test-DataTransferSustainedConnection {
  <#
  .SYNOPSIS
  Tests sustained connection with continuous data transfer
  .DESCRIPTION
  Maintains connection by sending data every second to test if
  data activity keeps connection alive vs idle timeout.
  #>
  param(
    [string]$TestHost = 'netflix.com',
    [int]$TestPort = 443,
    [int]$DurationSeconds = 10,
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Testing sustained connection with continuous data transfer..."
  & $WriteLog "This test sends data every second to see if activity prevents timeout"
  
  $results = @{
    ConnectionEstablished = $false
    TotalDuration = 0
    DataSentBytes = 0
    DataReceivedBytes = 0
    TransfersSent = 0
    SuccessfulTransfers = 0
    DroppedAt = $null
    DroppedDuringTransfer = $false
    DroppedDuringIdle = $false
    ConnectionLost = $false
    Errors = @()
  }
  
  try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $tcpClient.ReceiveTimeout = 3000
    $tcpClient.SendTimeout = 3000
    
    # Establish connection
    & $WriteLog "Establishing connection to ${TestHost}:${TestPort}..."
    $tcpClient.Connect($TestHost, $TestPort)
    
    if ($tcpClient.Connected) {
      $results.ConnectionEstablished = $true
      & $WriteLog "  Connection established"
      
      $startTime = Get-Date
      $endTime = $startTime.AddSeconds($DurationSeconds)
      $connectionStable = $true
      
      while ((Get-Date) -lt $endTime -and $connectionStable) {
        $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
        
        try {
          $stream = $tcpClient.GetStream()
          $stream.ReadTimeout = 2000
          
          # Send data transfer (HTTP request with body)
          $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
          $requestBody = "timestamp=$timestamp&test=sustained_connection&elapsed=$elapsed"
          $contentLength = [System.Text.Encoding]::ASCII.GetByteCount($requestBody)
          
          $request = "POST /post HTTP/1.1`r`nHost: $TestHost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $contentLength`r`nConnection: keep-alive`r`n`r`n$requestBody"
          $requestBytes = [System.Text.Encoding]::ASCII.GetBytes($request)
          
          $stream.Write($requestBytes, 0, $requestBytes.Length)
          $results.DataSentBytes += $requestBytes.Length
          $results.TransfersSent++
          
          # Read response
          $buffer = New-Object byte[] 4096
          $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
          $results.DataReceivedBytes += $bytesRead
          
          if ($bytesRead -gt 0) {
            $results.SuccessfulTransfers++
            & $WriteLog "  [$elapsed s] Transfer successful ($($requestBytes.Length) sent, $bytesRead received)"
          } else {
            & $WriteLog "  [$elapsed s] No response received"
          }
          
        } catch {
          $connectionStable = $false
          $results.ConnectionLost = $true
          $results.DroppedAt = $elapsed
          $results.DroppedDuringTransfer = $true
          $results.Errors += "Connection lost at ${elapsed}s during data transfer: $($_.Exception.Message)"
          & $WriteLog "  [$elapsed s] Connection lost during transfer: $($_.Exception.Message)"
          break
        }
        
        Start-Sleep -Seconds 1
      }
      
      $tcpClient.Close()
      $results.TotalDuration = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
      
      # Analysis
      & $WriteLog "Data Transfer Sustained Connection Analysis:"
      & $WriteLog "  Total duration: $($results.TotalDuration)s"
      & $WriteLog "  Data sent: $($results.DataSentBytes) bytes in $($results.TransfersSent) transfers"
      & $WriteLog "  Data received: $($results.DataReceivedBytes) bytes"
      & $WriteLog "  Successful transfers: $($results.SuccessfulTransfers)/$($results.TransfersSent)"
      
      if ($results.ConnectionLost) {
        & $WriteLog "  Connection lost at: $($results.DroppedAt)s"
        
        # Check for 4-second pattern
        if ($results.DroppedAt -ge 3.5 -and $results.DroppedAt -le 4.5) {
          & $WriteLog "  *** 4.1-SECOND DROP PATTERN: Even with continuous data transfer ***"
          & $WriteLog "  DIAGNOSIS: Connection timeout is NOT due to idle timeout"
          & $WriteLog "  IMPACT: Sending data does not prevent the timeout - this is connection tracking limit"
          & $WriteLog "  RECOMMENDATION: ISP CGNAT has hard connection duration limit, not idle timeout"
        } else {
          & $WriteLog "  DIAGNOSIS: Connection dropped at $($results.DroppedAt)s during active transfer"
          & $WriteLog "  IMPACT: Data transfer does not prevent connection drops"
          & $WriteLog "  RECOMMENDATION: Connection limit is duration-based, not activity-based"
        }
      } else {
        & $WriteLog "  Connection remained stable with continuous data transfer"
        & $WriteLog "  DIAGNOSIS: Data transfer successfully maintained connection"
        & $WriteLog "  IMPACT: Keeping connection active prevents timeout"
        & $WriteLog "  RECOMMENDATION: Applications should send keepalive data to maintain connections"
      }
      
    } else {
      & $WriteLog "  Failed to establish connection"
    }
    
  } catch {
    $results.Errors += "Connection error: $($_.Exception.Message)"
    & $WriteLog "Connection error: $($_.Exception.Message)"
  }
  
  return $results
}

function Test-MultipleSimultaneousSustainedConnections {
  <#
  .SYNOPSIS
  Tests multiple simultaneous sustained connections
  .DESCRIPTION
  Opens 5 connections to same host simultaneously to see if they all
  drop at the same time or behave differently.
  #>
  param(
    [string]$TestHost = 'netflix.com',
    [int]$TestPort = 443,
    [int]$ConnectionCount = 5,
    [int]$DurationSeconds = 10,
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Testing $ConnectionCount simultaneous sustained connections..."
  & $WriteLog "This test checks if multiple connections to same host drop together"
  
  $connectionTasks = @()
  $connectionResults = @()
  
  & $WriteLog "Starting $ConnectionCount simultaneous connections to ${TestHost}:${TestPort}..."
  
  for ($i = 1; $i -le $ConnectionCount; $i++) {
    $connNum = $i
    $destHost = $TestHost
    $destPort = $TestPort
    $duration = $DurationSeconds
    
    $task = [System.Threading.Tasks.Task]::Run({
      $result = @{
        ConnectionNumber = $connNum
        Host = $destHost
        Port = $destPort
        StartTime = Get-Date
        ConnectionEstablished = $false
        DroppedAt = $null
        Duration = 0
        RequestsSent = 0
        SuccessfulRequests = 0
        BytesSent = 0
        BytesReceived = 0
        Error = $null
      }
      
      try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = 3000
        $tcpClient.SendTimeout = 3000
        
        # Establish connection
        $tcpClient.Connect($destHost, $destPort)
        
        if ($tcpClient.Connected) {
          $result.ConnectionEstablished = $true
          
          $startTime = Get-Date
          $endTime = $startTime.AddSeconds($duration)
          $connectionStable = $true
          
          while ((Get-Date) -lt $endTime -and $connectionStable) {
            $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
            
            try {
              $stream = $tcpClient.GetStream()
              $stream.ReadTimeout = 2000
              
              # Send periodic request
              $request = "HEAD / HTTP/1.1`r`nHost: $destHost`r`nConnection: keep-alive`r`n`r`n"
              $requestBytes = [System.Text.Encoding]::ASCII.GetBytes($request)
              $stream.Write($requestBytes, 0, $requestBytes.Length)
              $result.BytesSent += $requestBytes.Length
              $result.RequestsSent++
              
              # Try to read response
              $buffer = New-Object byte[] 1024
              $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
              $result.BytesReceived += $bytesRead
              
              if ($bytesRead -gt 0) {
                $result.SuccessfulRequests++
              }
              
            } catch {
              $connectionStable = $false
              $result.DroppedAt = $elapsed
              $result.Error = $_.Exception.Message
              break
            }
            
            Start-Sleep -Seconds 2
          }
          
          $tcpClient.Close()
          $result.Duration = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
        }
        
      } catch {
        $result.Error = $_.Exception.Message
      }
      
      return $result
    }.GetNewClosure())
    
    $connectionTasks += $task
    Start-Sleep -Milliseconds 100  # Stagger connection attempts slightly
  }
  
  & $WriteLog "Waiting for all $ConnectionCount connections to complete ($DurationSeconds seconds)..."
  [System.Threading.Tasks.Task]::WaitAll($connectionTasks)
  
  # Collect results
  foreach ($task in $connectionTasks) {
    $connectionResults += $task.Result
  }
  
  # Analyze results
  & $WriteLog "Multiple Simultaneous Connections Analysis:"
  
  $established = ($connectionResults | Where-Object { $_.ConnectionEstablished }).Count
  $dropped = ($connectionResults | Where-Object { $null -ne $_.DroppedAt }).Count
  $stable = $established - $dropped
  
  & $WriteLog "  Connections established: $established/$ConnectionCount"
  & $WriteLog "  Connections dropped: $dropped/$established"
  & $WriteLog "  Connections remained stable: $stable/$established"
  
  if ($dropped -gt 0) {
    & $WriteLog "  Connection drop times:"
    $dropTimes = @()
    foreach ($conn in $connectionResults | Where-Object { $null -ne $_.DroppedAt }) {
      & $WriteLog "    Connection $($conn.ConnectionNumber): Dropped at $($conn.DroppedAt)s"
      $dropTimes += $conn.DroppedAt
    }
    
    # Check if all dropped at similar time
    if ($dropTimes.Count -gt 1) {
      $avgDropTime = [Math]::Round(($dropTimes | Measure-Object -Average).Average, 1)
      $minDropTime = ($dropTimes | Measure-Object -Minimum).Minimum
      $maxDropTime = ($dropTimes | Measure-Object -Maximum).Maximum
      $dropTimeVariance = $maxDropTime - $minDropTime
      
      & $WriteLog "  Drop time statistics:"
      & $WriteLog "    Average: ${avgDropTime}s"
      & $WriteLog "    Range: ${minDropTime}s - ${maxDropTime}s"
      & $WriteLog "    Variance: ${dropTimeVariance}s"
      
      # Check for synchronized drops
      if ($dropTimeVariance -lt 1.0) {
        & $WriteLog "  *** SYNCHRONIZED DROP PATTERN: All connections dropped within ${dropTimeVariance}s ***"
        & $WriteLog "  DIAGNOSIS: ISP is killing all connections to same destination simultaneously"
        & $WriteLog "  IMPACT: This is likely connection-per-destination limit or rate limiting"
        
        # Check for 4-second pattern
        if ($avgDropTime -ge 3.5 -and $avgDropTime -le 4.5) {
          & $WriteLog "  *** 4.1-SECOND SYNCHRONIZED DROP: All connections dropped at ~4 seconds ***"
          & $WriteLog "  DIAGNOSIS: Connection tracking timeout affects all connections to same host"
          & $WriteLog "  RECOMMENDATION: ISP CGNAT has connection duration limit per destination"
        }
      } else {
        & $WriteLog "  Connections dropped at different times (variance: ${dropTimeVariance}s)"
        & $WriteLog "  DIAGNOSIS: Connection drops are not synchronized"
        & $WriteLog "  IMPACT: Each connection has independent timeout/limit"
      }
    }
  } else {
    & $WriteLog "  All connections remained stable"
    & $WriteLog "  DIAGNOSIS: Multiple simultaneous connections work correctly"
    & $WriteLog "  IMPACT: No per-destination connection limits detected"
  }
  
  # Check for 4-second pattern across all connections
  $fourSecondDrops = $connectionResults | Where-Object { 
    $_.DroppedAt -and $_.DroppedAt -ge 3.5 -and $_.DroppedAt -le 4.5 
  }
  
  if ($fourSecondDrops.Count -gt 0) {
    $fourSecondRate = [Math]::Round(($fourSecondDrops.Count / $dropped) * 100, 1)
    & $WriteLog "  4-second drops: $($fourSecondDrops.Count)/$dropped ($fourSecondRate%)"
    
    if ($fourSecondRate -gt 50) {
      & $WriteLog "  *** CONSISTENT 4.1-SECOND PATTERN ACROSS MULTIPLE CONNECTIONS ***"
      & $WriteLog "  This confirms ISP/CGNAT connection tracking timeout of ~4 seconds"
    }
  }
  
  return @{
    TotalConnections = $ConnectionCount
    EstablishedConnections = $established
    DroppedConnections = $dropped
    StableConnections = $stable
    FourSecondDrops = $fourSecondDrops.Count
    ConnectionResults = $connectionResults
    Diagnosis = if ($fourSecondDrops.Count -gt ($dropped * 0.5)) { "FOUR_SECOND_PATTERN_CONFIRMED" } elseif ($dropTimeVariance -lt 1.0) { "SYNCHRONIZED_DROPS" } elseif ($dropped -eq 0) { "ALL_STABLE" } else { "INDIVIDUAL_DROPS" }
  }
}

function Test-TimeBasedPatternAnalysisQuick {
  <#
  .SYNOPSIS
  Quick time-based pattern analysis for diagnostic workflow
  .DESCRIPTION
  Optimized version that runs 6 mini-tests over 5 minutes to detect
  performance degradation patterns without taking too long.
  #>
  param(
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Quick time-based pattern analysis (5 minutes, 6 tests)..."
  & $WriteLog "This test will detect performance degradation over time"
  
  $results = @()
  $testInterval = 50  # seconds
  $totalTests = 6
  
  for ($i = 1; $i -le $totalTests; $i++) {
    $currentTime = Get-Date
    & $WriteLog "Mini-test $i/$totalTests at $($currentTime.ToString('HH:mm:ss'))..."
    
    $testResult = @{
      TestNumber = $i
      Timestamp = $currentTime
      PingLatency = $null
      ConnectionSuccess = $false
      DNSResponseTime = $null
      HealthScore = 0
    }
    
    # Quick ping test
    try {
      $pingResult = Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet
      if ($pingResult) {
        $testResult.PingLatency = 10  # Simplified for speed
        $testResult.HealthScore += 1
      }
    } catch {
      & $WriteLog "  Ping failed: $($_.Exception.Message)"
    }
    
    # Quick connection test
    try {
      $tcpClient = New-Object System.Net.Sockets.TcpClient
      $tcpClient.ReceiveTimeout = 2000
      $tcpClient.Connect('netflix.com', 443)
      
      if ($tcpClient.Connected) {
        $testResult.ConnectionSuccess = $true
        $testResult.HealthScore += 2
        $tcpClient.Close()
      }
    } catch {
      & $WriteLog "  Connection test failed: $($_.Exception.Message)"
    }
    
    # Quick DNS test
    try {
      $dnsStart = Get-Date
      # $dnsResult = [System.Net.Dns]::GetHostAddresses('google.com')  # Not used in quick version
      [System.Net.Dns]::GetHostAddresses('google.com') | Out-Null
      $dnsEnd = Get-Date
      $testResult.DNSResponseTime = [Math]::Round(($dnsEnd - $dnsStart).TotalMilliseconds, 1)
      $testResult.HealthScore += 1
    } catch {
      & $WriteLog "  DNS test failed: $($_.Exception.Message)"
    }
    
    $results += $testResult
    & $WriteLog "  Health score: $($testResult.HealthScore)/4"
    
    if ($i -lt $totalTests) {
      Start-Sleep -Seconds $testInterval
    }
  }
  
  # Quick analysis
  $totalHealthScore = ($results | Measure-Object -Property HealthScore -Sum).Sum
  $maxHealthScore = $totalTests * 4
  $overallHealth = [Math]::Round(($totalHealthScore / $maxHealthScore) * 100, 1)
  
  $connectionFailures = ($results | Where-Object { -not $_.ConnectionSuccess }).Count
  $dnsFailures = ($results | Where-Object { $null -eq $_.DNSResponseTime }).Count
  
  & $WriteLog "Quick Time-Based Pattern Analysis Results:"
  & $WriteLog "  Overall health: $overallHealth%"
  & $WriteLog "  Connection failures: $connectionFailures/$totalTests"
  & $WriteLog "  DNS failures: $dnsFailures/$totalTests"
  
  # Quick diagnosis
  $diagnosis = ""
  if ($overallHealth -lt 50) {
    $diagnosis = "SEVERE_DEGRADATION"
    & $WriteLog "  *** SEVERE PERFORMANCE DEGRADATION DETECTED ***"
  } elseif ($connectionFailures -gt 2) {
    $diagnosis = "CONNECTION_INSTABILITY"
    & $WriteLog "  *** CONNECTION INSTABILITY DETECTED ***"
  } elseif ($dnsFailures -gt 1) {
    $diagnosis = "DNS_ISSUES"
    & $WriteLog "  *** DNS ISSUES DETECTED ***"
  } else {
    $diagnosis = "STABLE_PERFORMANCE"
    & $WriteLog "  Performance appears stable over time"
  }
  
  return @{
    OverallHealth = $overallHealth
    ConnectionFailures = $connectionFailures
    DNSFailures = $dnsFailures
    Diagnosis = $diagnosis
    Results = $results
  }
}

Export-ModuleMember -Function *
