
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

  # Concise per-tier summary (PASS/FAIL/INFO)
  try {
    Write-Blank
    Write-Log "--- TIER SUMMARY ---"
    $tiers = @(
      @{ Name = 'System';      Keys = @('PowerShell version','Physical adapter detected','Ethernet link state','Adapter driver','ONT management') },
      @{ Name = 'PPP/Auth';    Keys = @('Credentials source','PPPoE authentication','PPP interface present','PPP IPv4 assignment') },
      @{ Name = 'Routing';     Keys = @('Default route via PPP','PPP gateway assignment','Gateway reachability') },
      @{ Name = 'Connectivity';Keys = @('Ping (1.1.1.1) via PPP','Ping (8.8.8.8) via PPP','TCP connectivity','Multi-destination routing','Windows Firewall','MTU probe (DF)') }
    )

    foreach ($tier in $tiers) {
      $values = @()
      foreach ($k in $Health.Keys) {
        $displayKey = $k -replace '^\d{2}_',''
        if ($tier.Keys -contains $displayKey) { $values += $Health[$k] }
      }
      if ($values.Count -gt 0) {
        $tierStatus = if ($values -match 'FAIL') { 'FAIL' } elseif ($values -match 'WARN') { 'WARN' } elseif ($values -match 'INFO|SKIP|N/A') { 'INFO' } else { 'PASS' }
        Write-Log ("{0}: {1}" -f $tier.Name, $tierStatus)
      }
    }
  } catch { }
  
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
  $gatewayStatus = ($Health.Values | Where-Object { $_ -match 'PPP gateway assignment' })

  # Extract specific keyed values we need to reason about
  $physicalAdapterKey = ($Health.Keys | Where-Object { $_ -match '^\d{2}_Physical adapter detected$' } | Select-Object -First 1)
  $physicalAdapterValue = if ($physicalAdapterKey) { $Health[$physicalAdapterKey] } else { $null }
  
  # Provider-agnostic policy: do not treat 0.0.0.0/unspecified gateway as a critical issue
  # We rely on the presence of a usable default route instead.
  $zeroGatewayIssue = $false
  
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
  
  # CRITICAL: 0.0.0.0 Gateway Issue - This takes precedence over other issues
  if ($zeroGatewayIssue) {
    Write-Label "*** CRITICAL: IPCP NEGOTIATION FAILURE DETECTED ***"
    Write-Blank
    Write-Label "PROBLEM IDENTIFIED:"
    Write-ListItem "PPPoE connection succeeds but gateway is 0.0.0.0" 1
    Write-ListItem "This is an IPCP (IP Control Protocol) negotiation failure" 1
    Write-ListItem "Your PC gets an IP but no default gateway from the ISP" 1
    Write-ListItem "Result: Direct TCP connections work, but browsing/streaming fails" 1
    Write-Blank
    Write-Label "TECHNICAL DETAILS:"
    Write-ListItem "PPPoE authentication: SUCCESS" 1
    Write-ListItem "IP address assigned: YES (likely 100.64.x.x/32 or similar)" 1
    Write-ListItem "Default gateway: 0.0.0.0 (INVALID - should be real IP)" 1
    Write-ListItem "Traceroute shows gateway exists but wasn't negotiated properly" 1
    Write-Blank
    Write-Label "ROOT CAUSES (in order of likelihood):"
    Write-ListItem "1. ISP PPPoE SERVER CONFIGURATION ISSUE (most common)" 1
    Write-ListItem "   The broadband provider's PPPoE server has a misconfiguration" 2
    Write-ListItem "   IPCP phase completes but doesn't send gateway address" 2
    Write-ListItem "   This is a PROVIDER-SIDE ISSUE, not your equipment" 2
    Write-Blank
    Write-ListItem "2. WINDOWS PPPoE CLIENT ISSUE (less common)" 1
    Write-ListItem "   Windows RAS/PPPoE client not parsing IPCP response correctly" 2
    Write-ListItem "   May require Windows update or RAS service restart" 2
    Write-Blank
    Write-ListItem "3. MTU/MSS NEGOTIATION PROBLEM (rare)" 1
    Write-ListItem "   IPCP packets being fragmented or dropped" 2
    Write-ListItem "   Can happen with certain MTU settings" 2
    Write-Blank
    Write-Label "IMMEDIATE ACTIONS TO TRY:"
    Write-ListItem "1. RESTART RASMAN SERVICE (fixes Windows client issues):" 1
    Write-ListItem "   Open PowerShell as Administrator:" 2
    Write-ListItem "   Restart-Service RasMan -Force" 2
    Write-ListItem "   Then reconnect PPPoE and test" 2
    Write-Blank
    Write-ListItem "2. DELETE AND RECREATE PPPoE CONNECTION:" 1
    Write-ListItem "   Remove-NetAdapter -Name 'YourPPPoEName' -Confirm:$false" 2
    Write-ListItem "   Then create new PPPoE connection from scratch" 2
    Write-ListItem "   Sometimes connection settings become corrupted" 2
    Write-Blank
    Write-ListItem "3. TEST WITH DIFFERENT PPPoE CLIENT (diagnostic only):" 1
    Write-ListItem "   Try a router in PPPoE mode to see if it gets proper gateway" 2
    Write-ListItem "   If router works: Windows RAS issue" 2
    Write-ListItem "   If router also fails: Provider PPPoE server issue" 2
    Write-Blank
    Write-Label "CONTACT YOUR ISP WITH THIS INFORMATION:"
    Write-ListItem "Your connection AUTHENTICATES successfully" 1
    Write-ListItem "You receive an IP address" 1
    Write-ListItem "But NO DEFAULT GATEWAY is provided during IPCP negotiation" 1
    Write-ListItem "Gateway shows as 0.0.0.0 in Windows" 1
    Write-ListItem "This is preventing normal internet access" 1
    Write-ListItem "Request they check their PPPoE/BNG (Broadband Network Gateway) configuration" 1
    Write-ListItem "This is a known issue with some ISP PPPoE implementations" 1
    Write-Blank
    Write-Label "WHY SOME THINGS WORK:"
    Write-ListItem "TCP to specific IPs works: Using on-link routing or cached routes" 1
    Write-ListItem "DNS works: DNS servers provided via IPCP (separate from gateway)" 1
    Write-ListItem "Traceroute works: Creates temporary routes as it discovers hops" 1
    Write-ListItem "But browsing fails: Requires proper default gateway for routing" 1
    Write-Blank
    Write-Label "THIS IS NOT YOUR FAULT:"
    Write-ListItem "Your equipment is working correctly" 1
    Write-ListItem "Your Ethernet, ONT, and physical connection are fine" 1
    Write-ListItem "The PPPoE server is not providing required routing information" 1
    Write-ListItem "This requires ISP intervention or Windows client workaround" 1
  }
  elseif ($physicalAdapterValue -and $physicalAdapterValue -match 'FAIL \(none found\)') {
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
  elseif ($Health.Values -match 'PPPoE authentication.*FAIL') {
    Write-Label "CREDENTIALS/AUTHENTICATION ISSUE DETECTED"
    Write-ListItem "Check your broadband username and password are correct" 1
    Write-ListItem "Verify credentials in credentials.ps1 file or Windows saved credentials" 1
    Write-ListItem "Test with script parameters: -UserName 'your@username' -Password 'yourpassword'" 1
    Write-ListItem "Contact your broadband provider to verify account status" 1
    Write-ListItem "This is likely a credentials or account issue" 1
  }
  elseif ($Health.Values -match 'Credentials source.*FAIL') {
    Write-Label "CREDENTIALS NOT AVAILABLE"
    Write-ListItem "No valid credentials found from any source" 1
    Write-ListItem "Check credentials.ps1 file exists and has correct username/password" 1
    Write-ListItem "Or provide credentials as script parameters" 1
    Write-ListItem "Or ensure Windows has saved credentials for this connection" 1
  }
  elseif ($Health.Values -match 'WARN.*No ONTs reachable') {
    Write-Label "ONT/FIBER ISSUE DETECTED"
    Write-ListItem "Check ONT LEDs (PON should be solid green)" 1
    Write-ListItem "Check fiber cable connection to ONT" 1
    Write-ListItem "Contact Openreach if ONT shows problems" 1
    Write-ListItem "This is likely an Openreach line/cabinet issue" 1
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

