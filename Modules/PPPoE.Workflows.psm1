# PPPoE.Workflows.psm1 - Diagnostic workflow orchestration

Set-StrictMode -Version 3.0

function Invoke-PPPoEDiagnosticWorkflow {
  param(
    [string]$PppoeName = 'PPPoE',
    [string]$UserName,
    [string]$Password,
    [string]$TargetAdapter,
    [switch]$FullLog,
    [switch]$SkipWifiToggle,
    [switch]$KeepPPP,
    [scriptblock]$WriteLog
  )
  
  # Initialize health tracking
  $Health = New-Health
  
  # Initialize variables to prevent undefined variable errors
  $pppInterface = $null
  $pppIP = $null
  $connectionResult = $null
  
  # Check and manage WiFi adapters
  $disabledWiFiAdapters = @()
  if (-not $SkipWifiToggle) {
    & $WriteLog "Checking WiFi adapter status..."
    $disabledWiFiAdapters = Disable-WiFiAdapters -WriteLog $WriteLog
    if ($disabledWiFiAdapters -and $disabledWiFiAdapters -is [array] -and $disabledWiFiAdapters.Count -gt 0) {
      & $WriteLog "Temporarily disabled $($disabledWiFiAdapters.Count) WiFi adapter(s) to prevent interference"
    } else {
      & $WriteLog "No WiFi adapters were active or found"
    }
  } else {
    & $WriteLog "Skipping WiFi adapter management (SkipWifiToggle specified)"
  }

  # Disconnect any existing PPPoE connections to start clean
  & $WriteLog "Disconnecting any existing PPPoE connections..."
  Disconnect-AllPPPoE
  & $WriteLog "Cleanup complete."

  # Phase 1: Basic System Checks
  & $WriteLog ""
  & $WriteLog "=== BASIC SYSTEM CHECKS ==="
  & $WriteLog "Checking PowerShell, adapters, and system status..."
  $basicChecks = Invoke-BasicSystemChecks -Health $Health -WriteLog $WriteLog
  
  # Handle null or malformed return from health check function
  if ($basicChecks -is [hashtable] -and $basicChecks.ContainsKey('Health')) {
    $Health = $basicChecks.Health
    $pppoeConnections = $basicChecks.PPPoEConnections
  } else {
    # Fallback if health check function returns null or malformed object
    & $WriteLog "Warning: Basic system checks returned unexpected result, using fallback values"
    $Health = Add-Health $Health 'Basic system checks' 'FAIL (unexpected result)' 1
    $pppoeConnections = @()
  }

  # Phase 2: Network Adapter Checks
  & $WriteLog ""
  & $WriteLog "=== NETWORK ADAPTER CHECKS ==="
  & $WriteLog "Scanning for Ethernet adapters and checking link status..."
  $adapterChecks = Invoke-NetworkAdapterChecks -Health $Health -TargetAdapter $TargetAdapter -WriteLog $WriteLog
  
  # Handle null or malformed return from health check function
  if ($adapterChecks -is [hashtable] -and $adapterChecks.ContainsKey('Health')) {
    $Health = $adapterChecks.Health
    $nic = $adapterChecks.Adapter
    $linkDown = $adapterChecks.LinkDown
  } else {
    # Fallback if health check function returns null or malformed object
    & $WriteLog "Warning: Network adapter checks returned unexpected result, using fallback values"
    $Health = Add-Health $Health 'Network adapter checks' 'FAIL (unexpected result)' 3
    $nic = $null
    $linkDown = $true
  }

  # Phase 3: PPPoE Connection (only if link is up)
  if (-not $linkDown) {
    # Determine the correct connection name to use
    $connectionNameToUse = $PppoeName
    if ($pppoeConnections -and $pppoeConnections.Count -gt 0) {
      # If we found existing connections, use the first one (most likely the correct one)
      $connectionNameToUse = $pppoeConnections[0]
      & $WriteLog "Using detected connection name: '$connectionNameToUse'"
    }
    
    # Set credentials file path (credentials.ps1 is in the root directory, not Modules)
    $scriptRoot = Split-Path $PSScriptRoot -Parent
    $credentialsFile = Join-Path $scriptRoot "credentials.ps1"
    
    & $WriteLog ""
    & $WriteLog "=== PPPoE CONNECTION ATTEMPTS ==="
    & $WriteLog "Attempting to establish PPPoE connection (this may take 30-90 seconds)..."
    $connectionChecks = Invoke-PPPoEConnectionChecks -Health $Health -ConnectionNameToUse $connectionNameToUse -UserName $UserName -Password $Password -CredentialsFile $credentialsFile -WriteLog $WriteLog
    
    # Handle null or malformed return from health check function
    if ($connectionChecks -is [hashtable] -and $connectionChecks.ContainsKey('Health')) {
      $Health = $connectionChecks.Health
      $connectionResult = $connectionChecks.ConnectionResult
      $authOk = $connectionChecks.AuthenticationOk
    } else {
      # Fallback if health check function returns null or malformed object
      & $WriteLog "Warning: PPPoE connection checks returned unexpected result, using fallback values"
      $Health = Add-Health $Health 'PPPoE connection checks' 'FAIL (unexpected result)' 10
      $connectionResult = $null
      $authOk = $false
    }

    # Phase 4: PPP Interface Checks (only if authentication succeeded)
    if ($authOk) {
      & $WriteLog ""
      & $WriteLog "=== PPP INTERFACE VERIFICATION ==="
      & $WriteLog "Verifying PPP interface and routing configuration..."
      $pppChecks = Invoke-PPPInterfaceChecks -Health $Health -ConnectionNameToUse $connectionNameToUse -WriteLog $WriteLog
      
      # Handle null or malformed return from health check function
      if ($pppChecks -is [hashtable] -and $pppChecks.ContainsKey('Health')) {
        $Health = $pppChecks.Health
        $pppInterface = $pppChecks.PPPInterface
        $pppIP = $pppChecks.PPPIP
      } else {
        # Fallback if health check function returns null or malformed object
        & $WriteLog "Warning: PPP interface checks returned unexpected result, using fallback values"
        $Health = Add-Health $Health 'PPP interface checks' 'FAIL (unexpected result)' 13
        $pppInterface = $null
        $pppIP = $null
      }

      # Phase 5: Connectivity Tests (only if we have a PPP interface)
      if ($pppIP) {
        & $WriteLog ""
        & $WriteLog "=== CONNECTIVITY TESTS ==="
        & $WriteLog "Testing basic connectivity and DNS resolution..."
        $Health = Invoke-ConnectivityChecks -Health $Health -PPPInterface $pppInterface -PPPIP $pppIP -WriteLog $WriteLog

        # Phase 5.5: Enhanced Connectivity Diagnostics
        & $WriteLog ""
        & $WriteLog "=== ENHANCED CONNECTIVITY DIAGNOSTICS ==="
        & $WriteLog "Running advanced tests to detect specific network issues..."
        $Health = Invoke-EnhancedConnectivityDiagnostics -Health $Health -WriteLog $WriteLog

        # Phase 6: Advanced Connectivity Tests
        if ($FullLog) {
          & $WriteLog ""
          & $WriteLog "=== ADVANCED CONNECTIVITY TESTS ==="
          $Health = Invoke-AdvancedConnectivityChecks -Health $Health -PPPInterface $pppInterface -WriteLog $WriteLog
        }

        # Phase 7: Traceroute Diagnostics
        if ($FullLog) {
          & $WriteLog ""
          & $WriteLog "=== TRACEROUTE DIAGNOSTICS ==="
          $Health = Invoke-TracerouteDiagnostics -Health $Health -WriteLog $WriteLog
        }

        # Phase 8: Optional Stability Test
        if ($FullLog) {
          & $WriteLog ""
          & $WriteLog "=== OPTIONAL STABILITY TEST ==="
          $Health = Invoke-OptionalStabilityTest -Health $Health -WriteLog $WriteLog
        }

        # Phase 9: Advanced Streaming Diagnostics (Full Log Only)
        if ($FullLog) {
          & $WriteLog ""
          & $WriteLog "=== ADVANCED STREAMING DIAGNOSTICS ==="
          $Health = Invoke-AdvancedStreamingDiagnostics -Health $Health -WriteLog $WriteLog
        }
      }
    } else {
      # Link is up but authentication failed
      $Health = Add-Health $Health 'PPP interface present' 'N/A' 13
      $Health = Add-Health $Health 'PPP IPv4 assignment' 'N/A' 14
      $Health = Add-Health $Health 'Default route via PPP' 'N/A' 15
    }
  }

  # Phase 9: Disconnect PPPoE connection unless KeepPPP is specified
  & $WriteLog ""
  & $WriteLog "Disconnecting PPPoE connection..."
  if (-not $KeepPPP) {
    if ($pppoeConnections -and $pppoeConnections.Count -gt 0) {
      Disconnect-PPP -PppoeName $pppoeConnections[0]
    } else {
      Disconnect-PPP -PppoeName $PppoeName
    }
  } else {
    & $WriteLog "Keeping PPPoE connection active (KeepPPP specified)"
  }

  return @{
    Health = $Health
    Adapter = $nic
    PPPInterface = if ($pppInterface) { $pppInterface } else { $null }
    PPPIP = if ($pppIP) { $pppIP } else { $null }
    ConnectionResult = if ($connectionResult) { $connectionResult } else { $null }
    DisabledWiFiAdapters = $disabledWiFiAdapters
  }
}

