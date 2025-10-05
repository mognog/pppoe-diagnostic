# PPPoE.Net.Diagnostics.psm1 - Network diagnostic functions

Set-StrictMode -Version 3.0

function Test-ONTAvailability {
  param([scriptblock]$WriteLog)
  
  & $WriteLog "Testing ONT (Optical Network Terminal) availability..."
  
  # Common ONT management IP addresses
  $ontIPs = @('192.168.1.1', '192.168.100.1', '192.168.0.1', '10.0.0.1')
  $ontResults = @()
  
  foreach ($ip in $ontIPs) {
    try {
      & $WriteLog "Testing ONT at $ip... (testing 4 common ONT addresses)"
      $ping = Test-Connection -TargetName $ip -Count 2 -TimeoutSeconds 3 -ErrorAction Stop
      if ($ping -and $ping.Count -gt 0) {
        $avgLatency = [Math]::Round(($ping | Measure-Object -Property Latency -Average).Average, 1)
        & $WriteLog "  ONT at $ip`: REACHABLE (${avgLatency}ms avg)"
        $ontResults += @{ IP = $ip; Status = "REACHABLE"; Latency = $avgLatency }
      } else {
        & $WriteLog "  ONT at $ip`: UNREACHABLE"
        $ontResults += @{ IP = $ip; Status = "UNREACHABLE"; Latency = $null }
      }
    } catch {
      & $WriteLog "  ONT at $ip`: UNREACHABLE"
      $ontResults += @{ IP = $ip; Status = "UNREACHABLE"; Latency = $null }
    }
  }
  
  # Check if any ONT is reachable
  $reachableONTs = $ontResults | Where-Object { $_.Status -eq "REACHABLE" }
  if ($reachableONTs -and $reachableONTs -is [array] -and $reachableONTs.Count -gt 0) {
    & $WriteLog "ONT Status: At least one ONT is reachable - local link appears OK"
    return @{ Status = "OK"; ReachableONTs = $reachableONTs; AllResults = $ontResults }
  } else {
    & $WriteLog "ONT Status: No ONTs reachable - possible fibre or ONT issue"
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
    }
    
  } catch {
    & $WriteLog "Error checking firewall state: $($_.Exception.Message)"
    return $null
  }
}

Export-ModuleMember -Function *
