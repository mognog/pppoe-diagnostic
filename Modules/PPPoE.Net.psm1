
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

function Select-NetworkAdapter {
  param([scriptblock]$WriteLog)
  
  $adapters = Get-CandidateEthernetAdapters
  if ($adapters.Count -eq 0) {
    & $WriteLog "No Ethernet adapters found"
    return $null
  }
  
  if ($adapters.Count -eq 1) {
    $adapter = $adapters[0]
    & $WriteLog "Only one Ethernet adapter found: $($adapter.Name) - $($adapter.InterfaceDescription)"
    return $adapter
  }
  
  # Multiple adapters - show selection menu
  & $WriteLog ""
  & $WriteLog "Multiple Ethernet adapters detected. Please select one:"
  & $WriteLog ""
  
  for ($i = 0; $i -lt $adapters.Count; $i++) {
    $adapter = $adapters[$i]
    $status = if ($adapter.Status -eq 'Up') { "UP" } else { "DOWN" }
    $speed = if ($adapter.LinkSpeed -gt 0) { "$($adapter.LinkSpeed) bps" } else { "No link" }
    & $WriteLog "[$($i + 1)] $($adapter.Name) - $($adapter.InterfaceDescription) ($status, $speed)"
  }
  
  # Get recommended adapter for default
  $recommended = Get-RecommendedAdapter
  $defaultChoice = if ($recommended) {
    $index = [array]::IndexOf($adapters, $recommended) + 1
    if ($index -gt 0) { $index } else { 1 }
  } else { 1 }
  
  & $WriteLog ""
  & $WriteLog "Enter choice (1-$($adapters.Count)) or press Enter for recommended [$defaultChoice]: "
  
  do {
    $choice = Read-Host
    if ([string]::IsNullOrEmpty($choice)) {
      $choice = $defaultChoice
    }
    
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $adapters.Count) {
      $selectedAdapter = $adapters[[int]$choice - 1]
      & $WriteLog "Selected: $($selectedAdapter.Name) - $($selectedAdapter.InterfaceDescription)"
      return $selectedAdapter
    } else {
      & $WriteLog "Invalid choice. Please enter a number between 1 and $($adapters.Count): "
    }
  } while ($true)
}

function Test-LinkUp {
  param([string]$AdapterName)
  $nic = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
  if ($nic.Status -ne 'Up' -or $nic.LinkSpeed -eq 0) {
    return $false
  }
  return $true
}


function Disconnect-PPP {
  param([string]$PppoeName)
  try { rasdial "$PppoeName" /disconnect | Out-Null } catch {}
  Start-Sleep -Milliseconds 800
}

