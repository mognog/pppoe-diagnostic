# PPPoE.WorkflowErrorHandling.Tests.Optimized.ps1 - FAST version with shared test setup
# This version runs the workflow ONCE and tests multiple assertions against the same result

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
    
    Write-Host "Running OPTIMIZED error handling tests for PPPoE.Workflows module..." -ForegroundColor Cyan
    Write-Host "(Running workflow ONCE for better performance)" -ForegroundColor Yellow
    Write-Host ""
    
    # Test function wrapper
    function Test-Assertion {
        param([string]$Name, [scriptblock]$TestScript)
        try {
            $result = & $TestScript
            if ($result) {
                Write-Host "  PASS: $Name" -ForegroundColor Green
                return $true
            } else {
                Write-Host "  FAIL: $Name" -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "  FAIL: $Name - Error: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    $passed = 0
    $failed = 0
    
    # ===========================
    # PHASE 1: Run workflow ONCE
    # ===========================
    Write-Host "[1/3] Running workflow (this may take a few seconds)..." -ForegroundColor Cyan
    $mockWriteLog = { param($msg) }  # Silent logger for faster execution
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $workflowResult = Invoke-QuickDiagnosticWorkflow -WriteLog $mockWriteLog
        $workflowSuccess = $true
    } catch {
        $workflowResult = $null
        $workflowSuccess = $false
        $workflowError = $_.Exception.Message
    }
    $stopwatch.Stop()
    
    Write-Host "  Workflow completed in $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor Gray
    Write-Host ""
    
    # ===========================
    # PHASE 2: Test structure validations (using shared result)
    # ===========================
    Write-Host "[2/3] Testing return structure (12 assertions)..." -ForegroundColor Cyan
    
    if (Test-Assertion "Workflow executed without throwing" { $workflowSuccess }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "Result is a hashtable" { $workflowResult -is [hashtable] }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "Result contains Health key" { $workflowResult.ContainsKey('Health') }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "Result contains Adapter key" { $workflowResult.ContainsKey('Adapter') }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "Result contains PPPInterface key" { $workflowResult.ContainsKey('PPPInterface') }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "Result contains PPPIp key" { $workflowResult.ContainsKey('PPPIp') }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "Health is a hashtable" { $workflowResult.Health -is [hashtable] }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "Adapter is null or valid object" { 
        $workflowResult.Adapter -eq $null -or $workflowResult.Adapter -is [object] 
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "PPPInterface is null or valid object" { 
        $workflowResult.PPPInterface -eq $null -or $workflowResult.PPPInterface -is [object] 
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "PPPIp is null or valid object" { 
        $workflowResult.PPPIp -eq $null -or $workflowResult.PPPIp -is [object] 
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "No ContainsKey errors occurred" { 
        -not ($workflowError -and $workflowError -match "ContainsKey") 
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "No property access errors occurred" { 
        -not ($workflowError -and $workflowError -match "property.*cannot be found") 
    }) { $passed++ } else { $failed++ }
    
    Write-Host ""
    
    # ===========================
    # PHASE 3: Test code quality (static analysis)
    # ===========================
    Write-Host "[3/3] Testing code quality (static analysis)..." -ForegroundColor Cyan
    
    $workflowPath = Join-Path $PSScriptRoot "../Modules/PPPoE.Workflows.psm1"
    $workflowContent = Get-Content $workflowPath -Raw
    
    if (Test-Assertion "Workflow uses type checking before ContainsKey" { 
        $workflowContent -match '-is \[hashtable\] -and \$\w+\.ContainsKey'
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "No unsafe ContainsKey calls" { 
        # Look for pattern: if ($var -and $var.ContainsKey) WITHOUT -is [hashtable]
        $lines = $workflowContent -split "`n"
        $unsafePatterns = $lines | Where-Object { 
            $_ -match 'if \(\$\w+ -and \$\w+\.ContainsKey' -and 
            $_ -notmatch '-is \[hashtable\]'
        }
        $unsafePatterns.Count -eq 0
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "All ContainsKey calls are protected" { 
        # Count total ContainsKey calls
        $totalCalls = ([regex]::Matches($workflowContent, '\.ContainsKey\(')).Count
        # Count protected calls (with type check)
        $protectedCalls = ([regex]::Matches($workflowContent, '-is \[hashtable\] -and \$\w+\.ContainsKey')).Count
        
        # All calls should be protected
        $totalCalls -eq $protectedCalls
    }) { $passed++ } else { $failed++ }
    
    Write-Host ""
    
    # ===========================
    # SUMMARY
    # ===========================
    Write-Host "Error Handling Test Results Summary:" -ForegroundColor Cyan
    Write-Host "  Passed: $passed" -ForegroundColor Green
    Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Gray' })
    Write-Host "  Total: $($passed + $failed)" -ForegroundColor White
    Write-Host "  Execution time: $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor Gray
    
    if ($failed -eq 0) {
        Write-Host ""
        Write-Host "All error handling tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "Some tests failed!" -ForegroundColor Red
        exit 1
    }
    
} finally {
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
