# PPPoE.ScriptError.Tests.ps1 - Test to reproduce the script error from the log

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Health.psm1",
        "../Modules/PPPoE.Net.Adapters.psm1",
        "../Modules/PPPoE.Net.Diagnostics.psm1",
        "../Modules/PPPoE.HealthChecks.psm1",
        "../Modules/PPPoE.Workflows.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "Testing script error reproduction..."
    
    # Test function wrapper
    function Test-Function {
        param([string]$Name, [scriptblock]$TestScript)
        try {
            $result = & $TestScript
            if ($result) {
                Write-Host "PASS: $Name" -ForegroundColor Green
                return $true
            } else {
                Write-Host "FAIL: $Name" -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "FAIL: $Name - Error: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    $passed = 0
    $failed = 0
    
    # Test 1: Invoke-NetworkAdapterChecks returns proper structure
    if (Test-Function "Invoke-NetworkAdapterChecks returns proper structure" {
        $health = @{}
        $result = Invoke-NetworkAdapterChecks -Health $health -TargetAdapter "Ethernet" -WriteLog { param($msg) Write-Host $msg }
        
        # Check if result has required properties
        return ($result -is [hashtable] -and 
                $result.ContainsKey('Health') -and 
                $result.ContainsKey('Adapter') -and 
                $result.ContainsKey('LinkDown'))
    }) { $passed++ } else { $failed++ }
    
    # Test 2: Test-ONTAvailability returns proper structure
    if (Test-Function "Test-ONTAvailability returns proper structure" {
        $result = Test-ONTAvailability -WriteLog { param($msg) Write-Host $msg }
        
        # Check if result has required properties
        return ($result -is [hashtable] -and 
                $result.ContainsKey('Status') -and 
                $result.ContainsKey('ReachableONTs') -and 
                $result.ContainsKey('AllResults'))
    }) { $passed++ } else { $failed++ }
    
    # Test 3: Show-ONTLEDReminder handles null WriteLog
    if (Test-Function "Show-ONTLEDReminder handles null WriteLog" {
        # This should not throw an error
        try {
            Show-ONTLEDReminder -WriteLog $null
            return $true
        } catch {
            return $false
        }
    }) { $passed++ } else { $failed++ }
    
    # Test 4: Workflow handles ONT LED check gracefully
    if (Test-Function "Workflow handles ONT LED check gracefully" {
        # Mock the workflow call that was failing
        try {
            $health = @{}
            $result = Invoke-NetworkAdapterChecks -Health $health -TargetAdapter "Ethernet" -WriteLog { param($msg) Write-Host $msg }
            
            # This should not throw "The property 'Health' cannot be found"
            if ($result.Health) {
                return $true
            } else {
                return $false
            }
        } catch {
            Write-Host "Error: $($_.Exception.Message)"
            return $false
        }
    }) { $passed++ } else { $failed++ }
    
    # Summary
    Write-Host ""
    Write-Host "Script Error Test Results:"
    Write-Host "=========================="
    Write-Host "Passed: $passed"
    Write-Host "Failed: $failed"
    Write-Host "Total: $($passed + $failed)"
    
    if ($failed -eq 0) {
        Write-Host ""
        Write-Host "All script error tests passed!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Some script error tests failed!" -ForegroundColor Red
        Write-Host "These tests help identify the source of the workflow error." -ForegroundColor Yellow
    }
    
} finally {
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
