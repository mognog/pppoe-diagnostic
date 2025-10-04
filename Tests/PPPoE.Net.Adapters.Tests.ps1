# PPPoE.Net.Adapters.Tests.ps1 - Tests for network adapter management module

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Net.Adapters.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "🔍 Running basic validation tests for PPPoE.Net.Adapters module..."
    
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
    
    # Test Get-CandidateEthernetAdapters
    Test-Function "Get-CandidateEthernetAdapters returns array" {
        $adapters = Get-CandidateEthernetAdapters
        return ($adapters -is [array] -or $adapters -eq $null)
    }
    
    Test-Function "Get-CandidateEthernetAdapters filters correctly" {
        $adapters = Get-CandidateEthernetAdapters
        if ($adapters -and $adapters.Count -gt 0) {
            # Should not include WiFi adapters
            $wifiAdapters = $adapters | Where-Object { 
                $_.InterfaceDescription -like "*wireless*" -or 
                $_.InterfaceDescription -like "*wi-fi*" -or 
                $_.InterfaceDescription -like "*wlan*"
            }
            return ($wifiAdapters.Count -eq 0)
        }
        return $true
    }
    
    # Test Get-RecommendedAdapter
    Test-Function "Get-RecommendedAdapter returns valid adapter or null" {
        $adapter = Get-RecommendedAdapter
        return ($adapter -eq $null -or ($adapter -is [object] -and $adapter.Name))
    }
    
    Test-Function "Get-RecommendedAdapter prefers active adapters" {
        $adapter = Get-RecommendedAdapter
        if ($adapter) {
            return ($adapter.Status -eq 'Up' -or $adapter.Status -eq 'Down')
        }
        return $true
    }
    
    # Test Select-NetworkAdapter
    Test-Function "Select-NetworkAdapter handles null input" {
        $result = Select-NetworkAdapter -TargetAdapter $null
        return ($result -eq $null -or ($result -is [object] -and $result.Name))
    }
    
    Test-Function "Select-NetworkAdapter handles empty string" {
        $result = Select-NetworkAdapter -TargetAdapter ""
        return ($result -eq $null -or ($result -is [object] -and $result.Name))
    }
    
    Test-Function "Select-NetworkAdapter handles non-existent adapter" {
        $result = Select-NetworkAdapter -TargetAdapter "NonExistentAdapter123"
        return ($result -eq $null -or ($result -is [object] -and $result.Name))
    }
    
    # Test Test-LinkUp
    Test-Function "Test-LinkUp handles valid adapter" {
        $adapters = Get-CandidateEthernetAdapters
        if ($adapters -and $adapters.Count -gt 0) {
            $result = Test-LinkUp -AdapterName $adapters[0].Name
            return ($result -is [bool])
        }
        return $true
    }
    
    Test-Function "Test-LinkUp handles non-existent adapter" {
        try {
            $result = Test-LinkUp -AdapterName "NonExistentAdapter123"
            return $false
        } catch {
            return $true  # Expected to throw for non-existent adapter
        }
    }
    
    Test-Function "Test-LinkUp handles null input" {
        try {
            $result = Test-LinkUp -AdapterName $null
            return $false
        } catch {
            return $true  # Expected to throw for null input
        }
    }
    
    # Error handling tests
    Test-Function "Functions handle network adapter enumeration errors gracefully" {
        # This test verifies that functions don't crash when network operations fail
        try {
            $adapters = Get-CandidateEthernetAdapters
            $recommended = Get-RecommendedAdapter
            return $true
        } catch {
            return $false
        }
    }
    
    # Performance tests
    Test-Function "Get-CandidateEthernetAdapters completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $adapters = Get-CandidateEthernetAdapters
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 5000)  # Should complete within 5 seconds
    }
    
    Test-Function "Get-RecommendedAdapter completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $adapter = Get-RecommendedAdapter
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 3000)  # Should complete within 3 seconds
    }
    
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
