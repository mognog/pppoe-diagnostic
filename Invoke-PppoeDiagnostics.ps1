# Invoke-PppoeDiagnostics.ps1 - Main entry point for PPPoE diagnostics

#Requires -Version 7.0

param(
  [string]$PppoeName = 'PPPoE',
  [string]$UserName,
  [string]$Password,  # Note: Using string for compatibility with rasdial command
  [string]$TargetAdapter,
  [switch]$FullLog,
  [switch]$SkipWifiToggle,
  [switch]$KeepPPP
)

#Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import all required modules
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here/Modules/PPPoE.Core.psm1" -Force
Import-Module "$here/Modules/PPPoE.Net.psm1" -Force
Import-Module "$here/Modules/PPPoE.Logging.psm1" -Force
Import-Module "$here/Modules/PPPoE.Health.psm1" -Force
Import-Module "$here/Modules/PPPoE.HealthChecks.psm1" -Force
Import-Module "$here/Modules/PPPoE.Workflows.psm1" -Force
Import-Module "$here/Modules/PPPoE.Credentials.psm1" -Force

# Initialize logging
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $here "logs/pppoe_transcript_$ts.txt"

try {
  Start-AsciiTranscript -Path $logPath
  Show-Banner
  Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"
  Write-Log "Script path: $($MyInvocation.MyCommand.Path)"
  Write-Log "Parameters: PppoeName=$PppoeName, TargetAdapter=$TargetAdapter, FullLog=$FullLog, SkipWifiToggle=$SkipWifiToggle, KeepPPP=$KeepPPP"

  # Show available credential sources
  Show-CredentialSources -WriteLog ${function:Write-Log}

  # Validate provided credentials if any
  if (Test-CredentialsProvided -UserName $UserName -Password $Password) {
    $validation = Validate-CredentialsFormat -UserName $UserName -Password $Password
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
  $result = Invoke-PPPoEDiagnosticWorkflow -PppoeName $PppoeName -UserName $UserName -Password $Password -TargetAdapter $TargetAdapter -FullLog:$FullLog -SkipWifiToggle:$SkipWifiToggle -KeepPPP:$KeepPPP -WriteLog ${function:Write-Log}

  # Display final results summary
  Write-Log ""
  Write-Log "=== DIAGNOSTIC COMPLETED ==="
  Write-Log "Health checks completed: $($result.Health.Count) total"
  Write-Log "Selected adapter: $($result.Adapter.Name)"
  if ($result.PPPInterface) {
    Write-Log "PPP interface: $($result.PPPInterface.InterfaceAlias)"
  }
  if ($result.PPPIP) {
    Write-Log "PPP IP address: $($result.PPPIP.IPAddress)"
  }
  if ($result.DisabledWiFiAdapters.Count -gt 0) {
    Write-Log "WiFi adapters re-enabled: $($result.DisabledWiFiAdapters.Count)"
  }

} catch {
  Write-Err "Fatal error during diagnostics: $($_.Exception.Message)"
  Write-Log "Stack trace: $($_.ScriptStackTrace)"
  exit 1
} finally {
  Stop-Transcript
  Write-Log "Transcript saved to: $logPath"
}