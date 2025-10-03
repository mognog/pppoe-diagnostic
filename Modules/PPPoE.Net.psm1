
# PPPoE.Net.psm1 - NIC and PPP operations

Set-StrictMode -Version Latest

function Get-CandidateEthernetAdapters {
  $eth = Get-NetAdapter -Physical | Where-Object { $_.MediaType -match '802\.3' -or $_.Name -match 'Ethernet' }
  $eth | Sort-Object -Property Status -Descending
}

function Get-RecommendedAdapter {
  $list = Get-CandidateEthernetAdapters
  # Prefer 'USB', 'Realtek', 'Sabrent', '5GbE' if present
  $pref = $list | Where-Object { $_.InterfaceDescription -match 'Realtek|Sabrent|USB|5G' }
  if ($pref -and $pref.Count -gt 0) { return $pref[0] }
  if ($list -and $list.Count -gt 0) { return $list[0] }
  return $null
}

function Ensure-LinkUp {
  param([string]$AdapterName)
  $nic = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
  if ($nic.Status -ne 'Up' -or $nic.LinkSpeed -eq 0) {
    return $false
  }
  return $true
}

function Get-SavedPppoeUsername {
  param([string]$PppoeName)
  
  try {
    # Method 1: Check RAS Phonebook registry (most common for PPPoE)
    $regPaths = @(
      "HKCU:\Software\Microsoft\RAS Phonebook",
      "HKLM:\SOFTWARE\Microsoft\RAS Phonebook",
      "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections",
      "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections"
    )
    
    foreach ($regPath in $regPaths) {
      if (Test-Path $regPath) {
        $entries = Get-ChildItem $regPath -ErrorAction SilentlyContinue
        foreach ($entry in $entries) {
          # Check if entry name matches (case-insensitive)
          if ($entry.Name -match [regex]::Escape($PppoeName) -or $entry.Name -eq $PppoeName) {
            # Try different property names that might contain the username
            $usernameProps = @("Username", "User", "UserName", "User Name", "szUserName")
            foreach ($prop in $usernameProps) {
              $username = Get-ItemProperty -Path $entry.PSPath -Name $prop -ErrorAction SilentlyContinue
              if ($username -and $username.$prop) {
                return $username.$prop
              }
            }
          }
        }
      }
    }
  } catch {
    # Registry method failed
  }
  
  try {
    # Method 2: Check Windows Credential Manager
    $credPaths = @(
      "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains",
      "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections"
    )
    
    foreach ($credPath in $credPaths) {
      if (Test-Path $credPath) {
        $entries = Get-ChildItem $credPath -ErrorAction SilentlyContinue
        foreach ($entry in $entries) {
          if ($entry.Name -match [regex]::Escape($PppoeName) -or $entry.Name -eq $PppoeName) {
            $username = Get-ItemProperty -Path $entry.PSPath -Name "Username" -ErrorAction SilentlyContinue
            if ($username -and $username.Username) {
              return $username.Username
            }
          }
        }
      }
    }
  } catch {
    # Credential manager method failed
  }
  
  try {
    # Method 3: Check for connection in Windows network connections
    $connections = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    if ($connections) {
      $matchingConn = $connections | Where-Object { $_.Name -eq $PppoeName }
      if ($matchingConn) {
        # Connection exists, try to get more details
        try {
          # Try to get connection details from registry
          $connRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections"
          if (Test-Path $connRegPath) {
            $connEntries = Get-ChildItem $connRegPath -ErrorAction SilentlyContinue
            foreach ($entry in $connEntries) {
              $entryProps = Get-ItemProperty -Path $entry.PSPath -ErrorAction SilentlyContinue
              if ($entryProps -and $entryProps.PSObject.Properties.Name -contains "DefaultConnectionSettings") {
                # This might contain connection details
                $settings = $entryProps.DefaultConnectionSettings
                if ($settings -and $settings.Length -gt 0) {
                  # Try to extract username from binary data (this is complex)
                  # For now, just indicate that saved credentials exist
                  return "[Saved credentials found]"
                }
              }
            }
          }
        } catch {
          # Could not parse connection details
        }
        return "[Saved credentials found]"
      }
    }
  } catch {
    # Network connections method failed
  }
  
  try {
    # Method 4: Use netsh to validate connection exists
    $netshOutput = & netsh interface show interface 2>$null
    if ($netshOutput) {
      $lines = $netshOutput -split "`n"
      foreach ($line in $lines) {
        if ($line -match [regex]::Escape($PppoeName)) {
          # Connection exists but we can't get username from netsh
          return "[Saved credentials found]"
        }
      }
    }
  } catch {
    # netsh method failed
  }
  
  return $null
}

function Disconnect-PPP {
  param([string]$PppoeName)
  try { rasdial "$PppoeName" /disconnect | Out-Null } catch {}
  Start-Sleep -Milliseconds 800
}

function Connect-PPP {
  param(
    [string]$PppoeName,
    [string]$UserName,
    [string]$Password,
    [switch]$UseSaved
  )
  # Returns hashtable: @{ Success=$bool; Code=$int; Output=$string }
  $cmd = if ($UseSaved) { "rasdial `"$PppoeName`"" } else { "rasdial `"$PppoeName`" `"$UserName`" `"$Password`"" }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "cmd.exe"
  $psi.Arguments = "/c $cmd"
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  $code = $p.ExitCode

  # Success heuristic: ExitCode==0 AND we can find "Command completed successfully"
  $ok = ($code -eq 0 -and $out -match '(?i)completed successfully')
  return @{ Success = [bool]$ok; Code = [int]$code; Output = $out }
}

function Get-PppInterface {
  param([string]$PppoeName)

  $if = Get-NetIPInterface -AddressFamily IPv4 | Where-Object {
    $_.InterfaceDescription -match 'PPP' -or $_.InterfaceAlias -match [regex]::Escape($PppoeName)
  }
  if ($if -and $if.Count -gt 0) { return $if[0] } else { return $null }
}

function Get-PppIPv4 {
  param([int]$IfIndex)
  if (-not $IfIndex) { return $null }
  $ip = Get-NetIPAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1
  return $ip
}

function Test-DefaultRouteVia {
  param([int]$IfIndex)
  $def = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
         Sort-Object -Property RouteMetric |
         Select-Object -First 1
  if (-not $def) { return $false }
  return ($def.InterfaceIndex -eq $IfIndex)
}

Export-ModuleMember -Function *
