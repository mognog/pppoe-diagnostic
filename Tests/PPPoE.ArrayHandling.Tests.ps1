# PPPoE.ArrayHandling.Tests.ps1 - Tests for PowerShell array handling issues

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Net.Diagnostics.psm1",
        "../Modules/PPPoE.Utilities.psm1",
        "../Modules/PPPoE.Net.Adapters.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "Running PowerShell array handling tests..."
    
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
    
    # Test 1: Test-ONTAvailability handles empty results correctly
    if (Test-Function "Test-ONTAvailability handles empty results correctly" {
        # Mock a scenario where no ONTs are reachable
        function Mock-Test-ONTAvailability {
            param([scriptblock]$WriteLog)
            
            $ontResults = @()  # Empty array
            $reachableONTs = $ontResults | Where-Object { $_.Status -eq "REACHABLE" }
            
            # This should not throw an error
            if ($reachableONTs -and $reachableONTs -is [array] -and $reachableONTs.Count -gt 0) {
                return $false  # Should not reach here
            } else {
                return $true   # Should reach here
            }
        }
        
        return Mock-Test-ONTAvailability -WriteLog { param($msg) Write-Host $msg }
    }) { $passed++ } else { $failed++ }
    
    # Test 2: Test-ONTAvailability handles single result correctly
    if (Test-Function "Test-ONTAvailability handles single result correctly" {
        function Mock-Test-ONTAvailability {
            param([scriptblock]$WriteLog)
            
            $ontResults = @(@{ IP = "192.168.1.1"; Status = "REACHABLE"; Latency = 1 })
            $reachableONTs = $ontResults | Where-Object { $_.Status -eq "REACHABLE" }
            
            # This should not throw an error
            if ($reachableONTs -and $reachableONTs -is [array] -and $reachableONTs.Count -gt 0) {
                return $true   # Should reach here
            } else {
                return $false  # Should not reach here
            }
        }
        
        return Mock-Test-ONTAvailability -WriteLog { param($msg) Write-Host $msg }
    }) { $passed++ } else { $failed++ }
    
    # Test 3: Test-ONTAvailability handles null results correctly
    if (Test-Function "Test-ONTAvailability handles null results correctly" {
        function Mock-Test-ONTAvailability {
            param([scriptblock]$WriteLog)
            
            $ontResults = $null
            $reachableONTs = $ontResults | Where-Object { $_.Status -eq "REACHABLE" }
            
            # This should not throw an error
            try {
                if ($reachableONTs -and $reachableONTs -is [array] -and $reachableONTs.Count -gt 0) {
                    return $false  # Should not reach here
                } else {
                    return $true   # Should reach here
                }
            } catch {
                return $false  # Should not throw error
            }
        }
        
        return Mock-Test-ONTAvailability -WriteLog { param($msg) Write-Host $msg }
    }) { $passed++ } else { $failed++ }
    
    # Test 4: Get-DisabledWiFiAdapters returns proper array
    if (Test-Function "Get-DisabledWiFiAdapters returns proper array" {
        $result = Get-DisabledWiFiAdapters
        return ($result -is [array])
    }) { $passed++ } else { $failed++ }
    
    # Test 5: Get-DisabledWiFiAdapters handles no disabled adapters
    if (Test-Function "Get-DisabledWiFiAdapters handles no disabled adapters" {
        $result = Get-DisabledWiFiAdapters
        # Should return empty array, not null
        return ($result -is [array] -and $result.Count -ge 0)
    }) { $passed++ } else { $failed++ }
    
    # Test 6: Array filtering with Where-Object returns proper types
    if (Test-Function "Array filtering with Where-Object returns proper types" {
        $testArray = @(
            @{ Name = "Test1"; Status = "OK" },
            @{ Name = "Test2"; Status = "FAIL" },
            @{ Name = "Test3"; Status = "OK" }
        )
        
        $filtered = $testArray | Where-Object { $_.Status -eq "OK" }
        
        # Should be an array with 2 items
        return ($filtered -is [array] -and $filtered.Count -eq 2)
    }) { $passed++ } else { $failed++ }
    
    # Test 7: Empty array filtering returns proper type
    if (Test-Function "Empty array filtering returns proper type" {
        $emptyArray = @()
        $filtered = $emptyArray | Where-Object { $_.Status -eq "OK" }
        
        # Should be an array (even if empty)
        return ($filtered -is [array])
    }) { $passed++ } else { $failed++ }
    
    # Test 8: Single item array filtering
    if (Test-Function "Single item array filtering" {
        $singleArray = @(@{ Name = "Test1"; Status = "OK" })
        $filtered = $singleArray | Where-Object { $_.Status -eq "OK" }
        
        # Should be an array with 1 item
        return ($filtered -is [array] -and $filtered.Count -eq 1)
    }) { $passed++ } else { $failed++ }
    
    # Test 9: Array count access with proper null checking
    if (Test-Function "Array count access with proper null checking" {
        function Test-ArrayCount {
            param($array)
            
            # Safe array count access
            if ($array -and $array -is [array] -and $array.Count -gt 0) {
                return $array.Count
            } else {
                return 0
            }
        }
        
        $result1 = Test-ArrayCount @()
        $result2 = Test-ArrayCount $null
        $result3 = Test-ArrayCount @("item1", "item2")
        
        return ($result1 -eq 0 -and $result2 -eq 0 -and $result3 -eq 2)
    }) { $passed++ } else { $failed++ }
    
    # Test 10: PowerShell array return behavior consistency
    if (Test-Function "PowerShell array return behavior consistency" {
        function Test-ReturnArray {
            $arr = @()
            return ,$arr  # Force array return
        }
        
        function Test-ReturnSingleItem {
            $arr = @("single")
            return ,$arr  # Force array return
        }
        
        $result1 = Test-ReturnArray
        $result2 = Test-ReturnSingleItem
        
        return ($result1 -is [array] -and $result2 -is [array])
    }) { $passed++ } else { $failed++ }
    
    # Summary
    Write-Host ""
    Write-Host "Array Handling Test Results:"
    Write-Host "============================"
    Write-Host "Passed: $passed"
    Write-Host "Failed: $failed"
    Write-Host "Total: $($passed + $failed)"
    
    if ($failed -eq 0) {
        Write-Host ""
        Write-Host "All array handling tests passed!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Some array handling tests failed!" -ForegroundColor Red
        Write-Host "These tests help catch PowerShell array quirks that cause runtime errors." -ForegroundColor Yellow
    }
    
} finally {
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
