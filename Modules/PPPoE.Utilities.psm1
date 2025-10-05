# PPPoE.Utilities.psm1 - Common utility functions

Set-StrictMode -Version 3.0

function Format-Duration {
  param(
    [TimeSpan]$Duration
  )
  
  if ($Duration.TotalDays -ge 1) {
    return "{0:N1} days" -f $Duration.TotalDays
  } elseif ($Duration.TotalHours -ge 1) {
    return "{0:N1} hours" -f $Duration.TotalHours
  } elseif ($Duration.TotalMinutes -ge 1) {
    return "{0:N1} minutes" -f $Duration.TotalMinutes
  } elseif ($Duration.TotalSeconds -ge 1) {
    return "{0:N1} seconds" -f $Duration.TotalSeconds
  } else {
    return "{0:N0} milliseconds" -f $Duration.TotalMilliseconds
  }
}

function ConvertTo-HumanReadable {
  param(
    [long]$Bytes,
    [int]$DecimalPlaces = 2
  )
  
  $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
  $unitIndex = 0
  $size = [double]$Bytes
  
  while ($size -ge 1024 -and $unitIndex -lt $units.Length - 1) {
    $size /= 1024
    $unitIndex++
  }
  
  return "{0:N$DecimalPlaces} {1}" -f $size, $units[$unitIndex]
}

