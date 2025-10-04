# Invoke-PppoeDiagnostics.ps1 - main entry

#Requires -Version 7.0

param(
  [string]$PppoeName = 'PPPoE',
  [string]$UserName,
  [string]$Password,  # Note: Using string for compatibility with rasdial command
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
        Write-Ok "Found PPPoE connection: $connName (exists but cannot connect - $reason)$adapterContext"
      }
    } catch {
      # Connection doesn't exist or other error
    }
  }
  
  # Set credentials file path regardless of whether connections are found
  $credentialsFile = Join-Path $here "credentials.ps1"
  
  if ($pppoeConnections.Count -gt 0) {
    Write-Ok "Found existing PPPoE connections: $($pppoeConnections -join ', ')"
    $Health = Add-Health $Health 'PPPoE connections configured' "OK ($($pppoeConnections.Count) found: $($pppoeConnections -join ', '))" 2
    Write-Log "Credential sources available: Windows saved, credentials.ps1 file, script parameters"
  } else {
    Write-Warn "No PPPoE connections configured in Windows"
    $Health = Add-Health $Health 'PPPoE connections configured' 'WARN (none found)' 2
    $Health = Add-Health $Health 'Credentials source' 'N/A' 3
    Write-Log "Tested connection names: $($testConnections -join ', ')"
    Write-Log "Available network connections:"
    try {
      $allConnections = Get-NetConnectionProfile | Select-Object -ExpandProperty Name
      Write-Log "$($allConnections -join ', ')"
    } catch {
      Write-Log "Could not retrieve network connections list"
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
  if (Test-LinkUp -AdapterName $nic.Name) {
    $Health = Add-Health $Health 'Ethernet link state' 'OK (Up)' 4
  } else {
    Write-Err "Ethernet link is down (0 bps / Disconnected)"
    $Health = Add-Health $Health 'Ethernet link state' 'FAIL (Down)' 4
    Write-Log "No physical connection, authentication aborted"
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
    # Skip to health summary - no point in attempting connection without link
    $linkDown = $true
  }

  # Only attempt PPPoE connection if Ethernet link is up
  if (-not $linkDown) {
    # Determine the correct connection name to use
    $connectionNameToUse = $PppoeName
    if ($pppoeConnections.Count -gt 0) {
      # If we found existing connections, use the first one (most likely the correct one)
      $connectionNameToUse = $pppoeConnections[0]
      Write-Log "Using detected connection name: '$connectionNameToUse'"
    }
    
    # Clean previous PPP state
    Disconnect-PPP -PppoeName $connectionNameToUse

    # Connect with fallback credential attempts
    Write-Log "Starting PPPoE connection attempts with fallback credential sources..."
    $res = Connect-PPPWithFallback -PppoeName $connectionNameToUse -UserName $UserName -Password $Password -CredentialsFile $credentialsFile -WriteLog ${function:Write-Log} -AddHealth ${function:Add-Health}
    $out = ($res.Output -replace '[^\x00-\x7F]', '?')
    Write-Log "Final connection result: Method=$($res.Method), Success=$($res.Success), ExitCode=$($res.Code)"
    Write-Log "rasdial output:`n$out"

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
        678 { '678 no answer (no PADO)' }
        default { "code $($res.Code)" }
      }
      $Health = Add-Health $Health 'PPPoE authentication' ("FAIL ($reason)") 12
      $Health = Add-Health $Health 'Credentials source' 'FAIL (All credential methods failed)' 11
    }
  }

  # Validate PPP interface materialization (only if link is up and we attempted connection)
  $pppIf = $null
  $pppIP = $null
  $defViaPPP = $false

  if (-not $linkDown -and $authOk) {
    try {
      Write-Log "Looking for PPP interface after successful connection..."
      $pppIf = Get-PppInterface -PppoeName $connectionNameToUse
      Write-Log "PPP interface search result: $($null -ne $pppIf)"
      
      if ($pppIf -and $pppIf.ConnectionState -eq 'Connected') {
        $Health = Add-Health $Health 'PPP interface present' ("OK (IfIndex $($pppIf.InterfaceIndex), '$($pppIf.InterfaceAlias)')") 13
        Write-Log "Found connected PPP interface: $($pppIf.InterfaceAlias) (Index: $($pppIf.InterfaceIndex))"
        
        $pppIP = Get-PppIPv4 -IfIndex $pppIf.InterfaceIndex
        if ($pppIP) {
          $Health = Add-Health $Health 'PPP IPv4 assignment' ("OK ($($pppIP.IPAddress)/$($pppIP.PrefixLength))") 14
          Write-Log "PPP IPv4 address: $($pppIP.IPAddress)/$($pppIP.PrefixLength)"
        } else {
          $Health = Add-Health $Health 'PPP IPv4 assignment' ("FAIL (no non-APIPA IPv4)") 14
          Write-Log "No valid IPv4 address found on PPP interface"
        }

        $defViaPPP = Test-DefaultRouteVia -IfIndex $pppIf.InterfaceIndex
        if ($defViaPPP) {
          $Health = Add-Health $Health 'Default route via PPP' 'OK' 15
          Write-Log "Default route is via PPP interface"
        } else {
          $Health = Add-Health $Health 'Default route via PPP' 'WARN (still via other interface)' 15
          Write-Log "Default route is NOT via PPP interface"
        }
      } else {
        Write-Log "No connected PPP interface found"
        $Health = Add-Health $Health 'PPP interface present' 'FAIL (not created/connected)' 13
        $Health = Add-Health $Health 'PPP IPv4 assignment' 'FAIL (no interface)' 14
        $Health = Add-Health $Health 'Default route via PPP' 'FAIL (no interface)' 15
      }
    } catch {
      Write-Log "Error detecting PPP interface: $($_.Exception.Message)"
      $Health = Add-Health $Health 'PPP interface present' 'FAIL (error detecting interface)' 13
      $Health = Add-Health $Health 'PPP IPv4 assignment' 'FAIL (error detecting interface)' 14
      $Health = Add-Health $Health 'Default route via PPP' 'FAIL (error detecting interface)' 15
    }
  } else {
    if (-not $linkDown) {
      # Link is up but authentication failed
      $Health = Add-Health $Health 'PPP interface present' 'N/A' 13
      $Health = Add-Health $Health 'PPP IPv4 assignment' 'N/A' 14
      $Health = Add-Health $Health 'Default route via PPP' 'N/A' 15
    }
  }

  # Public IP classification & gateway reachability (only if we have a PPP interface)
  if (-not $linkDown -and $pppIP) {
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
      Test-Connection -TargetName '1.1.1.1' -Count 1 -DontFragment -BufferSize 1472 -TimeoutSeconds 2 -ErrorAction Stop | Out-Null
      $Health = Add-Health $Health 'MTU probe (DF)' 'OK (~1492, payload 1472)' 20
    } catch {
      $Health = Add-Health $Health 'MTU probe (DF)' 'WARN (payload 1472 blocked; lower MTU)' 20
    }

    # Traceroute diagnostics (may take up to ~60s each)
    Write-Log "Starting traceroute to 1.1.1.1 (may take up to 60s)..."
    try {
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = "cmd.exe"
      $psi.Arguments = "/c tracert -d -4 -w 1000 -h 20 1.1.1.1"
      $psi.RedirectStandardOutput = $true
      $psi.UseShellExecute = $false
      $proc = [System.Diagnostics.Process]::Start($psi)
      while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        Write-Log "[tracert 1.1.1.1] $line"
      }
      $proc.WaitForExit()
      $Health = Add-Health $Health 'Traceroute (1.1.1.1)' 'DONE' 21
    } catch {
      Write-Log "Traceroute 1.1.1.1 error: $($_.Exception.Message)"
      $Health = Add-Health $Health 'Traceroute (1.1.1.1)' 'ERROR' 21
    }

    Write-Log "Starting traceroute to 8.8.8.8 (may take up to 60s)..."
    try {
      $psi2 = New-Object System.Diagnostics.ProcessStartInfo
      $psi2.FileName = "cmd.exe"
      $psi2.Arguments = "/c tracert -d -4 -w 1000 -h 20 8.8.8.8"
      $psi2.RedirectStandardOutput = $true
      $psi2.UseShellExecute = $false
      $proc2 = [System.Diagnostics.Process]::Start($psi2)
      while (-not $proc2.StandardOutput.EndOfStream) {
        $line2 = $proc2.StandardOutput.ReadLine()
        Write-Log "[tracert 8.8.8.8] $line2"
      }
      $proc2.WaitForExit()
      $Health = Add-Health $Health 'Traceroute (8.8.8.8)' 'DONE' 22
    } catch {
      Write-Log "Traceroute 8.8.8.8 error: $($_.Exception.Message)"
      $Health = Add-Health $Health 'Traceroute (8.8.8.8)' 'ERROR' 22
    }

  } else {
    if (-not $linkDown) {
      # Link is up but no PPP interface/IP
      $Health = Add-Health $Health 'Public IP classification' 'N/A' 16
      $Health = Add-Health $Health 'Gateway reachability' 'N/A' 17
      $Health = Add-Health $Health 'Ping (1.1.1.1) via PPP' 'N/A' 18
      $Health = Add-Health $Health 'Ping (8.8.8.8) via PPP' 'N/A' 19
      $Health = Add-Health $Health 'MTU probe (DF)' 'N/A' 20
      $Health = Add-Health $Health 'Traceroute (1.1.1.1)' 'N/A' 21
      $Health = Add-Health $Health 'Traceroute (8.8.8.8)' 'N/A' 22
    }
  }

} catch {
  Write-Err "Fatal error: $($_.Exception.Message)"
} finally {
  if (-not $KeepPPP) { Disconnect-PPP -PppoeName $PppoeName }
  Write-Log ""
  Write-HealthSummary -Health $Health
  Write-Log "Transcript saved to $logPath"
  Stop-AsciiTranscript
}


