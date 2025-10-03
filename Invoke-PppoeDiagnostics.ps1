# Invoke-PppoeDiagnostics.ps1 - main entry

#Requires -Version 7.0

param(
  [string]$PppoeName = 'PPPoE',
  [string]$UserName,
  [string]$Password,
  [string]$TargetAdapter,
  [switch]$FullLog,
  [switch]$SkipWifiToggle,
  [switch]$KeepPPP
)

#Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here/Modules/PPPoE.Core.psm1" -Force
Import-Module "$here/Modules/PPPoE.Net.psm1" -Force
Import-Module "$here/Modules/PPPoE.Logging.psm1" -Force
Import-Module "$here/Modules/PPPoE.Health.psm1" -Force

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $here "logs/pppoe_transcript_$ts.txt"

try {
  Start-AsciiTranscript -Path $logPath
  Show-Banner
  Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"
  Write-Log "Script path: $($MyInvocation.MyCommand.Path)"

  $Health = New-Health

  # Define health check order for logical grouping
  # Order 1-5: Basic system checks
  # Order 6-10: Network adapter and link checks  
  # Order 11-15: PPPoE connection and authentication
  # Order 16-20: Connectivity tests (grouped together)

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
        Write-Ok "Found PPPoE connection: $connName (exists but cannot connect - no physical adapter)"
      }
    } catch {
      # Connection doesn't exist or other error
    }
  }
  
  if ($pppoeConnections.Count -gt 0) {
    Write-Ok "Found existing PPPoE connections: $($pppoeConnections -join ', ')"
    $Health = Add-Health $Health 'PPPoE connections configured' "OK ($($pppoeConnections.Count) found: $($pppoeConnections -join ', '))" 2
    
    # [2.5] Check for credentials immediately after finding connections
    # Check for external credentials file first
    $credentialsFile = Join-Path $here "credentials.ps1"
    if (Test-Path $credentialsFile) {
      try {
        Write-Log "[DEBUG] Found credentials file, loading external credentials"
        . $credentialsFile
        # Check if credentials are actually provided (not null or empty)
        if ($PPPoE_Username -and $PPPoE_Password -and 
            $PPPoE_Username.Trim() -ne '' -and $PPPoE_Password.Trim() -ne '') {
          $UserName = $PPPoE_Username
          $Password = $PPPoE_Password
          if ($PPPoE_ConnectionName -and $PPPoE_ConnectionName.Trim() -ne '') {
            $PppoeName = $PPPoE_ConnectionName
          }
          $Health = Add-Health $Health 'Credentials source' "OK (Loaded from credentials.ps1 for: $UserName)" 3
          Write-Log "Loaded credentials from file for user: $UserName"
        } else {
          Write-Log "[DEBUG] Credentials file exists but values are empty/null, will use saved Windows credentials"
          $Health = Add-Health $Health 'Credentials source' 'OK (Using saved Windows credentials)' 3
          Write-Log "Using saved Windows credentials (cannot display username due to security restrictions)"
        }
      } catch {
        Write-Log "[WARN] Failed to load credentials from file: $($_.Exception.Message)"
        $Health = Add-Health $Health 'Credentials source' 'OK (Using saved Windows credentials)' 3
        Write-Log "Using saved Windows credentials (cannot display username due to security restrictions)"
      }
    } else {
      $Health = Add-Health $Health 'Credentials source' 'OK (Using saved Windows credentials)' 3
      Write-Log "Using saved Windows credentials (cannot display username due to security restrictions)"
    }
  } else {
    Write-Warn "No PPPoE connections configured in Windows"
    $Health = Add-Health $Health 'PPPoE connections configured' 'WARN (none found)' 2
    $Health = Add-Health $Health 'Credentials source' 'N/A' 3
    Write-Log "[DEBUG] Tested connection names: $($testConnections -join ', ')"
    Write-Log "[DEBUG] Available network connections:"
    try {
      $allConnections = Get-NetConnectionProfile | Select-Object -ExpandProperty Name
      Write-Log "[DEBUG] $($allConnections -join ', ')"
    } catch {
      Write-Log "[DEBUG] Could not retrieve network connections list"
    }
  }

  # [3] NIC selection
  $nic = $null
  if ($TargetAdapter) {
    try { $nic = Get-NetAdapter -Name $TargetAdapter -ErrorAction Stop } catch { $nic = $null }
  }
  if (-not $nic) { $nic = Get-RecommendedAdapter }

  if ($null -eq $nic) {
    Write-Err "No Ethernet adapters detected"
    $Health = Add-Health $Health 'Physical adapter detected' 'FAIL (none found)' 3
    throw "No adapter"
  } else {
    Write-Ok "Selected adapter: $($nic.Name) / $($nic.InterfaceDescription) @ $($nic.LinkSpeed)"
    $Health = Add-Health $Health 'Physical adapter detected' "OK ($($nic.InterfaceDescription) @ $($nic.LinkSpeed))" 3
  }

  # [4] Link state gate
  if (Ensure-LinkUp -AdapterName $nic.Name) {
    $Health = Add-Health $Health 'Ethernet link state' 'OK (Up)' 4
  } else {
    Write-Err "Ethernet link is down (0 bps / Disconnected)"
    $Health = Add-Health $Health 'Ethernet link state' 'FAIL (Down)' 4
    # Skip PPP attempt if link is down - set all remaining checks to N/A
    $Health = Add-Health $Health 'Credentials source' 'N/A' 11
    $Health = Add-Health $Health 'PPPoE authentication' 'N/A' 12
    $Health = Add-Health $Health 'PPP interface present' 'N/A' 13
    $Health = Add-Health $Health 'PPP IPv4 assignment' 'N/A' 14
    $Health = Add-Health $Health 'Default route via PPP' 'N/A' 15
    $Health = Add-Health $Health 'Public IP classification' 'N/A' 16
    $Health = Add-Health $Health 'Gateway reachability' 'N/A' 17
    $Health = Add-Health $Health 'Ping (1.1.1.1) via PPP' 'N/A' 18
    $Health = Add-Health $Health 'Ping (8.8.8.8) via PPP' 'N/A' 19
    $Health = Add-Health $Health 'MTU probe (DF)' 'N/A' 20
    # Don't return early - let the script continue to show the complete health summary
  }

  # Clean previous PPP state
  Disconnect-PPP -PppoeName $PppoeName

  # Determine if we should use saved credentials or provided ones
  $useSaved = $false
  if ([string]::IsNullOrWhiteSpace($UserName) -or [string]::IsNullOrWhiteSpace($Password)) {
    $useSaved = $true
  }

  # Connect
  Write-Log "Attempting PPPoE connect: $PppoeName (SavedCreds=$useSaved)"
  $res = Connect-PPP -PppoeName $PppoeName -UserName $UserName -Password $Password -UseSaved:$useSaved
  $out = ($res.Output -replace '[^\x00-\x7F]', '?')
  Write-Log "rasdial exit=$($res.Code) output:`n$out"

  # Map rasdial errors
  $authOk = $false
  if ($res.Success) { 
    $authOk = $true 
    $Health = Add-Health $Health 'PPPoE authentication' 'OK' 12
  } else {
    $reason = switch ($res.Code) {
      691 { '691 bad credentials' }
      651 { '651 modem (device) error' }
      619 { '619 port disconnected' }
      678 { '678 no answer (no PADO)' }
      default { "code $($res.Code)" }
    }
    $Health = Add-Health $Health 'PPPoE authentication' ("FAIL ($reason)") 12
  }

  # Validate PPP interface materialization
  $pppIf = $null
  $pppIP = $null
  $defViaPPP = $false

  if ($authOk) {
    $pppIf = Get-PppInterface -PppoeName $PppoeName
    if ($pppIf -and $pppIf.ConnectionState -eq 'Connected') {
      $Health = Add-Health $Health 'PPP interface present' ("OK (IfIndex $($pppIf.InterfaceIndex), '$($pppIf.InterfaceAlias)')") 13
      $pppIP = Get-PppIPv4 -IfIndex $pppIf.InterfaceIndex
      if ($pppIP) {
        $Health = Add-Health $Health 'PPP IPv4 assignment' ("OK ($($pppIP.IPAddress)/$($pppIP.PrefixLength))") 14
      } else {
        $Health = Add-Health $Health 'PPP IPv4 assignment' ("FAIL (no non-APIPA IPv4)") 14
      }

      $defViaPPP = Test-DefaultRouteVia -IfIndex $pppIf.InterfaceIndex
      if ($defViaPPP) {
        $Health = Add-Health $Health 'Default route via PPP' 'OK' 15
      } else {
        $Health = Add-Health $Health 'Default route via PPP' 'WARN (still via other interface)' 15
      }
    } else {
      $Health = Add-Health $Health 'PPP interface present' 'FAIL (not created/connected)' 13
      $Health = Add-Health $Health 'PPP IPv4 assignment' 'FAIL (no interface)' 14
      $Health = Add-Health $Health 'Default route via PPP' 'FAIL (no interface)' 15
    }
  } else {
    $Health = Add-Health $Health 'PPP interface present' 'N/A' 13
    $Health = Add-Health $Health 'PPP IPv4 assignment' 'N/A' 14
    $Health = Add-Health $Health 'Default route via PPP' 'N/A' 15
  }

  # Public IP classification & gateway reachability
  if ($pppIP) {
    $cls = Get-IpClass -IPv4 $pppIP.IPAddress
    switch ($cls) {
      'PUBLIC' { $Health = Add-Health $Health 'Public IP classification' 'OK (Public)' 16 }
      'CGNAT'  { $Health = Add-Health $Health 'Public IP classification' 'WARN (CGNAT 100.64/10)' 16 }
      'PRIVATE'{ $Health = Add-Health $Health 'Public IP classification' 'WARN (Private RFC1918)' 16 }
      'APIPA'  { $Health = Add-Health $Health 'Public IP classification' 'FAIL (APIPA)' 16 }
      default  { $Health = Add-Health $Health 'Public IP classification' "WARN ($cls)" 16 }
    }

    # Gateway (peer) reachability: ping default gateway of PPP if present
    $route = Get-NetRoute -InterfaceIndex $pppIf.InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
             Sort-Object -Property RouteMetric |
             Select-Object -First 1
    $gw = if ($route) { $route.NextHop } else { $null }
    if ($gw) {
      $okGw = Test-PingHost -TargetName $gw -Count 2 -TimeoutMs 1000 -Source $pppIP.IPAddress
      if ($okGw) { $Health = Add-Health $Health 'Gateway reachability' 'OK' 17 }
      else { $Health = Add-Health $Health 'Gateway reachability' 'FAIL (unreachable)' 17 }
    } else {
      $Health = Add-Health $Health 'Gateway reachability' 'WARN (no default route record)' 17
    }

    # External ping via PPP (grouped together)
    $ok11 = Test-PingHost -TargetName '1.1.1.1' -Count 2 -TimeoutMs 1000 -Source $pppIP.IPAddress
    $Health = Add-Health $Health 'Ping (1.1.1.1) via PPP' ($ok11 ? 'OK' : 'FAIL') 18
    
    $ok88 = Test-PingHost -TargetName '8.8.8.8' -Count 2 -TimeoutMs 1000 -Source $pppIP.IPAddress
    $Health = Add-Health $Health 'Ping (8.8.8.8) via PPP' ($ok88 ? 'OK' : 'FAIL') 19

    # MTU probe (rough)
    # We try payload 1472 with DF; if success -> ~1492 MTU on PPP
    try {
      $ping = Test-Connection -TargetName '1.1.1.1' -Count 1 -DontFragment -BufferSize 1472 -TimeoutSeconds 2 -ErrorAction Stop
      $Health = Add-Health $Health 'MTU probe (DF)' 'OK (~1492, payload 1472)' 20
    } catch {
      $Health = Add-Health $Health 'MTU probe (DF)' 'WARN (payload 1472 blocked; lower MTU)' 20
    }

  } else {
    $Health = Add-Health $Health 'Public IP classification' 'N/A' 16
    $Health = Add-Health $Health 'Gateway reachability' 'N/A' 17
    $Health = Add-Health $Health 'Ping (1.1.1.1) via PPP' 'N/A' 18
    $Health = Add-Health $Health 'Ping (8.8.8.8) via PPP' 'N/A' 19
    $Health = Add-Health $Health 'MTU probe (DF)' 'N/A' 20
  }

} catch {
  Write-Err "Fatal error: $($_.Exception.Message)"
} finally {
  if (-not $KeepPPP) { Disconnect-PPP -PppoeName $PppoeName }
  Write-HealthSummary -Health $Health
  Write-Log "Transcript saved to $logPath"
  Stop-AsciiTranscript
}


