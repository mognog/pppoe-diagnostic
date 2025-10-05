
# PPPoE.Health.psm1 - Health checks and summary

Set-StrictMode -Version 3.0

function New-Health {
  return [ordered]@{}
}

function Add-Health {
  param($Health, [string]$Key, [string]$Value, [int]$Order = 0)
  # Store the order as a prefix in the key for sorting
  $orderedKey = "{0:D2}_{1}" -f $Order, $Key
  $Health[$orderedKey] = $Value
  return $Health
}

function Write-HealthSummary {
  param([hashtable]$Health)
  Write-Log "=== HEALTH SUMMARY (ASCII) ==="
  
  # Sort by the prefixed key (which includes order)
  $sortedKeys = $Health.Keys | Sort-Object
  
  $i = 1
  foreach ($key in $sortedKeys) {
    # Remove the order prefix from the display
    $displayKey = $key -replace '^\d{2}_', ''
    $value = $Health[$key]
    $dots = '.' * [Math]::Max(1, 28 - $displayKey.Length)
    Write-Log ("[{0}] {1} {2} {3}" -f $i, $displayKey, $dots, $value)
    $i++
  }
  
  $hasFail = ($Health.Values | Where-Object { $_ -match 'FAIL' })
  $hasWarn = ($Health.Values | Where-Object { $_ -match 'WARN' })
  $overall = if ($hasFail) { 'FAIL' } elseif ($hasWarn) { 'WARN' } else { 'OK' }
  Write-Log ("OVERALL: {0}" -f $overall)
  
  # Add diagnostic conclusions
  Write-DiagnosticConclusions -Health $Health
}

