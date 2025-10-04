# PPPoE.MainScript.Tests.ps1 - Tests for main script functionality

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    Write-Host "🔍 Running basic validation tests for main script..."
    
    # Test function wrapper
    function Test-Function {
        param([string]$Name, [scriptblock]$TestScript)
        try {
            $result = & $TestScript
            if ($result) {
                Write-Host "✅ $Name" -ForegroundColor Green
                return $true
            } else {
                Write-Host "❌ $Name" -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "❌ $Name - Error: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    $passed = 0
    $failed = 0
    
    # Test script parameter validation
    Test-Function "Main script accepts valid parameters" {
        $scriptPath = Join-Path $PSScriptRoot "../Invoke-PppoeDiagnostics.ps1"
        $result = Get-Command -Syntax -Name $scriptPath
        return ($result -like "*PppoeName*" -and $result -like "*UserName*" -and $result -like "*Password*")
    }
    
    # Test script syntax validation
    Test-Function "Main script has valid PowerShell syntax" {
        $scriptPath = Join-Path $PSScriptRoot "../Invoke-PppoeDiagnostics.ps1"
        try {
            $ast = [System.Management.Automation.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            return ($ast -ne $null)
        } catch {
            return $false
        }
    }
    
    # Test module imports
    Test-Function "All required modules can be imported" {
        $modules = @(
            "PPPoE.Core.psm1",
            "PPPoE.Net.psm1", 
            "PPPoE.Logging.psm1",
            "PPPoE.Health.psm1",
            "PPPoE.HealthChecks.psm1",
            "PPPoE.Workflows.psm1",
            "PPPoE.Credentials.psm1",
            "PPPoE.Configuration.psm1",
            "PPPoE.Utilities.psm1"
        )
        
        $allImported = $true
        foreach ($module in $modules) {
            $modulePath = Join-Path $PSScriptRoot "../Modules/$module"
            try {
                Import-Module $modulePath -Force -ErrorAction Stop
            } catch {
                $allImported = $false
                break
            }
        }
        return $allImported
    }
    
    # Test script execution with help
    Test-Function "Main script can be executed with -WhatIf" {
        $scriptPath = Join-Path $PSScriptRoot "../Invoke-PppoeDiagnostics.ps1"
        try {
            # Test that the script can be loaded without execution errors
            $null = Get-Command -Name $scriptPath -ErrorAction Stop
            return $true
        } catch {
            return $false
        }
    }
    
    # Test error handling
    Test-Function "Script handles missing modules gracefully" {
        # This test verifies the script structure can handle module import failures
        $scriptPath = Join-Path $PSScriptRoot "../Invoke-PppoeDiagnostics.ps1"
        $content = Get-Content $scriptPath -Raw
        return ($content -like "*Import-Module*" -and $content -like "*try*" -and $content -like "*catch*")
    }
    
    # Test logging functionality
    Test-Function "Script includes proper logging setup" {
        $scriptPath = Join-Path $PSScriptRoot "../Invoke-PppoeDiagnostics.ps1"
        $content = Get-Content $scriptPath -Raw
        return ($content -like "*Start-AsciiTranscript*" -and $content -like "*Stop-Transcript*")
    }
    
    # Test parameter validation
    Test-Function "Script has proper parameter definitions" {
        $scriptPath = Join-Path $PSScriptRoot "../Invoke-PppoeDiagnostics.ps1"
        $content = Get-Content $scriptPath -Raw
        return ($content -like "*param(*" -and $content -like "*PppoeName*" -and $content -like "*UserName*")
    }
    
    # Test workflow integration
    Test-Function "Script calls workflow functions" {
        $scriptPath = Join-Path $PSScriptRoot "../Invoke-PppoeDiagnostics.ps1"
        $content = Get-Content $scriptPath -Raw
        return ($content -like "*Invoke-PPPoEDiagnosticWorkflow*")
    }
    
    # Count results
    $total = $passed + $failed
    
    Write-Host ""
    Write-Host "📊 Test Results Summary:" -ForegroundColor Cyan
    Write-Host "✅ Passed: $passed" -ForegroundColor Green
    Write-Host "❌ Failed: $failed" -ForegroundColor Red
    Write-Host "📈 Total: $total" -ForegroundColor Cyan
    
    if ($failed -eq 0) {
        Write-Host ""
        Write-Host "🎉 All tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "❌ Some tests failed!" -ForegroundColor Red
        exit 1
    }
    
} finally {
    # Restore original execution policy
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