function Invoke-QuickDiagnosticWorkflow {
  param(
    [string]$PppoeName = 'PPPoE',
    [string]$UserName,
    [string]$Password,
    [string]$TargetAdapter,
    [scriptblock]$WriteLog
  )
  
  # Initialize health tracking
  $Health = New-Health
  
  # Initialize variables to prevent undefined variable errors
  $pppInterface = $null
  $pppIP = $null
  
  # Quick system checks
  & $WriteLog "=== QUICK DIAGNOSTIC WORKFLOW ==="
  
  # Basic system checks
  $basicChecks = Invoke-BasicSystemChecks -Health $Health -WriteLog $WriteLog
  
  # Handle null or malformed return from health check function
  if ($basicChecks -is [hashtable] -and $basicChecks.ContainsKey('Health')) {
    $Health = $basicChecks.Health
    $pppoeConnections = $basicChecks.PPPoEConnections
  } else {
    # Fallback if health check function returns null or malformed object
    & $WriteLog "Warning: Basic system checks returned unexpected result, using fallback values"
    $Health = Add-Health $Health 'Basic system checks' 'FAIL (unexpected result)' 1
    $pppoeConnections = @()
  }

  # Network adapter checks
  $adapterChecks = Invoke-NetworkAdapterChecks -Health $Health -TargetAdapter $TargetAdapter -WriteLog $WriteLog
  
  # Handle null or malformed return from health check function
  if ($adapterChecks -is [hashtable] -and $adapterChecks.ContainsKey('Health')) {
    $Health = $adapterChecks.Health
    $nic = $adapterChecks.Adapter
    $linkDown = $adapterChecks.LinkDown
  } else {
    # Fallback if health check function returns null or malformed object
    & $WriteLog "Warning: Network adapter checks returned unexpected result, using fallback values"
    $Health = Add-Health $Health 'Network adapter checks' 'FAIL (unexpected result)' 3
    $nic = $null
    $linkDown = $true
  }

  # Quick connectivity test if link is up
  if (-not $linkDown) {
    $connectionNameToUse = if ($pppoeConnections -and $pppoeConnections.Count -gt 0) { $pppoeConnections[0] } else { $PppoeName }
    # Set credentials file path (credentials.ps1 is in the root directory, not Modules)
    $scriptRoot = Split-Path $PSScriptRoot -Parent
    $credentialsFile = Join-Path $scriptRoot "credentials.ps1"
    
    $connectionChecks = Invoke-PPPoEConnectionChecks -Health $Health -ConnectionNameToUse $connectionNameToUse -UserName $UserName -Password $Password -CredentialsFile $credentialsFile -WriteLog $WriteLog
    
    # Handle null or malformed return from health check function
    if ($connectionChecks -is [hashtable] -and $connectionChecks.ContainsKey('Health')) {
      $Health = $connectionChecks.Health
      $authOk = $connectionChecks.AuthenticationOk
    } else {
      # Fallback if health check function returns null or malformed object
      & $WriteLog "Warning: PPPoE connection checks returned unexpected result, using fallback values"
      $Health = Add-Health $Health 'PPPoE connection checks' 'FAIL (unexpected result)' 10
      $authOk = $false
    }

    if ($authOk) {
      $pppChecks = Invoke-PPPInterfaceChecks -Health $Health -ConnectionNameToUse $connectionNameToUse -WriteLog $WriteLog
      
      # Handle null or malformed return from health check function
      if ($pppChecks -is [hashtable] -and $pppChecks.ContainsKey('Health')) {
        $Health = $pppChecks.Health
        $pppInterface = $pppChecks.PPPInterface
        $pppIP = $pppChecks.PPPIP
      } else {
        # Fallback if health check function returns null or malformed object
        & $WriteLog "Warning: PPP interface checks returned unexpected result, using fallback values"
        $Health = Add-Health $Health 'PPP interface checks' 'FAIL (unexpected result)' 13
        $pppInterface = $null
        $pppIP = $null
      }

      if ($pppIP) {
        # Quick connectivity test
        $ok11 = Test-PingHost -TargetName '1.1.1.1' -Count 2 -TimeoutMs 1000 -Source $pppIP.IPAddress
        $Health = Add-Health $Health 'Quick ping test' ($ok11 ? 'OK' : 'FAIL') 99
      }
    }
  }

  return @{
    Health = $Health
    Adapter = $nic
    PPPInterface = if ($pppInterface) { $pppInterface } else { $null }
    PPPIP = if ($pppIP) { $pppIP } else { $null }
  }
}

