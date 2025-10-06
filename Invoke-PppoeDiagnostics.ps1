# Invoke-PppoeDiagnostics.ps1 - Main entry point for PPPoE diagnostics

#Requires -Version 7.0

param(
  [string]$PppoeName = 'PPPoE',
  [string]$UserName,
  [string]$Password,  # Note: Using string for compatibility with rasdial command
  [string]$TargetAdapter,
  [switch]$FullLog,
  [switch]$SkipWifiToggle,
  [switch]$KeepPPP,
  [ValidateSet('Quick','Standard','ISPEvidence')][string]$Profile = 'Standard',
  [ValidateSet('On','Evidence')][string]$Privacy = 'On'
)

#Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import all required modules
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here/Modules/PPPoE.Core.psm1" -Force
Import-Module "$here/Modules/PPPoE.Net.psm1" -Force
Import-Module "$here/Modules/PPPoE.Net.SmartTests.psm1" -Force
Import-Module "$here/Modules/PPPoE.Logging.psm1" -Force
Import-Module "$here/Modules/PPPoE.Health.psm1" -Force
Import-Module "$here/Modules/PPPoE.HealthChecks.psm1" -Force
Import-Module "$here/Modules/PPPoE.Workflows.psm1" -Force
Import-Module "$here/Modules/PPPoE.Credentials.psm1" -Force
Import-Module "$here/Modules/PPPoE.Configuration.psm1" -Force
Import-Module "$here/Modules/PPPoE.Utilities.psm1" -Force

# Initialize logging
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $here "logs/pppoe_transcript_$ts.txt"

# Initialize cleanup tracking
$disabledWiFiAdapters = @()
$cleanupRequired = $false

try {
  Start-AsciiTranscript -Path $logPath
  Show-Banner
  Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"
  Write-Log "Script path: $($MyInvocation.MyCommand.Path)"
  Set-PrivacyMode -Mode $Privacy
  Write-Log "Parameters: PppoeName=$PppoeName, TargetAdapter=$TargetAdapter, FullLog=$FullLog, SkipWifiToggle=$SkipWifiToggle, KeepPPP=$KeepPPP, Profile=$Profile, Privacy=$Privacy"

  # Show available credential sources
  Show-CredentialSources -WriteLog ${function:Write-Log}

  # Validate provided credentials if any
  if (Test-CredentialsProvided -UserName $UserName -Password $Password) {
    $validation = Test-CredentialsFormat -UserName $UserName -Password $Password
    if (-not $validation.IsValid) {
      Write-Warn "Credential validation issues found:"
      foreach ($issue in $validation.Issues) {
        Write-Warn "  - $issue"
      }
  } else {
      Write-Ok "Provided credentials passed validation"
    }
  }

  # Execute the main diagnostic workflow
  $result = Invoke-PPPoEDiagnosticWorkflow -PppoeName $PppoeName -UserName $UserName -Password $Password -TargetAdapter $TargetAdapter -FullLog:$FullLog -SkipWifiToggle:$SkipWifiToggle -KeepPPP:$KeepPPP -WriteLog ${function:Write-Log} -Profile $Profile

  # Store cleanup information from workflow
  if ($result -and $result.DisabledWiFiAdapters) {
    $disabledWiFiAdapters = $result.DisabledWiFiAdapters
    $cleanupRequired = $true
  }

  # Display final results summary
  Write-Log ""
  Write-Log "=== FINAL HEALTH SUMMARY ==="
  if ($result) {
    Write-HealthSummary -Health $result.Health
    Write-Log ""
    Write-Log "=== DIAGNOSTIC COMPLETED ==="
    Write-Log "Health checks completed: $($result.Health.Count) total"
    Write-Log "Selected adapter: $($result.Adapter.Name)"
    if ($result.PPPInterface) {
      Write-Log "PPP interface: $($result.PPPInterface.InterfaceAlias)"
    }
    if ($result.PPPIP) { Write-Log ("PPP IP address: {0}" -f (Describe-IPv4ForLog $result.PPPIP.IPAddress)) }
  } else {
    Write-Log "Diagnostic failed - no results available"
  }

} catch {
  Write-Err "Fatal error during diagnostics: $($_.Exception.Message)"
  Write-Log "Stack trace: $($_.ScriptStackTrace)"
  
  # Try to get cleanup information even if workflow failed
  try {
    if (-not $SkipWifiToggle) {
      Write-Log "Attempting to identify disabled WiFi adapters for cleanup..."
      $disabledWiFiAdapters = Get-DisabledWiFiAdapters
      if ($disabledWiFiAdapters -and $disabledWiFiAdapters.Count -gt 0) {
        $cleanupRequired = $true
        Write-Log "Found $($disabledWiFiAdapters.Count) disabled WiFi adapters that may need re-enabling"
      }
    }
  } catch {
    Write-Log "Could not determine WiFi adapter cleanup requirements"
  }
  
  # Show a minimal health summary even if diagnostics failed
  Write-Log ""
  Write-Log "=== FINAL HEALTH SUMMARY ==="
  Write-Log "[1] PowerShell version .......... OK ($($PSVersionTable.PSVersion))"
  Write-Log "[2] Diagnostic execution ........ FAIL (fatal error occurred)"
  Write-Log "OVERALL: FAIL"
} finally {
  # Always perform cleanup operations
  Write-Log ""
  Write-Log "=== CLEANUP OPERATIONS ==="
  
  # Try specific cleanup first if we have the list
  if ($cleanupRequired -and $disabledWiFiAdapters -and $disabledWiFiAdapters.Count -gt 0) {
    Write-Log "Re-enabling specific WiFi adapters that were temporarily disabled..."
    try {
      Enable-WiFiAdapters -AdapterNames $disabledWiFiAdapters -WriteLog ${function:Write-Log}
      Write-Log "Successfully re-enabled $($disabledWiFiAdapters.Count) WiFi adapter(s)"
    } catch {
      Write-Err "Failed to re-enable specific WiFi adapters: $($_.Exception.Message)"
      Write-Log "Attempting fallback cleanup..."
      # Fallback to general cleanup
      $enabledCount = Enable-AllDisabledWiFiAdapters -WriteLog ${function:Write-Log}
      if ($enabledCount -gt 0) {
        Write-Log "Fallback cleanup re-enabled $enabledCount WiFi adapter(s)"
      }
    }
  } else {
    # General cleanup - check for any disabled WiFi adapters
    Write-Log "Checking for any disabled WiFi adapters that need re-enabling..."
    $enabledCount = Enable-AllDisabledWiFiAdapters -WriteLog ${function:Write-Log}
    if ($enabledCount -gt 0) {
      Write-Log "Cleanup re-enabled $enabledCount WiFi adapter(s)"
    } else {
      Write-Log "No disabled WiFi adapters found"
    }
  }
  
  # Stop transcript
  try {
    if ($Host.Name -eq 'ConsoleHost' -and $Host.UI.RawUI) {
      Stop-Transcript -ErrorAction SilentlyContinue
    }
    Write-Log "Transcript saved to: $logPath"
    } catch {
    # Ignore transcript stopping errors
    }

  # Final cleanup message
  if ($cleanupRequired) {
    Write-Log ""
    Write-Log "=== CLEANUP COMPLETED ==="
  }
}