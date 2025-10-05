
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
  
  Write-Log ""
  Write-Log "=== DIAGNOSTIC CONCLUSIONS ==="
  
  # Analyze the health results to provide clear guidance
  $linkState = ($Health.Values | Where-Object { $_ -match 'Ethernet link state' })
  $ontStatus = ($Health.Values | Where-Object { $_ -match 'ONT availability' })
  $authStatus = ($Health.Values | Where-Object { $_ -match 'PPPoE authentication' })
  $pppInterface = ($Health.Values | Where-Object { $_ -match 'PPP interface present' })
  $connectivity = ($Health.Values | Where-Object { $_ -match 'Ping.*via PPP' })
  
  # Check what's working
  $workingComponents = @()
  $problemAreas = @()
  
  # PC/Software Layer
  if ($Health.Values -match 'PowerShell version.*OK') { $workingComponents += "PC/Software" }
  if ($Health.Values -match 'Physical adapter detected.*OK') { $workingComponents += "PC Network Adapter" }
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
    Write-Log "✓ WORKING COMPONENTS:"
    foreach ($component in $workingComponents) {
      Write-Log "  - $component"
    }
  }
  
  if ($problemAreas.Count -gt 0) {
    Write-Log ""
    Write-Log "✗ PROBLEM AREAS:"
    foreach ($problem in $problemAreas) {
      Write-Log "  - $problem"
    }
  }
  
  # Provide specific guidance based on the failure point
  Write-Log ""
  Write-Log "=== TROUBLESHOOTING GUIDANCE ==="
  
  if ($Health.Values -match 'FAIL.*Down') {
    Write-Log "🔌 CABLE ISSUE DETECTED:"
    Write-Log "  - Check Ethernet cable connection to ONT"
    Write-Log "  - Try a different Ethernet cable"
    Write-Log "  - Ensure cable is fully inserted at both ends"
    Write-Log "  - Check ONT LAN port LED (should be solid green)"
  }
  elseif ($Health.Values -match 'WARN.*No ONTs reachable') {
    Write-Log "📡 ONT/FIBER ISSUE DETECTED:"
    Write-Log "  - Check ONT LEDs (PON should be solid green)"
    Write-Log "  - Check fiber cable connection to ONT"
    Write-Log "  - Contact Openreach if ONT shows problems"
    Write-Log "  - This is likely an Openreach line/cabinet issue"
  }
  elseif ($Health.Values -match 'PPPoE authentication.*FAIL') {
    Write-Log "🔐 PROVIDER AUTHENTICATION ISSUE:"
    Write-Log "  - Verify broadband username/password"
    Write-Log "  - Check with broadband provider for account status"
    Write-Log "  - This is likely a broadband provider issue"
  }
  elseif ($Health.Values -match 'PPP interface present.*FAIL') {
    Write-Log "🌐 PROVIDER CONNECTION ISSUE:"
    Write-Log "  - Provider authentication succeeded but connection failed"
    Write-Log "  - Check with broadband provider"
    Write-Log "  - This is likely a provider network issue"
  }
  elseif ($Health.Values -match 'Ping.*via PPP.*FAIL') {
    Write-Log "🚫 PROVIDER NETWORK ISSUE:"
    Write-Log "  - Connection established but internet access failed"
    Write-Log "  - Check with broadband provider"
    Write-Log "  - This is likely a provider routing/DNS issue"
  }
  elseif ($workingComponents.Count -eq 0) {
    Write-Log "❓ UNKNOWN ISSUE:"
    Write-Log "  - Multiple components failed"
    Write-Log "  - Check with broadband provider"
    Write-Log "  - May need Openreach engineer visit"
  }
  else {
    Write-Log "✅ ALL TESTS PASSED:"
    Write-Log "  - Direct ONT connection works perfectly"
    Write-Log "  - Problem is likely with router or WiFi setup"
    Write-Log "  - Try connecting router to same Ethernet port"
    Write-Log "  - Check router configuration and WiFi settings"
  }
}

Export-ModuleMember -Function *

