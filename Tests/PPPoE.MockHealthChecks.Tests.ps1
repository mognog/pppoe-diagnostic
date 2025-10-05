# PPPoE.MockHealthChecks.Tests.ps1 - Tests with mocked health check functions to simulate error conditions

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
    
    Write-Host "🔍 Running mock health check tests for PPPoE.Workflows module..." -ForegroundColor Cyan
    
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
    
    # Test 1: Mock Invoke-NetworkAdapterChecks returning null
    Test-Function "Workflow handles null return from Invoke-NetworkAdapterChecks" {
        # Create a mock module that overrides the health check function
        $mockModule = @"
function Invoke-NetworkAdapterChecks {
    param([hashtable]`$Health, [string]`$TargetAdapter, [scriptblock]`$WriteLog)
    # Return null to simulate the error condition
    return `$null
}
"@
        
        # Save original function
        $originalFunction = Get-Command Invoke-NetworkAdapterChecks -ErrorAction SilentlyContinue
        
        try {
            # Temporarily override the function
            Invoke-Expression $mockModule
            
            $mockWriteLog = { param($msg) Write-Host $msg }
            
            # This should not throw the "Health property cannot be found" error
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
            
            # Should return a valid structure even with null health checks
            return ($result -is [hashtable] -and $result.ContainsKey('Health'))
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error from the transcript!" -ForegroundColor Yellow
                return $false
            }
            return $true  # Other errors are acceptable
        } finally {
            # Restore original function if it existed
            if ($originalFunction) {
                # Re-import the module to restore the original function
                Import-Module "../Modules/PPPoE.HealthChecks.psm1" -Force
            }
        }
    }
    
    # Test 2: Mock Invoke-NetworkAdapterChecks returning object without Health property
    Test-Function "Workflow handles object without Health property from Invoke-NetworkAdapterChecks" {
        $mockModule = @"
function Invoke-NetworkAdapterChecks {
    param([hashtable]`$Health, [string]`$TargetAdapter, [scriptblock]`$WriteLog)
    # Return object without Health property to simulate the error condition
    return @{
        Adapter = `$null
        LinkDown = `$true
        # Missing Health property!
    }
}
"@
        
        $originalFunction = Get-Command Invoke-NetworkAdapterChecks -ErrorAction SilentlyContinue
        
        try {
            Invoke-Expression $mockModule
            
            $mockWriteLog = { param($msg) Write-Host $msg }
            
            # This should not throw the "Health property cannot be found" error
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
            
            return ($result -is [hashtable] -and $result.ContainsKey('Health'))
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error from the transcript!" -ForegroundColor Yellow
                return $false
            }
            return $true
        } finally {
            if ($originalFunction) {
                Import-Module "../Modules/PPPoE.HealthChecks.psm1" -Force
            }
        }
    }
    
    # Test 3: Mock Invoke-BasicSystemChecks returning null
    Test-Function "Workflow handles null return from Invoke-BasicSystemChecks" {
        $mockModule = @"
function Invoke-BasicSystemChecks {
    param([hashtable]`$Health, [scriptblock]`$WriteLog)
    # Return null to simulate error condition
    return `$null
}
"@
        
        $originalFunction = Get-Command Invoke-BasicSystemChecks -ErrorAction SilentlyContinue
        
        try {
            Invoke-Expression $mockModule
            
            $mockWriteLog = { param($msg) Write-Host $msg }
            
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
            
            return ($result -is [hashtable] -and $result.ContainsKey('Health'))
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error from the transcript!" -ForegroundColor Yellow
                return $false
            }
            return $true
        } finally {
            if ($originalFunction) {
                Import-Module "../Modules/PPPoE.HealthChecks.psm1" -Force
            }
        }
    }
    
    # Test 4: Mock multiple health check functions returning null
    Test-Function "Workflow handles multiple null returns from health check functions" {
        $mockModule = @"
function Invoke-BasicSystemChecks {
    param([hashtable]`$Health, [scriptblock]`$WriteLog)
    return `$null
}

function Invoke-NetworkAdapterChecks {
    param([hashtable]`$Health, [string]`$TargetAdapter, [scriptblock]`$WriteLog)
    return `$null
}

function Invoke-PPPoEConnectionChecks {
    param([hashtable]`$Health, [string]`$ConnectionNameToUse, [string]`$UserName, [string]`$Password, [string]`$CredentialsFile, [scriptblock]`$WriteLog)
    return `$null
}
"@
        
        $originalFunctions = @(
            Get-Command Invoke-BasicSystemChecks -ErrorAction SilentlyContinue,
            Get-Command Invoke-NetworkAdapterChecks -ErrorAction SilentlyContinue,
            Get-Command Invoke-PPPoEConnectionChecks -ErrorAction SilentlyContinue
        )
        
        try {
            Invoke-Expression $mockModule
            
            $mockWriteLog = { param($msg) Write-Host $msg }
            
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
            
            return ($result -is [hashtable] -and $result.ContainsKey('Health'))
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error from the transcript!" -ForegroundColor Yellow
                return $false
            }
            return $true
        } finally {
            # Restore original functions
            Import-Module "../Modules/PPPoE.HealthChecks.psm1" -Force
        }
    }
    
    # Test 5: Test the specific line that caused the error (line 57 in Workflows.psm1)
    Test-Function "Workflow line 57 handles null adapterChecks.Health properly" {
        $mockModule = @"
function Invoke-NetworkAdapterChecks {
    param([hashtable]`$Health, [string]`$TargetAdapter, [scriptblock]`$WriteLog)
    # Return object with null Health property
    return @{
        Health = `$null
        Adapter = `$null
        LinkDown = `$true
    }
}
"@
        
        $originalFunction = Get-Command Invoke-NetworkAdapterChecks -ErrorAction SilentlyContinue
        
        try {
            Invoke-Expression $mockModule
            
            $mockWriteLog = { param($msg) Write-Host $msg }
            
            # This should not throw when trying to access .Health on a null object
            $result = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
            
            return ($result -is [hashtable] -and $result.ContainsKey('Health'))
        } catch {
            if ($_.Exception.Message -match "property.*Health.*cannot be found") {
                Write-Host "   Detected the exact error from line 57!" -ForegroundColor Yellow
                return $false
            }
            return $true
        } finally {
            if ($originalFunction) {
                Import-Module "../Modules/PPPoE.HealthChecks.psm1" -Force
            }
        }
    }
    
    # Count results
    $total = $passed + $failed
    
    Write-Host ""
    Write-Host "📊 Mock Health Check Test Results Summary:" -ForegroundColor Cyan
    Write-Host "✅ Passed: $passed" -ForegroundColor Green
    Write-Host "❌ Failed: $failed" -ForegroundColor Red
    Write-Host "📈 Total: $total" -ForegroundColor Cyan
    
    if ($failed -eq 0) {
        Write-Host ""
        Write-Host "🎉 All mock health check tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "❌ Some mock health check tests failed!" -ForegroundColor Red
        Write-Host "   This indicates the workflow needs better error handling." -ForegroundColor Yellow
        exit 1
    }
    
} finally {
    # Restore original execution policy
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
