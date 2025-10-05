# Run-Tests-Fast.ps1 - FAST test runner using optimized tests
# Runs only the fast unit tests, skipping slow integration tests

param(
    [switch]$Detailed
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "PPPoE Diagnostic Toolkit - FAST Test Runner" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$testResults = @{
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    TestFiles = @()
}

# Fast tests only (no hardware scanning, no network operations)
$fastTests = @(
    "PPPoE.Core.Tests.ps1",              # 3.7s - Fast
    "PPPoE.Health.Tests.ps1",            # 0.4s - Fast
    "PPPoE.Configuration.Tests.ps1",     # Fast
    "PPPoE.Utilities.Tests.ps1",         # Fast
    "PPPoE.Security.Tests.ps1",          # Fast
    "PPPoE.ErrorHandling.Tests.ps1",     # Fast
    "PPPoE.WorkflowErrorHandling.Tests.ps1"  # 24s - Optimized
)

Write-Host "Running FAST tests (skipping slow integration tests)" -ForegroundColor Yellow
Write-Host ""

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($testFile in $fastTests) {
    $testPath = Join-Path $PSScriptRoot $testFile
    
    if (-not (Test-Path $testPath)) {
        Write-Host "  SKIP: $testFile (not found)" -ForegroundColor Gray
        continue
    }
    
    Write-Host "Running $testFile..." -ForegroundColor Cyan
    
    try {
        $fileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $output = & $testPath 2>&1
        $fileStopwatch.Stop()
        
        $exitCode = $LASTEXITCODE
        
        if ($output -match "All tests passed" -or $output -match "All.*tests passed" -or $exitCode -eq 0) {
            $testResults.PassedTests++
            Write-Host "  PASS - $([math]::Round($fileStopwatch.Elapsed.TotalSeconds, 1))s" -ForegroundColor Green
        } else {
            $testResults.FailedTests++
            Write-Host "  FAIL - $([math]::Round($fileStopwatch.Elapsed.TotalSeconds, 1))s" -ForegroundColor Red
            if ($Detailed) {
                Write-Host "Output: $output" -ForegroundColor Gray
            }
        }
        
        $testResults.TestFiles += @{
            Name = $testFile
            Status = if ($exitCode -eq 0) { "PASSED" } else { "FAILED" }
            Time = $fileStopwatch.Elapsed.TotalSeconds
        }
        
        $testResults.TotalTests++
        
    } catch {
        $testResults.FailedTests++
        $testResults.TotalTests++
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$stopwatch.Stop()

# Summary
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Test Results Summary" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Total Files:  $($testResults.TotalTests)" -ForegroundColor White
Write-Host "  Passed:       $($testResults.PassedTests)" -ForegroundColor Green
Write-Host "  Failed:       $($testResults.FailedTests)" -ForegroundColor $(if ($testResults.FailedTests -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Total Time:   $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s" -ForegroundColor White
Write-Host ""

if ($testResults.FailedTests -eq 0) {
    Write-Host "All fast tests passed! " -ForegroundColor Green
    Write-Host ""
    Write-Host "NOTE: To run slow integration tests (with hardware scanning):" -ForegroundColor Yellow
    Write-Host "  .\Tests\Run-Tests.ps1" -ForegroundColor Gray
    exit 0
} else {
    Write-Host "Some tests failed!" -ForegroundColor Red
    exit 1
}
