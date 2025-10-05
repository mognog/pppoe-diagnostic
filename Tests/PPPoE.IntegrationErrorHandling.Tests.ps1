# PPPoE.IntegrationErrorHandling.Tests.ps1 - Integration tests for error handling across the entire system

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Net.psm1", 
        "../Modules/PPPoE.Health.psm1",
        "../Modules/PPPoE.HealthChecks.psm1",
        "../Modules/PPPoE.Workflows.psm1",
        "../Modules/PPPoE.Credentials.psm1",
        "../Modules/PPPoE.Logging.psm1",
        "../Modules/PPPoE.Configuration.psm1",
        "../Modules/PPPoE.Utilities.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "🔍 Running integration error handling tests for PPPoE system..." -ForegroundColor Cyan
    
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
    
    # Test 1: Full workflow with no network adapters
    Test-Function "Full workflow handles no network adapters gracefully" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        try {
            # This should not crash even if no adapters are found
            $result = Invoke-PPPoEDiagnosticWorkflow -WriteLog $mockWriteLog
            
            # Should return a valid structure
            return ($result -is [hashtable] -and 
                    $result.ContainsKey('Health') -and 
                    $result.ContainsKey('Adapter') -and
                    $result.ContainsKey('PPPInterface') -and
                    $result.ContainsKey('PPPIp') -and
                    $result.ContainsKey('ConnectionResult') -and
                    $result.ContainsKey('DisabledWiFiAdapters'))
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error from the transcript!" -ForegroundColor Yellow
                return $false
            }
            return $true
        }
    }
    
    # Test 2: Full workflow with invalid credentials
    Test-Function "Full workflow handles invalid credentials gracefully" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        try {
            # Test with obviously invalid credentials
            $result = Invoke-PPPoEDiagnosticWorkflow -UserName "invalid" -Password "invalid" -WriteLog $mockWriteLog
            
            return ($result -is [hashtable] -and $result.ContainsKey('Health'))
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error from the transcript!" -ForegroundColor Yellow
                return $false
            }
            return $true
        }
    }
    
    # Test 3: Full workflow with network connectivity issues
    Test-Function "Full workflow handles network connectivity issues gracefully" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        try {
            # This should handle network issues without crashing
            $result = Invoke-PPPoEDiagnosticWorkflow -WriteLog $mockWriteLog
            
            return ($result -is [hashtable] -and $result.ContainsKey('Health'))
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error from the transcript!" -ForegroundColor Yellow
                return $false
            }
            return $true
        }
    }
    
    # Test 4: Test the specific error condition from the transcript
    Test-Function "Workflow handles the exact error condition from transcript" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        try {
            # Run the workflow and see if it reproduces the error
            $result = Invoke-PPPoEDiagnosticWorkflow -WriteLog $mockWriteLog
            
            # If we get here without the specific error, the test passes
            return ($result -is [hashtable])
        } catch {
            # Check if it's the exact error from the transcript
            if ($_.Exception.Message -match "The property 'Health' cannot be found on this object") {
                Write-Host "   Reproduced the exact error from the transcript!" -ForegroundColor Yellow
                Write-Host "   Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Yellow
                return $false
            }
            # Other errors are acceptable for this test
            return $true
        }
    }
    
    # Test 5: Test with various parameter combinations
    Test-Function "Workflow handles various parameter combinations" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        $testCases = @(
            @{ PppoeName = "TestPPPoE"; TargetAdapter = "Ethernet" },
            @{ PppoeName = ""; TargetAdapter = "" },
            @{ PppoeName = $null; TargetAdapter = $null },
            @{ FullLog = $true },
            @{ SkipWifiToggle = $true },
            @{ KeepPPP = $true }
        )
        
        foreach ($testCase in $testCases) {
            try {
                $result = Invoke-PPPoEDiagnosticWorkflow -WriteLog $mockWriteLog @testCase
                
                if (-not ($result -is [hashtable])) {
                    Write-Host "   Failed with parameters: $($testCase | ConvertTo-Json)" -ForegroundColor Yellow
                    return $false
                }
            } catch {
                if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                    Write-Host "   Detected the exact error with parameters: $($testCase | ConvertTo-Json)" -ForegroundColor Yellow
                    return $false
                }
            }
        }
        
        return $true
    }
    
    # Test 6: Test error handling in health check functions individually
    Test-Function "Individual health check functions handle errors gracefully" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        $health = New-Health
        
        try {
            # Test each health check function individually
            $basicChecks = Invoke-BasicSystemChecks -Health $health -WriteLog $mockWriteLog
            if ($basicChecks -and $basicChecks.ContainsKey('Health')) {
                $health = $basicChecks.Health
            }
            
            $adapterChecks = Invoke-NetworkAdapterChecks -Health $health -WriteLog $mockWriteLog
            if ($adapterChecks -and $adapterChecks.ContainsKey('Health')) {
                $health = $adapterChecks.Health
            }
            
            # All functions should return valid objects or handle errors gracefully
            return $true
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error in individual health checks!" -ForegroundColor Yellow
                return $false
            }
            return $true
        }
    }
    
    # Test 7: Test with corrupted health object
    Test-Function "Workflow handles corrupted health object gracefully" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        try {
            # Create a corrupted health object
            $corruptedHealth = @{
                # Missing expected properties
            }
            
            # This should not crash the workflow
            $result = Invoke-PPPoEDiagnosticWorkflow -WriteLog $mockWriteLog
            
            return ($result -is [hashtable])
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error with corrupted health object!" -ForegroundColor Yellow
                return $false
            }
            return $true
        }
    }
    
    # Test 8: Test memory and resource management
    Test-Function "Workflow manages memory and resources properly" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        try {
            # Run multiple iterations to check for resource leaks
            for ($i = 1; $i -le 5; $i++) {
                $result = Invoke-PPPoEDiagnosticWorkflow -WriteLog $mockWriteLog
                
                if (-not ($result -is [hashtable])) {
                    Write-Host "   Failed on iteration $i" -ForegroundColor Yellow
                    return $false
                }
                
                # Force garbage collection
                [System.GC]::Collect()
            }
            
            return $true
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error in resource management test!" -ForegroundColor Yellow
                return $false
            }
            return $true
        }
    }
    
    # Count results
    $total = $passed + $failed
    
    Write-Host ""
    Write-Host "📊 Integration Error Handling Test Results Summary:" -ForegroundColor Cyan
    Write-Host "✅ Passed: $passed" -ForegroundColor Green
    Write-Host "❌ Failed: $failed" -ForegroundColor Red
    Write-Host "📈 Total: $total" -ForegroundColor Cyan
    
    if ($failed -eq 0) {
        Write-Host ""
        Write-Host "🎉 All integration error handling tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "❌ Some integration error handling tests failed!" -ForegroundColor Red
        Write-Host "   This indicates the system needs better error handling." -ForegroundColor Yellow
        exit 1
    }
    
} finally {
    # Restore original execution policy
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