function Test-AdministratorRights {
  $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SystemInformation {
  return @{
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    Domain = $env:USERDOMAIN
    OSVersion = (Get-WmiObject -Class Win32_OperatingSystem).Caption
    OSArchitecture = (Get-WmiObject -Class Win32_OperatingSystem).OSArchitecture
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    PowerShellEdition = $PSVersionTable.PSEdition
    IsAdministrator = Test-AdministratorRights
    TotalMemory = (Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory
    ProcessorCount = (Get-WmiObject -Class Win32_ComputerSystem).NumberOfProcessors
    ProcessorName = (Get-WmiObject -Class Win32_Processor | Select-Object -First 1).Name
  }
}

function Get-NetworkAdapterSummary {
  param(
    [string]$AdapterName = $null
  )
  
  $adapters = if ($AdapterName) {
    Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
  } else {
    Get-NetAdapter -Physical
  }
  
  if (-not $adapters) {
    return $null
  }
  
  $summary = @()
  foreach ($adapter in $adapters) {
    $summary += @{
      Name = $adapter.Name
      InterfaceDescription = $adapter.InterfaceDescription
      Status = $adapter.Status
      LinkSpeed = $adapter.LinkSpeed
      MediaType = $adapter.MediaType
      MacAddress = $adapter.MacAddress
      DriverVersion = $adapter.DriverVersion
      DriverDate = $adapter.DriverDate
    }
  }
  
  return $summary
}

function Get-ProcessInformation {
  param(
    [string]$ProcessName = $null
  )
  
  $processes = if ($ProcessName) {
    Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
  } else {
    Get-Process | Where-Object { $_.ProcessName -like "*ppp*" -or $_.ProcessName -like "*ras*" -or $_.ProcessName -like "*dial*" }
  }
  
  if (-not $processes) {
    return @()
  }
  
  $info = @()
  foreach ($process in $processes) {
    $info += @{
      ProcessName = $process.ProcessName
      Id = $process.Id
      CPU = $process.CPU
      WorkingSet = $process.WorkingSet
      StartTime = $process.StartTime
      Path = $process.Path
    }
  }
  
  return $info
}

function Test-PortAvailability {
  param(
    [string]$ComputerName = 'localhost',
    [int]$Port,
    [int]$TimeoutMs = 1000
  )
  
  try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync($ComputerName, $Port)
    $timeoutTask = [System.Threading.Tasks.Task]::Delay($TimeoutMs)
    
    $completedTask = [System.Threading.Tasks.Task]::WaitAny($connectTask, $timeoutTask)
    
    if ($completedTask -eq 0 -and $connectTask.IsCompleted -and -not $connectTask.IsFaulted) {
      $tcpClient.Close()
      return $true
    } else {
      $tcpClient.Close()
      return $false
    }
  } catch {
    return $false
  }
}

function Get-DiskSpace {
  param(
    [string]$Drive = 'C:'
  )
  
  try {
    $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$Drive'"
    if ($disk) {
      return @{
        Drive = $disk.DeviceID
        TotalSize = $disk.Size
        FreeSpace = $disk.FreeSpace
        UsedSpace = $disk.Size - $disk.FreeSpace
        PercentFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
        TotalSizeFormatted = ConvertTo-HumanReadable -Bytes $disk.Size
        FreeSpaceFormatted = ConvertTo-HumanReadable -Bytes $disk.FreeSpace
        UsedSpaceFormatted = ConvertTo-HumanReadable -Bytes ($disk.Size - $disk.FreeSpace)
      }
    }
  } catch {
    Write-Warning "Failed to get disk space for drive $Drive`: $($_.Exception.Message)"
  }
  
  return $null
}

function Get-ServiceStatus {
  param(
    [string[]]$ServiceNames = @('RasMan', 'RasAuto', 'RemoteAccess')
  )
  
  $services = @()
  foreach ($serviceName in $ServiceNames) {
    try {
      $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
      if ($service) {
        $services += @{
          Name = $service.Name
          DisplayName = $service.DisplayName
          Status = $service.Status
          StartType = $service.StartType
          CanStop = $service.CanStop
          CanPauseAndContinue = $service.CanPauseAndContinue
        }
      }
    } catch {
      Write-Warning "Failed to get service information for $serviceName`: $($_.Exception.Message)"
    }
  }
  
  return $services
}

function Measure-ExecutionTime {
  param(
    [scriptblock]$ScriptBlock,
    [string]$Description = "Script execution"
  )
  
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  
  try {
    $result = & $ScriptBlock
    $stopwatch.Stop()
    
    return @{
      Result = $result
      Duration = $stopwatch.Elapsed
      DurationFormatted = Format-Duration -Duration $stopwatch.Elapsed
      Description = $Description
      Success = $true
    }
  } catch {
    $stopwatch.Stop()
    
    return @{
      Result = $null
      Duration = $stopwatch.Elapsed
      DurationFormatted = Format-Duration -Duration $stopwatch.Elapsed
      Description = $Description
      Success = $false
      Error = $_.Exception.Message
    }
  }
}

function Test-InternetConnectivity {
  param(
    [string[]]$TestUrls = @('https://www.google.com', 'https://www.cloudflare.com', 'https://www.microsoft.com'),
    [int]$TimeoutSeconds = 5
  )
  
  $results = @()
  
  foreach ($url in $TestUrls) {
    try {
      $response = Invoke-WebRequest -Uri $url -TimeoutSec $TimeoutSeconds -UseBasicParsing
      $results += @{
        Url = $url
        Status = 'Success'
        StatusCode = $response.StatusCode
        ResponseTime = $response.Headers.'X-Response-Time'
        Success = $true
      }
    } catch {
      $results += @{
        Url = $url
        Status = 'Failed'
        StatusCode = $null
        ResponseTime = $null
        Success = $false
        Error = $_.Exception.Message
      }
    }
  }
  
  return $results
}

function Get-EnvironmentInfo {
  return @{
    PowerShellVersion = $PSVersionTable.PSVersion
    PowerShellEdition = $PSVersionTable.PSEdition
    ExecutionPolicy = Get-ExecutionPolicy
    ModulePath = $env:PSModulePath -split ';'
    WorkingDirectory = Get-Location
    ScriptRoot = $PSScriptRoot
    UserProfile = $env:USERPROFILE
    TempPath = $env:TEMP
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    Domain = $env:USERDOMAIN
    Architecture = $env:PROCESSOR_ARCHITECTURE
    OSVersion = [System.Environment]::OSVersion.VersionString
    Is64Bit = [System.Environment]::Is64BitOperatingSystem
    Is64BitProcess = [System.Environment]::Is64BitProcess
  }
}

function Get-DisabledWiFiAdapters {
  try {
    # Only return the primary WiFi adapter if it's disabled (same logic as Get-WiFiAdapters)
    $wifiAdapters = Get-NetAdapter -Physical | Where-Object { 
      $_.MediaType -match '802\.11' -and 
      $_.Status -in @('Up', 'Disconnected', 'Disabled') -and  # Include Disabled for fallback
      $_.InterfaceDescription -notlike "*virtual*" -and
      $_.InterfaceDescription -notlike "*hyper-v*" -and
      $_.InterfaceDescription -notlike "*vmware*" -and
      $_.InterfaceDescription -notlike "*virtualbox*"
    }
    
    # If multiple WiFi adapters from same hardware, prefer the disabled one
    $disabledAdapter = $wifiAdapters | Where-Object { $_.Status -eq 'Disabled' } | Select-Object -First 1
    if ($disabledAdapter) {
      return ,@($disabledAdapter.Name)  # Force array return
    } else {
      return ,@()  # Force empty array return
    }
  } catch {
    Write-Warning "Failed to get disabled WiFi adapters: $($_.Exception.Message)"
    return ,@()  # Force empty array return on error
  }
}

function Enable-AllDisabledWiFiAdapters {
  param(
    [scriptblock]$WriteLog = { param($msg) Write-Host $msg }
  )
  
  try {
    $disabledAdapters = Get-DisabledWiFiAdapters
    if ($disabledAdapters -and $disabledAdapters.Count -gt 0) {
      & $WriteLog "Found $($disabledAdapters.Count) disabled WiFi adapters, attempting to re-enable..."
      
      $enabledCount = 0
      foreach ($adapterName in $disabledAdapters) {
        try {
          Enable-NetAdapter -Name $adapterName -Confirm:$false -ErrorAction Stop
          & $WriteLog "Re-enabled WiFi adapter: $adapterName"
          $enabledCount++
        } catch {
          & $WriteLog "Failed to re-enable WiFi adapter $adapterName`: $($_.Exception.Message)"
        }
      }
      
      & $WriteLog "Successfully re-enabled $enabledCount of $($disabledAdapters.Count) WiFi adapters"
      return $enabledCount
    } else {
      & $WriteLog "No disabled WiFi adapters found"
      return 0
    }
  } catch {
    & $WriteLog "Error during WiFi adapter cleanup: $($_.Exception.Message)"
    return -1
  }
}

Export-ModuleMember -Function *
