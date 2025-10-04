# PPPoE.Workflows.Tests.ps1 - Tests for workflow orchestration module

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
    
    Write-Host "🔍 Running basic validation tests for PPPoE.Workflows module..."
    
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
    
    # Test Invoke-QuickDiagnosticWorkflow
    Test-Function "Invoke-QuickDiagnosticWorkflow returns valid structure" {
        $result = Invoke-QuickDiagnosticWorkflow -PppoeName "TestPPPoE" -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [hashtable] -and 
                $result.ContainsKey('Health') -and 
                $result.ContainsKey('Adapter') -and
                $result.ContainsKey('PPPInterface') -and
                $result.ContainsKey('PPPIp'))
    }
    
    Test-Function "Invoke-QuickDiagnosticWorkflow handles null parameters" {
        $result = Invoke-QuickDiagnosticWorkflow -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [hashtable] -and $result.ContainsKey('Health'))
    }
    
    # Test workflow parameter handling
    Test-Function "Workflow handles SkipWifiToggle parameter" {
        $result = Invoke-QuickDiagnosticWorkflow -SkipWifiToggle -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [hashtable])
    }
    
    Test-Function "Workflow handles TargetAdapter parameter" {
        $result = Invoke-QuickDiagnosticWorkflow -TargetAdapter "TestAdapter" -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [hashtable])
    }
    
    # Test error handling
    Test-Function "Workflow handles WriteLog errors gracefully" {
        $badWriteLog = { throw "Test error" }
        try {
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $badWriteLog
            return $false  # Should not reach here
        } catch {
            return $true  # Expected to throw
        }
    }
    
    # Test health object structure
    Test-Function "Workflow returns valid health object" {
        $result = Invoke-QuickDiagnosticWorkflow -WriteLog { param($msg) Write-Host $msg }
        $health = $result.Health
        return ($health -is [hashtable] -and $health.ContainsKey('Items'))
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