function Invoke-EnhancedConnectivityDiagnostics {
  <#
  .SYNOPSIS
  Runs enhanced connectivity diagnostics to detect specific network issues
  .DESCRIPTION
  Performs optimized versions of advanced tests to detect:
  - TCP connection reset patterns and 4.1-second drops
  - Port exhaustion and CGNAT limits
  - Bandwidth consistency and rate limiting
  - Packet capture during failures
  - Time-based performance patterns
  #>
  param(
    [hashtable]$Health,
    [scriptblock]$WriteLog
  )
  
  try {
    # Import required modules
    Import-Module "$PSScriptRoot/PPPoE.Net.SmartTests.psm1" -Force
    Import-Module "$PSScriptRoot/PPPoE.Net.Diagnostics.psm1" -Force
    Import-Module "$PSScriptRoot/PPPoE.Net.Connectivity.psm1" -Force
    
    # Test 1: TCP Connection Reset Detection (15 seconds)
    & $WriteLog "Test 1/5: TCP Connection Reset Detection..."
    & $WriteLog "This test will take about 15 seconds to complete"
    $tcpResult = Test-TCPConnectionResetDetectionQuick -TestHost 'netflix.com' -TestPort 443 -WriteLog $WriteLog
    $tcpStatus = if ($tcpResult.FourSecondDrops -gt 0) { 'FAIL (4s drops detected)' } else { 'OK' }
    $Health = Add-Health $Health 'TCP Reset Detection' $tcpStatus 50
    
    # Test 2: Port Exhaustion Detection (15 seconds)
    & $WriteLog "Test 2/5: Port Exhaustion Detection..."
    & $WriteLog "This test will take about 15 seconds to complete"
    $portResult = Test-PortExhaustionDetectionQuick -WriteLog $WriteLog
    $portStatus = if ($portResult.Diagnosis -eq 'PORT_EXHAUSTION_LIKELY') { 'FAIL (port limits detected)' } else { 'OK' }
    $Health = Add-Health $Health 'Port Exhaustion Test' $portStatus 51
    
    # Test 3: Bandwidth Consistency Analysis (30 seconds)
    & $WriteLog "Test 3/5: Bandwidth Consistency Analysis..."
    & $WriteLog "This test will take about 30 seconds to complete"
    $bandwidthResult = Test-BandwidthConsistencyAnalysisQuick -WriteLog $WriteLog
    $bandwidthStatus = if ($bandwidthResult.Diagnosis -eq 'HIGH_SPEED_VARIATION') { 'FAIL (rate limiting detected)' } else { 'OK' }
    $Health = Add-Health $Health 'Bandwidth Consistency' $bandwidthStatus 52
    
    # Test 4: Packet Capture During Failures (20 seconds)
    & $WriteLog "Test 4/5: Packet Capture During Failures..."
    & $WriteLog "This test will take about 20 seconds to complete"
    $packetResult = Test-PacketCaptureDuringFailuresQuick -TestHost 'netflix.com' -TestPort 443 -WriteLog $WriteLog
    $packetStatus = if ($packetResult.Diagnosis -eq 'CONNECTION_FAILURES_CAPTURED') { 'FAIL (failures captured)' } else { 'OK' }
    $Health = Add-Health $Health 'Packet Capture Test' $packetStatus 53
    
    # Test 5: Time-Based Pattern Analysis (5 minutes)
    & $WriteLog "Test 5/5: Time-Based Pattern Analysis..."
    & $WriteLog "This test will take about 5 minutes to complete - please wait"
    $timeResult = Test-TimeBasedPatternAnalysisQuick -WriteLog $WriteLog
    $timeStatus = if ($timeResult.Diagnosis -eq 'SEVERE_DEGRADATION') { 'FAIL (degradation detected)' } else { 'OK' }
    $Health = Add-Health $Health 'Time-Based Patterns' $timeStatus 54
    
    # Generate enhanced diagnosis summary
    & $WriteLog ""
    & $WriteLog "=== ENHANCED DIAGNOSTIC SUMMARY ==="
    
    $issues = @()
    if ($tcpResult.FourSecondDrops -gt 0) {
      $issues += "4.1-second connection drops detected ($($tcpResult.FourSecondRate)%)"
    }
    if ($portResult.Diagnosis -eq 'PORT_EXHAUSTION_LIKELY') {
      $issues += "Port exhaustion detected ($($portResult.TimeoutRate)% timeouts)"
    }
    if ($bandwidthResult.Diagnosis -eq 'HIGH_SPEED_VARIATION') {
      $issues += "Bandwidth inconsistency detected ($($bandwidthResult.SpeedVariationPercent)% variation)"
    }
    if ($packetResult.Diagnosis -eq 'CONNECTION_FAILURES_CAPTURED') {
      $issues += "Connection failures captured ($($packetResult.ConnectionFailures) failures)"
    }
    if ($timeResult.Diagnosis -eq 'SEVERE_DEGRADATION') {
      $issues += "Performance degradation over time ($($timeResult.OverallHealth)% health)"
    }
    
    if ($issues.Count -gt 0) {
      & $WriteLog "*** ENHANCED DIAGNOSTICS DETECTED ISSUES ***"
      foreach ($issue in $issues) {
        & $WriteLog "  - $issue"
      }
      
      # Provide specific recommendations
      & $WriteLog ""
      & $WriteLog "RECOMMENDATIONS:"
      if ($tcpResult.FourSecondDrops -gt 0) {
        & $WriteLog "  - 4.1s drops: Check CGNAT timeout settings or ISP rate limiting"
      }
      if ($portResult.Diagnosis -eq 'PORT_EXHAUSTION_LIKELY') {
        & $WriteLog "  - Port exhaustion: Reduce concurrent connections or contact ISP"
      }
      if ($bandwidthResult.Diagnosis -eq 'HIGH_SPEED_VARIATION') {
        & $WriteLog "  - Bandwidth issues: Check for ISP throttling or network congestion"
      }
      if ($packetResult.Diagnosis -eq 'CONNECTION_FAILURES_CAPTURED') {
        & $WriteLog "  - Connection failures: Analyze packet capture file for root cause"
      }
      if ($timeResult.Diagnosis -eq 'SEVERE_DEGRADATION') {
        & $WriteLog "  - Time-based issues: Check for evening congestion or progressive problems"
      }
    } else {
      & $WriteLog "Enhanced diagnostics found no specific issues"
      & $WriteLog "Network appears to be functioning normally"
    }
    
    return $Health
    
  } catch {
    & $WriteLog "Enhanced connectivity diagnostics failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'Enhanced Diagnostics' 'FAIL (test error)' 55
    return $Health
  }
}

