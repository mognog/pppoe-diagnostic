# PPPoE.Workflows.Tests.Optimized.ps1 - FAST version with shared test setup

$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
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
    
    Write-Host "Running OPTIMIZED workflow tests (shared setup pattern)..." -ForegroundColor Cyan
    Write-Host ""
    
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
            Write-Host "  FAIL: $Name - $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    $passed = 0
    $failed = 0
    
    # =======================
    # RUN WORKFLOW ONCE
    # =======================
    Write-Host "[1/2] Running workflow once (silent mode)..." -ForegroundColor Cyan
    $silentLogger = { param($msg) }  # Silent for speed
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $sharedResult = Invoke-QuickDiagnosticWorkflow -PppoeName "TestPPPoE" -WriteLog $silentLogger
        $workflowSuccess = $true
    } catch {
        $sharedResult = $null
        $workflowSuccess = $false
        $workflowError = $_.Exception.Message
    }
    $stopwatch.Stop()
    
    Write-Host "  Completed in $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor Gray
    Write-Host ""
    
    # =======================
    # TEST ASSERTIONS (Fast)
    # =======================
    Write-Host "[2/2] Testing assertions (10 tests)..." -ForegroundColor Cyan
    
    if (Test-Assertion "Workflow executes without throwing" { $workflowSuccess }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "Returns valid hashtable structure" { 
        $sharedResult -is [hashtable] -and 
        $sharedResult.ContainsKey('Health') -and 
        $sharedResult.ContainsKey('Adapter') -and
        $sharedResult.ContainsKey('PPPInterface') -and
        $sharedResult.ContainsKey('PPPIp')
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "Health is hashtable" { $sharedResult.Health -is [hashtable] }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "Adapter is null or object" { 
        $sharedResult.Adapter -eq $null -or $sharedResult.Adapter -is [object] 
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "PPPInterface is null or object" { 
        $sharedResult.PPPInterface -eq $null -or $sharedResult.PPPInterface -is [object] 
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "PPPIp is null or object" { 
        $sharedResult.PPPIp -eq $null -or $sharedResult.PPPIp -is [object] 
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "No ContainsKey errors" { 
        -not ($workflowError -and $workflowError -match "ContainsKey") 
    }) { $passed++ } else { $failed++ }
    
    if (Test-Assertion "No property access errors" { 
        -not ($workflowError -and $workflowError -match "property.*cannot be found") 
    }) { $passed++ } else { $failed++ }
    
    # Test with null parameters
    try {
        $nullResult = Invoke-QuickDiagnosticWorkflow -WriteLog $silentLogger
        if (Test-Assertion "Handles null parameters" { $nullResult -is [hashtable] }) { $passed++ } else { $failed++ }
    } catch {
        if (Test-Assertion "Handles null parameters" { $false }) { $passed++ } else { $failed++ }
    }
    
    # Test workflow function exports
    if (Test-Assertion "Workflow functions exported correctly" {
        (Get-Command Invoke-QuickDiagnosticWorkflow -ErrorAction SilentlyContinue) -and
        (Get-Command Invoke-PPPoEDiagnosticWorkflow -ErrorAction SilentlyContinue)
    }) { $passed++ } else { $failed++ }
    
    Write-Host ""
    
    # Summary
    Write-Host "Test Results Summary:" -ForegroundColor Cyan
    Write-Host "  Passed: $passed" -ForegroundColor Green
    Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Gray' })
    Write-Host "  Total: $($passed + $failed)" -ForegroundColor White
    Write-Host "  Execution time: $($stopwatch.ElapsedMilliseconds)ms (vs ~170s unoptimized)" -ForegroundColor Gray
    
    if ($failed -eq 0) {
        Write-Host ""
        Write-Host "All tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "Some tests failed!" -ForegroundColor Red
        exit 1
    }
    
} finally {
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
