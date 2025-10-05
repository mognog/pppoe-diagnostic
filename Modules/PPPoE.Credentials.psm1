# PPPoE.Credentials.psm1 - Credential management functions

Set-StrictMode -Version 3.0

function Get-CredentialsFromFile {
  param(
    [string]$CredentialsFilePath,
    [scriptblock]$WriteLog
  )
  
  if (-not (Test-Path $CredentialsFilePath)) {
    & $WriteLog "Credentials file not found: $CredentialsFilePath"
    return $null
  }
  
  try {
    # Dot-source the credentials file to get the variables
    $credentialVars = @{}
    $content = Get-Content $CredentialsFilePath -Raw
    
    # Extract username and password variables using regex
    # Support both $username/$password and $PPPoE_Username/$PPPoE_Password formats
    if ($content -match '\$PPPoE_Username\s*=\s*["'']([^"'']+)["'']') {
      $credentialVars.Username = $matches[1]
    } elseif ($content -match '\$username\s*=\s*["'']([^"'']+)["'']') {
      $credentialVars.Username = $matches[1]
    }
    if ($content -match '\$PPPoE_Password\s*=\s*["'']([^"'']+)["'']') {
      $credentialVars.Password = $matches[1]
    } elseif ($content -match '\$password\s*=\s*["'']([^"'']+)["'']') {
      $credentialVars.Password = $matches[1]
    }
    
    if ($credentialVars.Username -and $credentialVars.Password) {
      & $WriteLog "Successfully loaded credentials from file for user: $($credentialVars.Username)"
      return $credentialVars
    } else {
      & $WriteLog "Could not extract valid credentials from file"
      return $null
    }
  } catch {
    & $WriteLog "Error reading credentials file: $($_.Exception.Message)"
    return $null
  }
}

function Test-CredentialsProvided {
  param(
    [string]$UserName,
    [string]$Password
  )
  
  return (-not [string]::IsNullOrWhiteSpace($UserName) -and -not [string]::IsNullOrWhiteSpace($Password))
}

function Get-CredentialSource {
  param(
    [string]$UserName,
    [string]$Password,
    [string]$CredentialsFilePath,
    [scriptblock]$WriteLog
  )
  
  # Check if credentials are provided via parameters
  if (Test-CredentialsProvided -UserName $UserName -Password $Password) {
    & $WriteLog "Using credentials from script parameters for user: $UserName"
    return @{
      Source = 'Parameters'
      Username = $UserName
      Password = $Password
      Description = "script parameters for user: $UserName"
    }
  }
  
  # Check if credentials file exists and has valid credentials
  $fileCreds = Get-CredentialsFromFile -CredentialsFilePath $CredentialsFilePath -WriteLog $WriteLog
  if ($fileCreds) {
    return @{
      Source = 'File'
      Username = $fileCreds.Username
      Password = $fileCreds.Password
      Description = "credentials.ps1 file for user: $($fileCreds.Username)"
    }
  }
  
  # Fall back to Windows saved credentials
  & $WriteLog "No credentials provided via parameters or file, will attempt Windows saved credentials"
  return @{
    Source = 'Windows Saved'
    Username = $null
    Password = $null
    Description = 'Windows saved credentials'
  }
}

function Test-CredentialsFormat {
  param(
    [string]$UserName,
    [string]$Password
  )
  
  $issues = @()
  
  if ([string]::IsNullOrWhiteSpace($UserName)) {
    $issues += "Username is empty or whitespace only"
  }
  
  if ([string]::IsNullOrWhiteSpace($Password)) {
    $issues += "Password is empty or whitespace only"
  }
  
  if ($UserName -and $UserName.Length -lt 3) {
    $issues += "Username is too short (minimum 3 characters)"
  }
  
  if ($Password -and $Password.Length -lt 6) {
    $issues += "Password is too short (minimum 6 characters)"
  }
  
  return @{
    IsValid = ($issues.Count -eq 0)
    Issues = $issues
  }
}

function Show-CredentialSources {
  param(
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Available credential sources:"
  & $WriteLog "  1. Script parameters (-UserName and -Password)"
  & $WriteLog "  2. credentials.ps1 file in script directory"
  & $WriteLog "  3. Windows saved credentials (if connection exists)"
  & $WriteLog ""
  & $WriteLog "Priority order: Script parameters > credentials.ps1 file > Windows saved"
}

Export-ModuleMember -Function *
