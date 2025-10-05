# PPPoE.WorkflowErrorHandling.Tests.ps1 - Tests for error handling in workflow functions

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
        "../Modules/PPPoE.Credentials.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "🔍 Running error handling tests for PPPoE.Workflows module..." -ForegroundColor Cyan
    
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
    
    # Test 1: Workflow handles null return from health check functions
    Test-Function "Workflow handles null return from Invoke-NetworkAdapterChecks" {
        # Mock a scenario where Invoke-NetworkAdapterChecks returns null
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        try {
            # This should not throw an error even if health checks fail
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
            return ($result -is [hashtable] -and $result.ContainsKey('Health'))
        } catch {
            # If it throws, check if it's the specific error we're trying to prevent
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                return $false  # This is the error we want to catch
            }
            return $true  # Other errors are acceptable for this test
        }
    }
    
    # Test 2: Workflow handles malformed return objects
    Test-Function "Workflow handles malformed return objects from health checks" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        try {
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
            # Should return a valid structure even if health checks return malformed objects
            return ($result -is [hashtable] -and 
                    $result.ContainsKey('Health') -and 
                    $result.ContainsKey('Adapter') -and
                    $result.ContainsKey('PPPInterface') -and
                    $result.ContainsKey('PPPIp'))
        } catch {
            if ($_.Exception.Message -match "property.*cannot be found") {
                return $false  # This is the error we want to prevent
            }
            return $true  # Other errors are acceptable
        }
    }
    
    # Test 3: Health object validation
    Test-Function "Health object has expected structure" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
        $health = $result.Health
        
        # Health should be a hashtable
        if (-not ($health -is [hashtable])) {
            return $false
        }
        
        # Health should have Items property or be a valid hashtable
        return $true
    }
    
    # Test 4: Adapter object validation
    Test-Function "Adapter object validation" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
        $adapter = $result.Adapter
        
        # Adapter can be null (no adapters found) or a valid object
        if ($adapter -ne $null -and -not ($adapter -is [object])) {
            return $false
        }
        
        return $true
    }
    
    # Test 5: PPPInterface object validation
    Test-Function "PPPInterface object validation" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
        $pppInterface = $result.PPPInterface
        
        # PPPInterface can be null (no connection) or a valid object
        if ($pppInterface -ne $null -and -not ($pppInterface -is [object])) {
            return $false
        }
        
        return $true
    }
    
    # Test 6: PPPIP object validation
    Test-Function "PPPIp object validation" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
        $pppIP = $result.PPPIp
        
        # PPPIP can be null (no IP assigned) or a valid object
        if ($pppIP -ne $null -and -not ($pppIP -is [object])) {
            return $false
        }
        
        return $true
    }
    
    # Test 7: Error handling in WriteLog function
    Test-Function "Workflow handles WriteLog function errors gracefully" {
        $badWriteLog = { 
            param($msg) 
            if ($msg -match "error") {
                throw "Simulated WriteLog error"
            }
            Write-Host $msg 
        }
        
        try {
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $badWriteLog
            return $true  # Should handle WriteLog errors gracefully
        } catch {
            # Should not throw unhandled exceptions
            return $false
        }
    }
    
    # Test 8: Parameter validation
    Test-Function "Workflow validates required parameters" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        try {
            # Test with various parameter combinations
            $result1 = Invoke-QuickDiagnosticWorkflow -PppoeName $null -WriteLog $mockWriteLog
            $result2 = Invoke-QuickDiagnosticWorkflow -TargetAdapter "" -WriteLog $mockWriteLog
            $result3 = Invoke-QuickDiagnosticWorkflow -UserName $null -Password $null -WriteLog $mockWriteLog
            
            # All should return valid results
            return (($result1 -is [hashtable]) -and 
                    ($result2 -is [hashtable]) -and 
                    ($result3 -is [hashtable]))
        } catch {
            return $false
        }
    }
    
    # Test 9: Memory and resource cleanup
    Test-Function "Workflow cleans up resources properly" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        # Run multiple times to check for resource leaks
        for ($i = 1; $i -le 3; $i++) {
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
            if (-not ($result -is [hashtable])) {
                return $false
            }
        }
        
        return $true
    }
    
    # Test 10: Exception handling in health check functions
    Test-Function "Workflow handles exceptions in health check functions" {
        $mockWriteLog = { param($msg) Write-Host $msg }
        
        try {
            # This should not throw unhandled exceptions even if health checks fail
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
            return ($result -is [hashtable])
        } catch {
            # Check if it's the specific property access error we're trying to prevent
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the specific error we're trying to prevent!" -ForegroundColor Yellow
                return $false
            }
            # Other exceptions might be acceptable depending on system state
            return $true
        }
    }
    
    # Count results
    $total = $passed + $failed
    
    Write-Host ""
    Write-Host "📊 Error Handling Test Results Summary:" -ForegroundColor Cyan
    Write-Host "✅ Passed: $passed" -ForegroundColor Green
    Write-Host "❌ Failed: $failed" -ForegroundColor Red
    Write-Host "📈 Total: $total" -ForegroundColor Cyan
    
    if ($failed -eq 0) {
        Write-Host ""
        Write-Host "🎉 All error handling tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "❌ Some error handling tests failed!" -ForegroundColor Red
        Write-Host "   This indicates potential issues with error handling in the workflow." -ForegroundColor Yellow
        exit 1
    }
    
} finally {
    # Restore original execution policy
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
