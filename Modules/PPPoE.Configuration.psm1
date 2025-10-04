# PPPoE.Configuration.psm1 - Centralized configuration management

Set-StrictMode -Version 3.0

function ConvertTo-Hashtable {
  param([object]$InputObject)
  
  if ($InputObject -is [hashtable]) {
    return $InputObject
  }
  
  if ($InputObject -is [PSCustomObject]) {
    $hashtable = @{}
    $InputObject.PSObject.Properties | ForEach-Object {
      if ($_.Value -is [PSCustomObject]) {
        $hashtable[$_.Name] = ConvertTo-Hashtable -InputObject $_.Value
      } else {
        $hashtable[$_.Name] = $_.Value
      }
    }
    return $hashtable
  }
  
  return $InputObject
}

function Get-ProjectConfiguration {
  param(
    [string]$ConfigPath = $null
  )
  
  # Default configuration
  $defaultConfig = @{
    # Logging configuration
    Logging = @{
      DefaultLogLevel = 'INFO'
      EnableTranscript = $true
      LogDirectory = 'logs'
      LogFilePrefix = 'pppoe_transcript'
      MaxLogFiles = 10
    }
    
    # Network configuration
    Network = @{
      DefaultPPPoEName = 'PPPoE'
      TestConnections = @('Rise PPPoE', 'PPPoE', 'Broadband Connection', 'Ransomeware_6G 2')
      DefaultTargets = @('1.1.1.1', '8.8.8.8')
      PingTimeout = 1000
      PingCount = 2
      TracerouteTimeout = 1000
      TracerouteMaxHops = 20
    }
    
    # Health check configuration
    HealthChecks = @{
      EnableAdvancedTests = $false
      EnableTraceroute = $false
      EnableStabilityTest = $false
      PacketLossThreshold = 2
      JitterThreshold = 50
      RouteStabilityThreshold = 80
    }
    
    # Credential configuration
    Credentials = @{
      CredentialsFile = 'credentials.ps1'
      MinUsernameLength = 3
      MinPasswordLength = 6
      EnableCredentialValidation = $true
    }
    
    # WiFi management
    WiFi = @{
      AutoDisableWiFi = $true
      ReEnableWiFi = $true
      WiFiAdapterPatterns = @('Wi-Fi', 'Wireless', 'WLAN')
    }
  }
  
  # If no config path provided, return default configuration
  if (-not $ConfigPath) {
    return $defaultConfig
  }
  
  # Try to load configuration from file
  if (Test-Path $ConfigPath) {
    try {
      $fileConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
      # Merge with defaults (file config takes precedence)
      return Merge-Configuration -Default $defaultConfig -Override $fileConfig
    } catch {
      Write-Warning "Failed to load configuration from $ConfigPath`: $($_.Exception.Message)"
      Write-Warning "Using default configuration"
      return $defaultConfig
    }
  } else {
    Write-Warning "Configuration file not found: $ConfigPath"
    Write-Warning "Using default configuration"
    return $defaultConfig
  }
}

function Set-LoggingConfiguration {
  param(
    [hashtable]$Config,
    [string]$LogDirectory = $null,
    [string]$LogLevel = $null,
    [int]$MaxLogFiles = $null
  )
  
  if ($LogDirectory) {
    $Config.Logging.LogDirectory = $LogDirectory
  }
  
  if ($LogLevel) {
    $Config.Logging.DefaultLogLevel = $LogLevel
  }
  
  if ($MaxLogFiles) {
    $Config.Logging.MaxLogFiles = $MaxLogFiles
  }
  
  return $Config
}

function Get-DefaultParameters {
  param(
    [hashtable]$Config
  )
  
  return @{
    PppoeName = $Config.Network.DefaultPPPoEName
    TargetAdapter = $null
    FullLog = $Config.HealthChecks.EnableAdvancedTests
    SkipWifiToggle = -not $Config.WiFi.AutoDisableWiFi
    KeepPPP = $false
  }
}

function Test-Configuration {
  param(
    [hashtable]$Config
  )
  
  $issues = @()
  
  # Validate logging configuration
  if (-not $Config.Logging.LogDirectory) {
    $issues += "Logging.LogDirectory is required"
  }
  
  if ($Config.Logging.MaxLogFiles -lt 1) {
    $issues += "Logging.MaxLogFiles must be at least 1"
  }
  
  # Validate network configuration
  if (-not $Config.Network.DefaultPPPoEName) {
    $issues += "Network.DefaultPPPoEName is required"
  }
  
  if ($Config.Network.PingTimeout -lt 100) {
    $issues += "Network.PingTimeout should be at least 100ms"
  }
  
  if ($Config.Network.PingCount -lt 1) {
    $issues += "Network.PingCount must be at least 1"
  }
  
  # Validate health check configuration
  if ($Config.HealthChecks.PacketLossThreshold -lt 0 -or $Config.HealthChecks.PacketLossThreshold -gt 100) {
    $issues += "HealthChecks.PacketLossThreshold must be between 0 and 100"
  }
  
  if ($Config.HealthChecks.JitterThreshold -lt 0) {
    $issues += "HealthChecks.JitterThreshold must be non-negative"
  }
  
  if ($Config.HealthChecks.RouteStabilityThreshold -lt 0 -or $Config.HealthChecks.RouteStabilityThreshold -gt 100) {
    $issues += "HealthChecks.RouteStabilityThreshold must be between 0 and 100"
  }
  
  # Validate credential configuration
  if ($Config.Credentials.MinUsernameLength -lt 1) {
    $issues += "Credentials.MinUsernameLength must be at least 1"
  }
  
  if ($Config.Credentials.MinPasswordLength -lt 1) {
    $issues += "Credentials.MinPasswordLength must be at least 1"
  }
  
  return @{
    IsValid = ($issues.Count -eq 0)
    Issues = $issues
  }
}

function Merge-Configuration {
  param(
    [hashtable]$Default,
    [hashtable]$Override
  )
  
  $result = $Default.Clone()
  
  foreach ($key in $Override.Keys) {
    if ($result.ContainsKey($key)) {
      if ($result[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
        $result[$key] = Merge-Configuration -Default $result[$key] -Override $Override[$key]
      } else {
        $result[$key] = $Override[$key]
      }
    } else {
      $result[$key] = $Override[$key]
    }
  }
  
  return $result
}

function Export-Configuration {
  param(
    [hashtable]$Config,
    [string]$OutputPath
  )
  
  try {
    $json = $Config | ConvertTo-Json -Depth 10
    $json | Out-File -FilePath $OutputPath -Encoding UTF8
    return $true
  } catch {
    Write-Error "Failed to export configuration: $($_.Exception.Message)"
    return $false
  }
}

function Import-Configuration {
  param(
    [string]$ConfigPath
  )
  
  if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    return $null
  }
  
  try {
    $content = Get-Content $ConfigPath -Raw
    $config = $content | ConvertFrom-Json | ConvertTo-Hashtable
    return $config
  } catch {
    Write-Error "Failed to import configuration: $($_.Exception.Message)"
    return $null
  }
}

Export-ModuleMember -Function *
