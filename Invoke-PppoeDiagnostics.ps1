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

  # Initialize health entries in logical order
  Add-Health $Health 'PowerShell version' ''
  Add-Health $Health 'PPPoE connections configured' ''
  Add-Health $Health 'Physical adapter detected' ''

  # [1] PowerShell 7+
  if (Test-PwshVersion7Plus) {
    $Health['PowerShell version'] = "OK ($($PSVersionTable.PSVersion))"
  } else {
    $Health['PowerShell version'] = "FAIL ($($PSVersionTable.PSVersion))"
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
    $Health['PPPoE connections configured'] = "OK ($($pppoeConnections.Count) found: $($pppoeConnections -join ', '))"
  } else {
    Write-Warn "No PPPoE connections configured in Windows"
    $Health['PPPoE connections configured'] = 'WARN (none found)'
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
    $Health['Physical adapter detected'] = 'FAIL (none found)'
    throw "No adapter"
  } else {
    Write-Ok "Selected adapter: $($nic.Name) / $($nic.InterfaceDescription) @ $($nic.LinkSpeed)"
    $Health['Physical adapter detected'] = "OK ($($nic.InterfaceDescription) @ $($nic.LinkSpeed))"
  }

  # [4] Link state gate
  if (Ensure-LinkUp -AdapterName $nic.Name) {
    Add-Health $Health 'Ethernet link state' 'OK (Up)'
  } else {
    Write-Err "Ethernet link is down (0 bps / Disconnected)"
    Add-Health $Health 'Ethernet link state' 'FAIL (Down)'
    # Skip PPP attempt if link is down
    Add-Health $Health 'Credentials source' 'N/A'
    Add-Health $Health 'PPPoE authentication' 'N/A'
    Add-Health $Health 'PPP interface present' 'N/A'
    Add-Health $Health 'PPP IPv4 assignment' 'N/A'
    Add-Health $Health 'Default route via PPP' 'N/A'
    Add-Health $Health 'Public IP classification' 'N/A'
    Add-Health $Health 'Gateway reachability' 'N/A'
    Add-Health $Health 'Ping (1.1.1.1) via PPP' 'N/A'
    Add-Health $Health 'Ping (8.8.8.8) via PPP' 'N/A'
    Add-Health $Health 'MTU probe (DF)' 'N/A'
    Write-HealthSummary -Health $Health
    return
  }

  # Clean previous PPP state
  Disconnect-PPP -PppoeName $PppoeName

  $useSaved = $false
  if ([string]::IsNullOrWhiteSpace($UserName) -or [string]::IsNullOrWhiteSpace($Password)) {
    $useSaved = $true
    $savedUsername = Get-SavedPppoeUsername -PppoeName $PppoeName
    if ($savedUsername) {
      Add-Health $Health 'Credentials source' "OK (Using saved credentials for: $savedUsername)"
      Write-Log "Found saved credentials for user: $savedUsername"
    } else {
      Add-Health $Health 'Credentials source' 'WARN (Using saved credentials - username not retrievable)'
      Write-Log "Using saved credentials (username not accessible)"
    }
  } else {
    Add-Health $Health 'Credentials source' 'OK (Supplied at runtime)'
    Write-Log "Using provided credentials for user: $UserName"
  }

  # Connect
  Write-Log "Attempting PPPoE connect: $PppoeName (SavedCreds=$useSaved)"
  $res = Connect-PPP -PppoeName $PppoeName -UserName $UserName -Password $Password -UseSaved:$useSaved
  $out = ($res.Output -replace '[^\x00-\x7F]', '?')
  Write-Log "rasdial exit=$($res.Code) output:`n$out"

  # Map rasdial errors
  $authOk = $false
  if ($res.Success) { $authOk = $true ; Add-Health $Health 'PPPoE authentication' 'OK' }
  else {
    $reason = switch ($res.Code) {
      691 { '691 bad credentials' }
      651 { '651 modem (device) error' }
      619 { '619 port disconnected' }
      678 { '678 no answer (no PADO)' }
      default { "code $($res.Code)" }
    }
    Add-Health $Health 'PPPoE authentication' ("FAIL ($reason)")
  }

  # Validate PPP interface materialization
  $pppIf = $null
  $pppIP = $null
  $defViaPPP = $false

  if ($authOk) {
    $pppIf = Get-PppInterface -PppoeName $PppoeName
    if ($pppIf -and $pppIf.ConnectionState -eq 'Connected') {
      Add-Health $Health 'PPP interface present' ("OK (IfIndex $($pppIf.InterfaceIndex), '$($pppIf.InterfaceAlias)')")
      $pppIP = Get-PppIPv4 -IfIndex $pppIf.InterfaceIndex
      if ($pppIP) {
        Add-Health $Health 'PPP IPv4 assignment' ("OK ($($pppIP.IPAddress)/$($pppIP.PrefixLength))")
      } else {
        Add-Health $Health 'PPP IPv4 assignment' ("FAIL (no non-APIPA IPv4)")
      }

      $defViaPPP = Test-DefaultRouteVia -IfIndex $pppIf.InterfaceIndex
      if ($defViaPPP) {
        Add-Health $Health 'Default route via PPP' 'OK'
      } else {
        Add-Health $Health 'Default route via PPP' 'WARN (still via other interface)'
      }
    } else {
      Add-Health $Health 'PPP interface present' 'FAIL (not created/connected)'
      Add-Health $Health 'PPP IPv4 assignment' 'FAIL (no interface)'
      Add-Health $Health 'Default route via PPP' 'FAIL (no interface)'
    }
  } else {
    Add-Health $Health 'PPP interface present' 'N/A'
    Add-Health $Health 'PPP IPv4 assignment' 'N/A'
    Add-Health $Health 'Default route via PPP' 'N/A'
  }

  # Public IP classification & gateway reachability
  if ($pppIP) {
    $cls = Get-IpClass -IPv4 $pppIP.IPAddress
    switch ($cls) {
      'PUBLIC' { Add-Health $Health 'Public IP classification' 'OK (Public)' }
      'CGNAT'  { Add-Health $Health 'Public IP classification' 'WARN (CGNAT 100.64/10)' }
      'PRIVATE'{ Add-Health $Health 'Public IP classification' 'WARN (Private RFC1918)' }
      'APIPA'  { Add-Health $Health 'Public IP classification' 'FAIL (APIPA)' }
      default  { Add-Health $Health 'Public IP classification' "WARN ($cls)" }
    }

    # Gateway (peer) reachability: ping default gateway of PPP if present
    $route = Get-NetRoute -InterfaceIndex $pppIf.InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
             Sort-Object -Property RouteMetric |
             Select-Object -First 1
    $gw = if ($route) { $route.NextHop } else { $null }
    if ($gw) {
      $okGw = Test-PingHost -TargetName $gw -Count 2 -TimeoutMs 1000 -Source $pppIP.IPAddress
      if ($okGw) { Add-Health $Health 'Gateway reachability' 'OK' }
      else { Add-Health $Health 'Gateway reachability' 'FAIL (unreachable)' }
    } else {
      Add-Health $Health 'Gateway reachability' 'WARN (no default route record)'
    }

    # External ping via PPP
    $ok11 = Test-PingHost -TargetName '1.1.1.1' -Count 2 -TimeoutMs 1000 -Source $pppIP.IPAddress
    Add-Health $Health 'Ping (1.1.1.1) via PPP' ($ok11 ? 'OK' : 'FAIL')
    
    $ok88 = Test-PingHost -TargetName '8.8.8.8' -Count 2 -TimeoutMs 1000 -Source $pppIP.IPAddress
    Add-Health $Health 'Ping (8.8.8.8) via PPP' ($ok88 ? 'OK' : 'FAIL')

    # MTU probe (rough)
    # We try payload 1472 with DF; if success -> ~1492 MTU on PPP
    try {
      $ping = Test-Connection -TargetName '1.1.1.1' -Count 1 -DontFragment -BufferSize 1472 -TimeoutSeconds 2 -ErrorAction Stop
      Add-Health $Health 'MTU probe (DF)' 'OK (~1492, payload 1472)'
    } catch {
      Add-Health $Health 'MTU probe (DF)' 'WARN (payload 1472 blocked; lower MTU)'
    }

  } else {
    Add-Health $Health 'Public IP classification' 'N/A'
    Add-Health $Health 'Gateway reachability' 'N/A'
    Add-Health $Health 'Ping (1.1.1.1) via PPP' 'N/A'
    Add-Health $Health 'Ping (8.8.8.8) via PPP' 'N/A'
    Add-Health $Health 'MTU probe (DF)' 'N/A'
  }

} catch {
  Write-Err "Fatal error: $($_.Exception.Message)"
} finally {
  if (-not $KeepPPP) { Disconnect-PPP -PppoeName $PppoeName }
  Write-HealthSummary -Health $Health
  Write-Log "Transcript saved to $logPath"
  Stop-AsciiTranscript
}