function Disconnect-AllPPPoE {
  # Disconnect all existing PPPoE connections to start clean
  $commonNames = @('Rise PPPoE', 'PPPoE', 'Broadband Connection', 'Ransomeware_6G 2', 'RAS')
  
  foreach ($name in $commonNames) {
    try {
      rasdial "$name" /disconnect 2>$null | Out-Null
    } catch {
      # Ignore errors - connection might not exist
    }
  }
  
  # Also try to disconnect any connections that might be active
  try {
    $activeConnections = Get-NetConnectionProfile | Where-Object { $_.Name -match 'PPPoE|RAS|Broadband' }
    foreach ($conn in $activeConnections) {
      try {
        rasdial "$($conn.Name)" /disconnect 2>$null | Out-Null
      } catch {
        # Ignore errors
      }
    }
  } catch {
    # Ignore errors
  }
  
  Start-Sleep -Milliseconds 1000
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

function Connect-PPPWithFallback {
  param(
    [string]$PppoeName,
    [string]$UserName,
    [string]$Password,
    [string]$CredentialsFile,
    [scriptblock]$WriteLog,
    [scriptblock]$AddHealth
  )
  
  # Returns hashtable: @{ Success=$bool; Code=$int; Output=$string; Method=$string; CredentialSource=$string }
  
  # Attempt 1: Try Windows saved credentials first (most common scenario)
  & $WriteLog "Attempt 1: Trying Windows saved credentials for connection '$PppoeName'"
  $result = Connect-PPP -PppoeName $PppoeName -UseSaved
  if ($result.Success) {
    & $WriteLog "SUCCESS: Connected using Windows saved credentials"
    try {
      # Note: AddHealth function expects $Health as first parameter, but we can't access it here
      # So we'll just log the success and let the main script handle health updates
      & $WriteLog "SUCCESS: Windows saved credentials will be recorded in health summary"
    } catch {
      & $WriteLog "WARN: Could not log health status: $($_.Exception.Message)"
    }
    return @{ 
      Success = $true; 
      Code = $result.Code; 
      Output = $result.Output; 
      Method = 'Windows Saved'; 
      CredentialSource = 'Windows saved credentials' 
    }
  }
  & $WriteLog "FAILED: Windows saved credentials failed (exit code: $($result.Code))"
  
  # Attempt 2: Try external credentials file
  if ($CredentialsFile -and (Test-Path $CredentialsFile)) {
    & $WriteLog "Attempt 2: Loading credentials from file '$CredentialsFile'"
    try {
      # Clear any existing credential variables to avoid conflicts
      $PPPoE_Username = $null
      $PPPoE_Password = $null
      $PPPoE_ConnectionName = $null
      
      # Dot-source the credentials file
      . $CredentialsFile
      
      # Check if variables were loaded successfully
      if ((Get-Variable -Name 'PPPoE_Username' -ErrorAction SilentlyContinue) -and 
          (Get-Variable -Name 'PPPoE_Password' -ErrorAction SilentlyContinue) -and
          $PPPoE_Username -and $PPPoE_Password -and 
          $PPPoE_Username.Trim() -ne '' -and $PPPoE_Password.Trim() -ne '') {
        
        $fileUserName = $PPPoE_Username
        $filePassword = $PPPoE_Password
        $fileConnectionName = if ((Get-Variable -Name 'PPPoE_ConnectionName' -ErrorAction SilentlyContinue) -and 
                                 $PPPoE_ConnectionName -and $PPPoE_ConnectionName.Trim() -ne '') { 
                                 $PPPoE_ConnectionName 
                               } else { 
                                 $PppoeName 
                               }
        
        & $WriteLog "Attempt 2: Trying credentials from file for user '$fileUserName' on connection '$fileConnectionName'"
        $result = Connect-PPP -PppoeName $fileConnectionName -UserName $fileUserName -Password $filePassword
        if ($result.Success) {
          & $WriteLog "SUCCESS: Connected using credentials from file"
        try {
          # Note: AddHealth function expects $Health as first parameter, but we can't access it here
          # So we'll just log the success and let the main script handle health updates
          & $WriteLog "SUCCESS: Credentials from file will be recorded in health summary"
        } catch {
          & $WriteLog "WARN: Could not log health status: $($_.Exception.Message)"
        }
          return @{ 
            Success = $true; 
            Code = $result.Code; 
            Output = $result.Output; 
            Method = 'File'; 
            CredentialSource = "credentials.ps1 file for user: $fileUserName" 
          }
        }
        & $WriteLog "FAILED: Credentials from file failed (exit code: $($result.Code))"
      } else {
        & $WriteLog "SKIP: Credentials file exists but values are empty or invalid"
      }
    } catch {
      & $WriteLog "SKIP: Failed to load credentials from file: $($_.Exception.Message)"
    }
  } else {
    & $WriteLog "SKIP: No credentials file found at '$CredentialsFile'"
  }
  
  # Attempt 3: Try parameters passed to script
  if ($UserName -and $Password -and $UserName.Trim() -ne '' -and $Password.Trim() -ne '') {
    & $WriteLog "Attempt 3: Trying credentials from script parameters for user '$UserName'"
    $result = Connect-PPP -PppoeName $PppoeName -UserName $UserName -Password $Password
    if ($result.Success) {
      & $WriteLog "SUCCESS: Connected using script parameters"
      try {
        # Note: AddHealth function expects $Health as first parameter, but we can't access it here
        # So we'll just log the success and let the main script handle health updates
        & $WriteLog "SUCCESS: Script parameters will be recorded in health summary"
      } catch {
        & $WriteLog "WARN: Could not log health status: $($_.Exception.Message)"
      }
      return @{ 
        Success = $true; 
        Code = $result.Code; 
        Output = $result.Output; 
        Method = 'Parameters'; 
        CredentialSource = "script parameters for user: $UserName" 
      }
    }
    & $WriteLog "FAILED: Script parameters failed (exit code: $($result.Code))"
  } else {
    & $WriteLog "SKIP: No credentials provided as script parameters"
  }
  
  # All attempts failed
  & $WriteLog "FAILED: All credential attempts failed"
  
  # Use the last result if available and it's a hashtable, otherwise create a default failure result
  $lastCode = -1
  $lastOutput = "No connection attempts succeeded"
  
  if ($result -and $result -is [hashtable] -and $result.ContainsKey('Code')) {
    $lastCode = $result.Code
  }
  if ($result -and $result -is [hashtable] -and $result.ContainsKey('Output')) {
    $lastOutput = $result.Output
  }
  
  return @{ 
    Success = $false; 
    Code = $lastCode; 
    Output = $lastOutput; 
    Method = 'None'; 
    CredentialSource = 'No working credentials found' 
  }
}

function Get-PppInterface {
  param([string]$PppoeName)

  try {
    # Look for PPP interfaces by checking for PPP in the interface alias or description
    $if = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
      $_.InterfaceAlias -match 'PPP' -or $_.InterfaceAlias -match [regex]::Escape($PppoeName)
    }
    
    # If we found interfaces, return the first one
    if ($if -and $if.Count -gt 0) { 
      return $if[0] 
    }
    
    # If no specific match, try to find any connected interface that might be the PPP connection
    $allIfs = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
      $_.ConnectionState -eq 'Connected' -and $_.InterfaceAlias -match 'PPP'
    }
    
    if ($allIfs -and $allIfs.Count -gt 0) {
      return $allIfs[0]
    }
    
    return $null
  } catch {
    return $null
  }
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
