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
    
    # Set credentials file path
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $credentialsFile = Join-Path $here "credentials.ps1"
    
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
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $credentialsFile = Join-Path $here "credentials.ps1"
    
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

Export-ModuleMember -Function *
