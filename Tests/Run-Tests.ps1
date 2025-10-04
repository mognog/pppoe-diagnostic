# Run-Tests.ps1 - Test runner for all PPPoE diagnostic tests
# This script runs all tests and provides a comprehensive report

param(
    [string[]]$TestFiles = @(),
    [switch]$Detailed,
    [switch]$InstallPester
)

Write-Host "PPPoE Diagnostic Toolkit - Test Runner" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Check if we should install Pester
if ($InstallPester) {
    Write-Host "Installing Pester testing framework..." -ForegroundColor Yellow
    try {
        Install-Module -Name Pester -Force -SkipPublisherCheck -AllowPrerelease
        Write-Host "Pester installed successfully" -ForegroundColor Green
    } catch {
        Write-Host "Failed to install Pester: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Continuing with basic validation tests..." -ForegroundColor Yellow
    }
}

# Determine which test files to run
if ($TestFiles.Count -eq 0) {
    $TestFiles = @(
        "PPPoE.Core.Tests.ps1",
        "PPPoE.Health.Tests.ps1", 
        "PPPoE.Net.Tests.ps1",
        "PPPoE.Integration.Tests.ps1",
        "PPPoE.Configuration.Tests.ps1",
        "PPPoE.Utilities.Tests.ps1",
        "PPPoE.Workflows.Tests.ps1",
        "PPPoE.Credentials.Tests.ps1",
        "PPPoE.MainScript.Tests.ps1",
        "PPPoE.Net.Adapters.Tests.ps1",
        "PPPoE.Net.PPPoE.Tests.ps1",
        "PPPoE.Net.Connectivity.Tests.ps1",
        "PPPoE.Net.Diagnostics.Tests.ps1",
        "PPPoE.HealthChecks.Tests.ps1",
        "PPPoE.ErrorHandling.Tests.ps1",
        "PPPoE.Security.Tests.ps1"
    )
}

$testResults = @{
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    TestFiles = @()
}

Write-Host ""
Write-Host "Running tests from: $($TestFiles -join ', ')" -ForegroundColor Yellow

foreach ($testFile in $TestFiles) {
    $testPath = Join-Path $PSScriptRoot $testFile
    
    if (-not (Test-Path $testPath)) {
        Write-Host "Test file not found: $testFile" -ForegroundColor Yellow
        continue
    }
    
    Write-Host ""
    Write-Host "Running $testFile..." -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Gray
    
    try {
        # Run the test file
        $output = & $testPath 2>&1
        
        # Capture exit code
        $exitCode = $LASTEXITCODE
        
        # Parse results based on output
        if ($output -match "All tests passed") {
            $testResults.PassedTests++
            Write-Host "$testFile - PASSED" -ForegroundColor Green
        } elseif ($exitCode -eq 0) {
            $testResults.PassedTests++
            Write-Host "$testFile - PASSED" -ForegroundColor Green
        } else {
            $testResults.FailedTests++
            Write-Host "$testFile - FAILED" -ForegroundColor Red
            if ($Detailed) {
                Write-Host "Output: $output" -ForegroundColor Gray
            }
        }
        
        $testResults.TestFiles += @{
            Name = $testFile
            Status = if ($exitCode -eq 0) { "PASSED" } else { "FAILED" }
            ExitCode = $exitCode
        }
        
        $testResults.TotalTests++
        
    } catch {
        $testResults.FailedTests++
        $testResults.TotalTests++
        Write-Host "$testFile - ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $testResults.TestFiles += @{
            Name = $testFile
            Status = "ERROR"
            ExitCode = 1
            Error = $_.Exception.Message
        }
    }
}

# Summary Report
Write-Host ""
Write-Host "Test Results Summary" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host "📁 Total Test Files: $($testResults.TotalTests)" -ForegroundColor White
Write-Host "Passed: $($testResults.PassedTests)" -ForegroundColor Green
Write-Host "Failed: $($testResults.FailedTests)" -ForegroundColor Red

if ($testResults.FailedTests -gt 0) {
    Write-Host ""
    Write-Host "Failed Test Files:" -ForegroundColor Red
    $testResults.TestFiles | Where-Object { $_.Status -ne "PASSED" } | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Status)" -ForegroundColor Red
        if ($_.Error) {
            Write-Host "    Error: $($_.Error)" -ForegroundColor Gray
        }
    }
}

# Overall result
if ($testResults.FailedTests -eq 0) {
    Write-Host ""
    Write-Host "All tests passed! Ready for refactoring." -ForegroundColor Green
    $overallExitCode = 0
} else {
    Write-Host ""
    Write-Host "Some tests failed. Review issues before refactoring." -ForegroundColor Yellow
    $overallExitCode = 1
}

Write-Host ""
Write-Host "Tips:" -ForegroundColor Cyan
Write-Host "  - Run with -Detailed for more output" -ForegroundColor Gray
Write-Host "  - Run with -InstallPester to install testing framework" -ForegroundColor Gray
Write-Host "  - Run specific tests: .\Run-Tests.ps1 -TestFiles @('PPPoE.Core.Tests.ps1')" -ForegroundColor Gray

exit $overallExitCode
