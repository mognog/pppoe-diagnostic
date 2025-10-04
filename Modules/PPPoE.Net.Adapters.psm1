# PPPoE.Net.Adapters.psm1 - Network adapter management functions

Set-StrictMode -Version 3.0

function Get-CandidateEthernetAdapters {
  $eth = Get-NetAdapter -Physical | Where-Object { $_.MediaType -match '802\.3' -or $_.Name -match 'Ethernet' }
  $eth | Sort-Object -Property Status -Descending
}

function Get-RecommendedAdapter {
  $list = Get-CandidateEthernetAdapters
  # Ensure we have an array to work with
  if ($list -and -not ($list -is [array])) {
    $list = @($list)
  }
  
  # Prefer 'USB', 'Realtek', 'Sabrent', '5GbE' if present
  $pref = $list | Where-Object { $_.InterfaceDescription -match 'Realtek|Sabrent|USB|5G' }
  if ($pref -and -not ($pref -is [array])) {
    $pref = @($pref)
  }
  
  if ($pref -and $pref.Count -gt 0) { return $pref[0] }
  if ($list -and $list.Count -gt 0) { return $list[0] }
  return $null
}

function Select-NetworkAdapter {
  param([scriptblock]$WriteLog)
  
  $adapters = Get-CandidateEthernetAdapters
  # Ensure we have an array to work with
  if ($adapters -and -not ($adapters -is [array])) {
    $adapters = @($adapters)
  }
  
  if (-not $adapters -or $adapters.Count -eq 0) {
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

function Get-WiFiAdapters {
  Get-NetAdapter -Physical | Where-Object { $_.MediaType -match '802\.11' }
}

function Disable-WiFiAdapters {
  param([scriptblock]$WriteLog)
  
  $wifiAdapters = Get-WiFiAdapters
  if (-not $wifiAdapters) {
    & $WriteLog "No WiFi adapters found to disable"
    return
  }
  
  foreach ($adapter in $wifiAdapters) {
    if ($adapter.Status -eq 'Up') {
      & $WriteLog "Disabling WiFi adapter: $($adapter.Name)"
      try {
        Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
        & $WriteLog "WiFi adapter disabled: $($adapter.Name)"
      } catch {
        & $WriteLog "Failed to disable WiFi adapter $($adapter.Name): $($_.Exception.Message)"
      }
    } else {
      & $WriteLog "WiFi adapter already disabled: $($adapter.Name)"
    }
  }
}

function Enable-WiFiAdapters {
  param([scriptblock]$WriteLog)
  
  $wifiAdapters = Get-WiFiAdapters
  if (-not $wifiAdapters) {
    & $WriteLog "No WiFi adapters found to enable"
    return
  }
  
  foreach ($adapter in $wifiAdapters) {
    if ($adapter.Status -eq 'Disabled') {
      & $WriteLog "Enabling WiFi adapter: $($adapter.Name)"
      try {
        Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
        & $WriteLog "WiFi adapter enabled: $($adapter.Name)"
      } catch {
        & $WriteLog "Failed to enable WiFi adapter $($adapter.Name): $($_.Exception.Message)"
      }
    } else {
      & $WriteLog "WiFi adapter already enabled: $($adapter.Name)"
    }
  }
}

function Get-LinkHealth {
  param([string]$AdapterName)
  
  try {
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
    $stats = Get-NetAdapterStatistics -Name $AdapterName -ErrorAction SilentlyContinue
    
    $result = @{
      Name = $adapter.Name
      Status = $adapter.Status
      LinkSpeed = $adapter.LinkSpeed
      MediaType = $adapter.MediaType
      InterfaceDescription = $adapter.InterfaceDescription
      BytesReceived = if ($stats) { $stats.BytesReceived } else { 0 }
      BytesSent = if ($stats) { $stats.BytesSent } else { 0 }
      PacketsReceived = if ($stats) { $stats.UnicastPacketsReceived } else { 0 }
      PacketsSent = if ($stats) { $stats.UnicastPacketsSent } else { 0 }
      ErrorsReceived = if ($stats) { $stats.DiscardedPacketsIncoming } else { 0 }
      ErrorsSent = if ($stats) { $stats.DiscardedPacketsOutgoing } else { 0 }
    }
    
    return $result
  } catch {
    return $null
  }
}

function Get-AdapterDriverInfo {
  param([string]$AdapterName)
  
  try {
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
    $driver = Get-NetAdapterDriver -Name $AdapterName -ErrorAction SilentlyContinue
    
    $result = @{
      Name = $adapter.Name
      InterfaceDescription = $adapter.InterfaceDescription
      DriverName = if ($driver) { $driver.DriverName } else { "Unknown" }
      DriverVersion = if ($driver) { $driver.DriverVersion } else { "Unknown" }
      DriverDate = if ($driver) { $driver.DriverDate } else { "Unknown" }
      DriverProvider = if ($driver) { $driver.DriverProvider } else { "Unknown" }
    }
    
    return $result
  } catch {
    return $null
  }
}

Export-ModuleMember -Function *
