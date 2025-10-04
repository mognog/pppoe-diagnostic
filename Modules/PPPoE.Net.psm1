
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
    & $AddHealth 'Credentials source' 'OK (Using Windows saved credentials)' 3
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
    try {
      & $WriteLog "Attempt 2: Loading credentials from file '$CredentialsFile'"
      . $CredentialsFile
      if ($PPPoE_Username -and $PPPoE_Password -and 
          $PPPoE_Username.Trim() -ne '' -and $PPPoE_Password.Trim() -ne '') {
        $fileUserName = $PPPoE_Username
        $filePassword = $PPPoE_Password
        $fileConnectionName = if ($PPPoE_ConnectionName -and $PPPoE_ConnectionName.Trim() -ne '') { $PPPoE_ConnectionName } else { $PppoeName }
        
        & $WriteLog "Attempt 2: Trying credentials from file for user '$fileUserName'"
        $result = Connect-PPP -PppoeName $fileConnectionName -UserName $fileUserName -Password $filePassword
        if ($result.Success) {
          & $WriteLog "SUCCESS: Connected using credentials from file"
          & $AddHealth 'Credentials source' "OK (Using credentials from file for: $fileUserName)" 3
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
        & $WriteLog "SKIP: Credentials file exists but values are empty"
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
      & $AddHealth 'Credentials source' "OK (Using script parameters for: $UserName)" 3
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
  & $AddHealth 'Credentials source' 'FAIL (All credential methods failed)' 3
  return @{ 
    Success = $false; 
    Code = $result.Code; 
    Output = $result.Output; 
    Method = 'None'; 
    CredentialSource = 'No working credentials found' 
  }
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
