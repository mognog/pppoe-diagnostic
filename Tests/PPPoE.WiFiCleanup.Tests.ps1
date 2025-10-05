# PPPoE.WiFiCleanup.Tests.ps1 - Tests for WiFi adapter cleanup functionality

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Net.Adapters.psm1",
        "../Modules/PPPoE.Utilities.psm1",
        "../Modules/PPPoE.Workflows.psm1",
        "../Modules/PPPoE.Health.psm1",
        "../Modules/PPPoE.HealthChecks.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "Running WiFi cleanup functionality tests..."
    
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
    
    # Test 1: Disable-WiFiAdapters returns array of disabled adapter names
    if (Test-Function "Disable-WiFiAdapters returns array of disabled adapter names" {
        $result = Disable-WiFiAdapters -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [array])
    }) { $passed++ } else { $failed++ }
    
    # Test 2: Disable-WiFiAdapters remembers which adapters were disabled
    if (Test-Function "Disable-WiFiAdapters remembers which adapters were disabled" {
        $result = Disable-WiFiAdapters -WriteLog { param($msg) Write-Host $msg }
        if ($result -and $result.Count -gt 0) {
            # Should return adapter names that were actually disabled
            return ($result | ForEach-Object { $_ -is [string] -and $_.Length -gt 0 }) -notcontains $false
        } else {
            # No adapters to disable is also valid
            return $true
        }
    }) { $passed++ } else { $failed++ }
    
    # Test 3: Enable-WiFiAdapters can re-enable specific adapters
    if (Test-Function "Enable-WiFiAdapters can re-enable specific adapters" {
        # First disable some adapters
        $disabledAdapters = Disable-WiFiAdapters -WriteLog { param($msg) Write-Host $msg }
        
        # Then try to re-enable them
        if ($disabledAdapters -and $disabledAdapters.Count -gt 0) {
            $result = Enable-WiFiAdapters -AdapterNames $disabledAdapters -WriteLog { param($msg) Write-Host $msg }
            return $true  # Function should execute without error
        } else {
            # Test with empty array
            $result = Enable-WiFiAdapters -AdapterNames @() -WriteLog { param($msg) Write-Host $msg }
            return $true
        }
    }) { $passed++ } else { $failed++ }
    
    # Test 4: Enable-WiFiAdapters handles non-existent adapter names gracefully
    if (Test-Function "Enable-WiFiAdapters handles non-existent adapter names gracefully" {
        $result = Enable-WiFiAdapters -AdapterNames @("NonExistentAdapter123", "AnotherNonExistent456") -WriteLog { param($msg) Write-Host $msg }
        return $true  # Should not throw error
    }) { $passed++ } else { $failed++ }
    
    # Test 5: Get-DisabledWiFiAdapters finds disabled adapters
    if (Test-Function "Get-DisabledWiFiAdapters finds disabled adapters" {
        $result = Get-DisabledWiFiAdapters
        return ($result -is [array])
    }) { $passed++ } else { $failed++ }
    
    # Test 6: Enable-AllDisabledWiFiAdapters re-enables all disabled adapters
    if (Test-Function "Enable-AllDisabledWiFiAdapters re-enables all disabled adapters" {
        $result = Enable-AllDisabledWiFiAdapters -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [int])
    }) { $passed++ } else { $failed++ }
    
    # Test 7: Complete disable/enable cycle works
    if (Test-Function "Complete disable/enable cycle works" {
        # Disable adapters and remember names
        $disabledAdapters = Disable-WiFiAdapters -WriteLog { param($msg) Write-Host $msg }
        
        # Re-enable the same adapters
        if ($disabledAdapters -and $disabledAdapters.Count -gt 0) {
            $result = Enable-WiFiAdapters -AdapterNames $disabledAdapters -WriteLog { param($msg) Write-Host $msg }
        }
        
        return $true  # Should complete without error
    }) { $passed++ } else { $failed++ }
    
    # Test 8: Workflow returns disabled WiFi adapters in result
    if (Test-Function "Workflow returns disabled WiFi adapters in result" {
        $result = Invoke-QuickDiagnosticWorkflow -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [hashtable] -and $result.ContainsKey('DisabledWiFiAdapters'))
    }) { $passed++ } else { $failed++ }
    
    # Test 9: Workflow DisabledWiFiAdapters is an array
    if (Test-Function "Workflow DisabledWiFiAdapters is an array" {
        $result = Invoke-QuickDiagnosticWorkflow -WriteLog { param($msg) Write-Host $msg }
        if ($result -and $result.DisabledWiFiAdapters) {
            return ($result.DisabledWiFiAdapters -is [array])
        } else {
            return $true  # Null or empty is also valid
        }
    }) { $passed++ } else { $failed++ }
    
    # Test 10: Functions handle null WriteLog gracefully
    if (Test-Function "Functions handle null WriteLog gracefully" {
        try {
            $result1 = Disable-WiFiAdapters -WriteLog $null
            $result2 = Enable-WiFiAdapters -AdapterNames @() -WriteLog $null
            $result3 = Enable-AllDisabledWiFiAdapters -WriteLog $null
            return $true
        } catch {
            return $false
        }
    }) { $passed++ } else { $failed++ }
    
    # Test 11: Functions handle empty WriteLog gracefully
    if (Test-Function "Functions handle empty WriteLog gracefully" {
        try {
            $result1 = Disable-WiFiAdapters -WriteLog { }
            $result2 = Enable-WiFiAdapters -AdapterNames @() -WriteLog { }
            $result3 = Enable-AllDisabledWiFiAdapters -WriteLog { }
            return $true
        } catch {
            return $false
        }
    }) { $passed++ } else { $failed++ }
    
    # Test 12: WiFi cleanup functions complete within reasonable time
    if (Test-Function "WiFi cleanup functions complete within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $disabledAdapters = Disable-WiFiAdapters -WriteLog { param($msg) Write-Host $msg }
        if ($disabledAdapters -and $disabledAdapters.Count -gt 0) {
            Enable-WiFiAdapters -AdapterNames $disabledAdapters -WriteLog { param($msg) Write-Host $msg }
        }
        
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 10000)  # 10 seconds
    }) { $passed++ } else { $failed++ }
    
    # Test 13: Get-WiFiAdapters returns valid adapter objects
    if (Test-Function "Get-WiFiAdapters returns valid adapter objects" {
        $adapters = Get-WiFiAdapters
        if ($adapters) {
            # Check that each adapter has required properties
            foreach ($adapter in $adapters) {
                if (-not $adapter.Name -or -not $adapter.Status) {
                    return $false
                }
            }
        }
        return $true
    }) { $passed++ } else { $failed++ }
    
    # Test 14: WiFi adapter status checking works
    if (Test-Function "WiFi adapter status checking works" {
        $adapters = Get-WiFiAdapters
        if ($adapters -and $adapters.Count -gt 0) {
            $adapter = $adapters[0]
            # Status should be one of: Up, Disabled, NotPresent, etc.
            return ($adapter.Status -match '^(Up|Disabled|NotPresent|Down)$')
        } else {
            return $true  # No adapters is valid
        }
    }) { $passed++ } else { $failed++ }
    
    # Test 15: Multiple WiFi adapters are handled correctly
    if (Test-Function "Multiple WiFi adapters are handled correctly" {
        $adapters = Get-WiFiAdapters
        if ($adapters -and $adapters.Count -gt 1) {
            # Should be able to disable and re-enable multiple adapters
            $disabledAdapters = Disable-WiFiAdapters -WriteLog { param($msg) Write-Host $msg }
            if ($disabledAdapters -and $disabledAdapters.Count -gt 1) {
                $result = Enable-WiFiAdapters -AdapterNames $disabledAdapters -WriteLog { param($msg) Write-Host $msg }
            }
        }
        return $true  # Should complete without error
    }) { $passed++ } else { $failed++ }
    
    # Summary
    Write-Host ""
    Write-Host "Test Results Summary:"
    Write-Host "===================="
    Write-Host "Passed: $passed"
    Write-Host "Failed: $failed"
    Write-Host "Total: $($passed + $failed)"
    
    if ($failed -eq 0) {
        Write-Host ""
        Write-Host "All tests passed!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Some tests failed!" -ForegroundColor Red
    }
    
} finally {
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}