function Write-DiagnosticConclusions {
  param([hashtable]$Health)
  
  Write-Section "DIAGNOSTIC CONCLUSIONS"
  
  # Analyze the health results to provide clear guidance
  $linkState = ($Health.Values | Where-Object { $_ -match 'Ethernet link state' })
  $ontStatus = ($Health.Values | Where-Object { $_ -match 'ONT availability' })
  $authStatus = ($Health.Values | Where-Object { $_ -match 'PPPoE authentication' })
  $pppInterface = ($Health.Values | Where-Object { $_ -match 'PPP interface present' })
  $connectivity = ($Health.Values | Where-Object { $_ -match 'Ping.*via PPP' })

  # Extract specific keyed values we need to reason about
  $physicalAdapterKey = ($Health.Keys | Where-Object { $_ -match '^\d{2}_Physical adapter detected$' } | Select-Object -First 1)
  $physicalAdapterValue = if ($physicalAdapterKey) { $Health[$physicalAdapterKey] } else { $null }
  
  # Check what's working
  $workingComponents = @()
  $problemAreas = @()
  
  # PC/Software Layer
  if ($Health.Values -match 'PowerShell version.*OK') { $workingComponents += "PC/Software" }
  if ($physicalAdapterValue -and $physicalAdapterValue -match 'OK') { $workingComponents += "PC Network Adapter" }
  if ($Health.Values -match 'Adapter driver.*OK') { $workingComponents += "PC Network Driver" }
  
  # Cable Layer (only check if link is up)
  if ($Health.Values -match 'Ethernet link state.*OK') { 
    $workingComponents += "Ethernet Cable" 
    if ($Health.Values -match 'Link error counters.*OK') { $workingComponents += "Cable Quality" }
    if ($Health.Values -match 'ONT availability.*OK') { $workingComponents += "ONT Device" }
    
    # Provider Layer (only check if cable is working)
    if ($Health.Values -match 'PPPoE authentication.*OK') { $workingComponents += "Provider Authentication" }
    if ($Health.Values -match 'PPP interface present.*OK') { $workingComponents += "Provider Connection" }
    if ($Health.Values -match 'Ping.*via PPP.*OK') { $workingComponents += "Provider Network" }
  }
  
  # Identify problem areas (check in order of precedence)
  if ($Health.Values -match 'FAIL.*Down') { 
    $problemAreas += "Ethernet cable or connection" 
  }
  elseif ($Health.Values -match 'WARN.*No ONTs reachable') { 
    $problemAreas += "ONT device or fiber connection" 
  }
  elseif ($Health.Values -match 'FAIL.*bad credentials') { 
    $problemAreas += "Broadband provider authentication" 
  }
  elseif ($Health.Values -match 'FAIL.*not created') { 
    $problemAreas += "Provider connection establishment" 
  }
  elseif ($Health.Values -match 'FAIL.*unreachable') { 
    $problemAreas += "Provider network connectivity" 
  }
  
  # Generate conclusions
  if ($workingComponents.Count -gt 0) {
    Write-Label "WORKING COMPONENTS"
    foreach ($component in $workingComponents) { Write-ListItem $component 1 }
  }
  
  if ($problemAreas.Count -gt 0) {
    Write-Blank
    Write-Label "PROBLEM AREAS"
    foreach ($problem in $problemAreas) { Write-ListItem $problem 1 }
  }
  
  # Provide specific guidance based on the failure point
  Write-Blank
  Write-Section "TROUBLESHOOTING GUIDANCE"
  
  if ($physicalAdapterValue -and $physicalAdapterValue -match 'FAIL \(none found\)') {
    Write-Label "NO ETHERNET ADAPTER DETECTED"
    Write-ListItem "If using a built-in (internal) Ethernet port:" 1
    Write-ListItem "Check Device Manager for disabled or missing adapter" 2
    Write-ListItem "Ensure the adapter is enabled and drivers are installed" 2
    Write-ListItem "If using a USB Ethernet adapter (external):" 1
    Write-ListItem "Unplug and replug the adapter" 2
    Write-ListItem "Try a different USB port (prefer USB 3.0/blue)" 2
    Write-ListItem "If available, try a different USB-to-Ethernet dongle" 2
    Write-ListItem "After resolving adapter detection, re-run diagnostics" 1
  }
  elseif ($Health.Values -match 'FAIL.*Down') {
    Write-Label "CABLE ISSUE DETECTED"
    Write-ListItem "Check Ethernet cable connection to ONT" 1
    Write-ListItem "Try a different Ethernet cable" 1
    Write-ListItem "Ensure cable is fully inserted at both ends" 1
    Write-ListItem "Check ONT LAN port LED (should be solid green)" 1
  }
  elseif ($Health.Values -match 'WARN.*No ONTs reachable') {
    Write-Label "ONT/FIBER ISSUE DETECTED"
    Write-ListItem "Check ONT LEDs (PON should be solid green)" 1
    Write-ListItem "Check fiber cable connection to ONT" 1
    Write-ListItem "Contact Openreach if ONT shows problems" 1
    Write-ListItem "This is likely an Openreach line/cabinet issue" 1
  }
  elseif ($Health.Values -match 'PPPoE authentication.*FAIL') {
    Write-Label "PROVIDER AUTHENTICATION ISSUE"
    Write-ListItem "Verify broadband username/password" 1
    Write-ListItem "Check with broadband provider for account status" 1
    Write-ListItem "This is likely a broadband provider issue" 1
  }
  elseif ($Health.Values -match 'PPP interface present.*FAIL') {
    Write-Label "PROVIDER CONNECTION ISSUE"
    Write-ListItem "Provider authentication succeeded but connection failed" 1
    Write-ListItem "Check with broadband provider" 1
    Write-ListItem "This is likely a provider network issue" 1
  }
  elseif ($Health.Values -match 'Ping.*via PPP.*FAIL') {
    Write-Label "PROVIDER NETWORK ISSUE"
    Write-ListItem "Connection established but internet access failed" 1
    Write-ListItem "Check with broadband provider" 1
    Write-ListItem "This is likely a provider routing/DNS issue" 1
  }
  elseif ($workingComponents.Count -eq 0) {
    Write-Label "UNKNOWN ISSUE"
    Write-ListItem "Multiple components failed" 1
    Write-ListItem "Check with broadband provider" 1
    Write-ListItem "May need Openreach engineer visit" 1
  }
  else {
    Write-Label "ALL TESTS PASSED"
    Write-ListItem "Direct ONT connection works perfectly" 1
    Write-ListItem "Problem is likely with router or WiFi setup" 1
    Write-ListItem "Try connecting router to same Ethernet port" 1
    Write-ListItem "Check router configuration and WiFi settings" 1
  }
}

Export-ModuleMember -Function *

