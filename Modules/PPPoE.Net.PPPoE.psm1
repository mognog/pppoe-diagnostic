# PPPoE.Net.PPPoE.psm1 - PPPoE connection management functions

Set-StrictMode -Version 3.0

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

function Get-DefaultRouteOwner {
  param([scriptblock]$WriteLog)
  
  try {
    $def = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
           Sort-Object -Property RouteMetric |
           Select-Object -First 1
    
    if (-not $def) {
      & $WriteLog "No default route found"
      return $null
    }
    
    $interface = Get-NetAdapter -InterfaceIndex $def.InterfaceIndex -ErrorAction SilentlyContinue
    if ($interface) {
      $ownerInfo = "$($interface.Name) ($($interface.InterfaceDescription)) - Metric: $($def.RouteMetric)"
      & $WriteLog "Current default route owner: $ownerInfo"
      return @{
        InterfaceIndex = $def.InterfaceIndex
        InterfaceName = $interface.Name
        InterfaceDescription = $interface.InterfaceDescription
        RouteMetric = $def.RouteMetric
        NextHop = $def.NextHop
      }
    } else {
      & $WriteLog "Default route found but interface details unavailable (Index: $($def.InterfaceIndex))"
      return @{
        InterfaceIndex = $def.InterfaceIndex
        InterfaceName = "Unknown"
        InterfaceDescription = "Interface not found"
        RouteMetric = $def.RouteMetric
        NextHop = $def.NextHop
      }
    }
  } catch {
    & $WriteLog "Error getting default route owner: $($_.Exception.Message)"
    return $null
  }
}

function Set-RouteMetrics {
  param([int]$PppInterfaceIndex, [scriptblock]$WriteLog)
  
  try {
    & $WriteLog "Adjusting route metrics to prefer PPP interface..."
    
    # Get the PPP interface
    $pppInterface = Get-NetAdapter -InterfaceIndex $PppInterfaceIndex -ErrorAction SilentlyContinue
    if (-not $pppInterface) {
      & $WriteLog "Could not find PPP interface with index $PppInterfaceIndex"
      return $false
    }
    
    # Set PPP interface metric to 1 (highest priority)
    try {
      Set-NetIPInterface -InterfaceIndex $PppInterfaceIndex -InterfaceMetric 1 -ErrorAction Stop
      & $WriteLog "Set PPP interface metric to 1 (highest priority)"
    } catch {
      & $WriteLog "Failed to set PPP interface metric: $($_.Exception.Message)"
    }
    
    # Get all other network adapters and increase their metrics
    $otherAdapters = Get-NetAdapter -Physical | Where-Object { $_.InterfaceIndex -ne $PppInterfaceIndex }
    
    foreach ($adapter in $otherAdapters) {
      try {
        $currentMetric = (Get-NetIPInterface -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceMetric
        if ($currentMetric -and $currentMetric -lt 10) {
          $newMetric = $currentMetric + 10
          Set-NetIPInterface -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -InterfaceMetric $newMetric -ErrorAction Stop
          & $WriteLog "Increased metric for $($adapter.Name) from $currentMetric to $newMetric"
        }
      } catch {
        & $WriteLog "Could not adjust metric for $($adapter.Name): $($_.Exception.Message)"
      }
    }
    
    # Wait a moment for routes to update
    Start-Sleep -Seconds 2
    
    # Verify the change
    $newDefaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object -Property RouteMetric | Select-Object -First 1
    if ($newDefaultRoute -and $newDefaultRoute.InterfaceIndex -eq $PppInterfaceIndex) {
      & $WriteLog "SUCCESS: Default route now uses PPP interface"
      return $true
    } else {
      & $WriteLog "WARNING: Default route still not using PPP interface after metric adjustment"
      return $false
    }
    
  } catch {
    & $WriteLog "Error adjusting route metrics: $($_.Exception.Message)"
    return $false
  }
}

function Get-PPPoESessionInfo {
  param([string]$PppoeName, [scriptblock]$WriteLog)
  
  try {
    & $WriteLog "Checking PPPoE session information for: $PppoeName"
    
    # Check Windows Event Log for PPPoE session events
    $sessionEvents = Get-WinEvent -FilterHashtable @{
      LogName = 'System'
      ID = 20227
      StartTime = (Get-Date).AddHours(-1)
    } -ErrorAction SilentlyContinue | Where-Object {
      $_.Message -match [regex]::Escape($PppoeName)
    }
    
    if ($sessionEvents) {
      & $WriteLog "Found $($sessionEvents.Count) recent PPPoE session events:"
      foreach ($sessionEvent in $sessionEvents | Select-Object -First 5) {
        $time = $sessionEvent.TimeCreated.ToString("HH:mm:ss")
        $message = $sessionEvent.Message -replace '\s+', ' '
        & $WriteLog "  [$time] $message"
      }
    } else {
      & $WriteLog "No recent PPPoE session events found in Event Log"
    }
    
    # Check for PPPoE service status
    $pppoeService = Get-Service -Name "RasMan" -ErrorAction SilentlyContinue
    if ($pppoeService) {
      & $WriteLog "PPPoE Service (RasMan): $($pppoeService.Status)"
    }
    
    return @{
      SessionEvents = $sessionEvents
      ServiceStatus = $pppoeService.Status
    }
    
  } catch {
    & $WriteLog "Error checking PPPoE session info: $($_.Exception.Message)"
    return $null
  }
}

Export-ModuleMember -Function *