function Invoke-AdvancedStreamingDiagnostics {
  param(
    [hashtable]$Health,
    [scriptblock]$WriteLog
  )
  
  & $WriteLog "Running advanced streaming diagnostics to identify specific issues..."
  & $WriteLog "These tests are designed to pinpoint the root cause of streaming problems"
  
  # Test 1: IPv6 Fallback Delay Test (Highest Priority)
  & $WriteLog ""
  & $WriteLog "--- Test 1: IPv6 Fallback Delay Test ---"
  try {
    $ipv6Result = Test-IPv6FallbackDelay -WriteLog $WriteLog
    $Health = Add-Health $Health 'IPv6 Fallback Delay Test' ($ipv6Result.Diagnosis) 101
  } catch {
    & $WriteLog "IPv6 Fallback Delay Test failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'IPv6 Fallback Delay Test' 'ERROR' 101
  }
  
  # Test 2: Connection Establishment Speed Test
  & $WriteLog ""
  & $WriteLog "--- Test 2: Connection Establishment Speed Test ---"
  try {
    $connectionSpeedResult = Test-ConnectionEstablishmentSpeed -WriteLog $WriteLog
    $Health = Add-Health $Health 'Connection Establishment Speed' ($connectionSpeedResult.Diagnosis) 102
  } catch {
    & $WriteLog "Connection Establishment Speed Test failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'Connection Establishment Speed' 'ERROR' 102
  }
  
  # Test 3: CGNAT Connection Capacity Test
  & $WriteLog ""
  & $WriteLog "--- Test 3: CGNAT Connection Capacity Test ---"
  try {
    $cgnatResult = Test-CGNATConnectionCapacity -WriteLog $WriteLog
    $Health = Add-Health $Health 'CGNAT Connection Capacity' ($cgnatResult.Diagnosis) 103
  } catch {
    & $WriteLog "CGNAT Connection Capacity Test failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'CGNAT Connection Capacity' 'ERROR' 103
  }
  
  # Test 4: ICMP Rate Limiting Detection
  & $WriteLog ""
  & $WriteLog "--- Test 4: ICMP Rate Limiting Detection ---"
  try {
    $icmpRateLimitResult = Test-ICMPRateLimiting -WriteLog $WriteLog
    $Health = Add-Health $Health 'ICMP Rate Limiting Detection' ($icmpRateLimitResult.Diagnosis) 104
  } catch {
    & $WriteLog "ICMP Rate Limiting Detection Test failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'ICMP Rate Limiting Detection' 'ERROR' 104
  }
  
  # Test 5: Streaming Service DNS & TCP Test
  & $WriteLog ""
  & $WriteLog "--- Test 5: Streaming Service DNS & TCP Test ---"
  try {
    $streamingServiceResult = Test-StreamingServiceDNSAndTCP -WriteLog $WriteLog
    $Health = Add-Health $Health 'Streaming Service Connectivity' ($streamingServiceResult.Diagnosis) 105
  } catch {
    & $WriteLog "Streaming Service DNS & TCP Test failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'Streaming Service Connectivity' 'ERROR' 105
  }
  
  # Test 6: DNS Server Performance Test
  & $WriteLog ""
  & $WriteLog "--- Test 6: DNS Server Performance Test ---"
  try {
    $dnsPerformanceResult = Test-DNSServerPerformance -WriteLog $WriteLog
    $Health = Add-Health $Health 'DNS Server Performance' ($dnsPerformanceResult.Diagnosis) 106
  } catch {
    & $WriteLog "DNS Server Performance Test failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'DNS Server Performance' 'ERROR' 106
  }
  
  # Test 7: Sustained Connection Test
  & $WriteLog ""
  & $WriteLog "--- Test 7: Sustained Connection Test ---"
  try {
    $sustainedConnectionResult = Test-SustainedConnection -WriteLog $WriteLog
    $Health = Add-Health $Health 'Sustained Connection Stability' ($sustainedConnectionResult.Diagnosis) 107
  } catch {
    & $WriteLog "Sustained Connection Test failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'Sustained Connection Stability' 'ERROR' 107
  }
  
  # Test 8: IPv6 Interference Check
  & $WriteLog ""
  & $WriteLog "--- Test 8: IPv6 Interference Check ---"
  try {
    $ipv6InterferenceResult = Test-IPv6Interference -WriteLog $WriteLog
    $Health = Add-Health $Health 'IPv6 Interference Check' ($ipv6InterferenceResult.Diagnosis) 108
  } catch {
    & $WriteLog "IPv6 Interference Check failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'IPv6 Interference Check' 'ERROR' 108
  }
  
  # Test 9: Large Packet Handling Test
  & $WriteLog ""
  & $WriteLog "--- Test 9: Large Packet Handling Test ---"
  try {
    $largePacketResult = Test-LargePacketHandling -WriteLog $WriteLog
    $Health = Add-Health $Health 'Large Packet Handling' ($largePacketResult.Diagnosis) 109
  } catch {
    & $WriteLog "Large Packet Handling Test failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'Large Packet Handling' 'ERROR' 109
  }
  
  # Test 10: Default Route Verification
  & $WriteLog ""
  & $WriteLog "--- Test 10: Default Route Verification ---"
  try {
    $defaultRouteResult = Test-DefaultRouteVerification -WriteLog $WriteLog
    $Health = Add-Health $Health 'Default Route Verification' ($defaultRouteResult.Diagnosis) 110
  } catch {
    & $WriteLog "Default Route Verification failed: $($_.Exception.Message)"
    $Health = Add-Health $Health 'Default Route Verification' 'ERROR' 110
  }
  
  # Summary and Recommendations
  & $WriteLog ""
  & $WriteLog "=== ADVANCED STREAMING DIAGNOSTICS SUMMARY ==="
  
  # Count issues by severity
  $criticalIssues = @()
  $moderateIssues = @()
  $minorIssues = @()
  
  # Analyze results and categorize issues
  $healthItems = $Health.GetEnumerator() | Where-Object { $_.Key -match 'Test|Detection|Connectivity|Performance|Stability|Check|Verification' -and $_.Value -ne 'OK' -and $_.Value -ne 'ERROR' }
  
  foreach ($item in $healthItems) {
    $diagnosis = $item.Value
    if ($diagnosis -match 'SEVERE|MAJOR|ALL_SERVICES_FAILED|SIGNIFICANT_DELAYS|FRAGMENTATION_ISSUES') {
      $criticalIssues += "$($item.Key): $diagnosis"
    } elseif ($diagnosis -match 'MODERATE|SOME_ISSUES|DNS_PERFORMANCE_ISSUES|MULTIPLE_SERVICE_ISSUES|BURST_RATE_LIMITED') {
      $moderateIssues += "$($item.Key): $diagnosis"
    } elseif ($diagnosis -match 'SLOW|ACCEPTABLE|NO_LIMITS|GOOD|OK') {
      $minorIssues += "$($item.Key): $diagnosis"
    }
  }
  
  & $WriteLog "Issue Summary:"
  & $WriteLog "  Critical Issues: $($criticalIssues.Count)"
  & $WriteLog "  Moderate Issues: $($moderateIssues.Count)"
  & $WriteLog "  Minor Issues: $($minorIssues.Count)"
  
  if ($criticalIssues.Count -gt 0) {
    & $WriteLog "Critical Issues Found:"
    foreach ($issue in $criticalIssues) {
      & $WriteLog "  - $issue"
    }
  }
  
  if ($moderateIssues.Count -gt 0) {
    & $WriteLog "Moderate Issues Found:"
    foreach ($issue in $moderateIssues) {
      & $WriteLog "  - $issue"
    }
  }
  
  # Provide prioritized recommendations
  & $WriteLog ""
  & $WriteLog "=== PRIORITIZED RECOMMENDATIONS ==="
  
  if ($criticalIssues.Count -gt 0) {
    & $WriteLog "IMMEDIATE ACTIONS REQUIRED:"
    if ($criticalIssues -match 'IPv6') {
      & $WriteLog "  1. Disable IPv6 on PPPoE interface - this is likely causing connection delays"
      & $WriteLog "     Command: netsh interface ipv6 set interface \"PPPoE Interface Name\" disable"
    }
    if ($criticalIssues -match 'CGNAT|Connection Capacity') {
      & $WriteLog "  2. Contact ISP about CGNAT connection limits - request static IP if needed"
    }
    if ($criticalIssues -match 'DNS|Streaming Service') {
      & $WriteLog "  3. Change DNS servers to 1.1.1.1 and 8.8.8.8 for better performance"
    }
  }
  
  if ($moderateIssues.Count -gt 0) {
    & $WriteLog "RECOMMENDED ACTIONS:"
    if ($moderateIssues -match 'ICMP|Rate Limiting') {
      & $WriteLog "  1. Monitor for MTU-related issues during streaming"
    }
    if ($moderateIssues -match 'Connection Speed|Establishment') {
      & $WriteLog "  2. Increase application timeout settings"
    }
  }
  
  if ($criticalIssues.Count -eq 0 -and $moderateIssues.Count -eq 0) {
    & $WriteLog "NO MAJOR ISSUES DETECTED:"
    & $WriteLog "  Advanced diagnostics show no significant problems with your connection."
    & $WriteLog "  If streaming issues persist, they may be related to:"
    & $WriteLog "  - Application-specific problems"
    & $WriteLog "  - ISP throttling or content filtering"
    & $WriteLog "  - Router/firewall configuration"
    & $WriteLog "  - Local network congestion"
  }
  
  return $Health
}

Export-ModuleMember -Function *
