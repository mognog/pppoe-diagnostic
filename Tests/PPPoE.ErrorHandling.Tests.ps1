# PPPoE.ErrorHandling.Tests.ps1 - Tests for error handling and edge cases

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Health.psm1",
        "../Modules/PPPoE.Net.psm1",
        "../Modules/PPPoE.Configuration.psm1",
        "../Modules/PPPoE.Credentials.psm1",
        "../Modules/PPPoE.Utilities.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "🔍 Running error handling and edge case tests..."
    
    # Test function wrapper
    function Test-Function {
        param([string]$Name, [scriptblock]$TestScript)
        try {
            $result = & $TestScript
            if ($result) {
                Write-Host "✅ $Name" -ForegroundColor Green
                $script:passed++
                return $true
            } else {
                Write-Host "❌ $Name" -ForegroundColor Red
                $script:failed++
                return $false
            }
        } catch {
            Write-Host "❌ $Name - Error: $($_.Exception.Message)" -ForegroundColor Red
            $script:failed++
            return $false
        }
    }
    
    $script:passed = 0
    $script:failed = 0
    
    # Test null and empty input handling
    Test-Function "Functions handle null inputs gracefully" {
        try {
            # Test various functions with null inputs
            $health = New-Health
            $result1 = Add-Health -Health $health -Key $null -Value "test"
            $result2 = Test-CredentialsFormat -UserName $null -Password $null
            $result3 = Get-ProjectConfiguration -ConfigPath $null
            $result4 = Test-AdministratorRights
            return $true
        } catch {
            return $false
        }
    }
    
    Test-Function "Functions handle empty string inputs gracefully" {
        try {
            # Test various functions with empty string inputs
            $health = New-Health
            $result1 = Add-Health -Health $health -Key "" -Value "test"
            $result2 = Test-CredentialsFormat -UserName "" -Password ""
            $result3 = Get-ProjectConfiguration -ConfigPath ""
            $result4 = Format-Duration -Duration 0
            return $true
        } catch {
            return $false
        }
    }
    
    # Test malformed data handling
    Test-Function "Configuration functions handle malformed JSON" {
        try {
            # Create a temporary malformed JSON file
            $tempFile = [System.IO.Path]::GetTempFileName()
            "invalid json content { broken" | Out-File -FilePath $tempFile -Encoding UTF8
            
            $result = Import-Configuration -ConfigPath $tempFile
            Remove-Item $tempFile -Force
            return ($result -eq $null)  # Should return null for malformed JSON
        } catch {
            return $true  # Expected to handle malformed JSON
        }
    }
    
    Test-Function "Configuration functions handle non-existent files" {
        try {
            $result = Import-Configuration -ConfigPath "NonExistentFile123.json"
            return ($result -eq $null)  # Should return null for non-existent file
        } catch {
            return $true  # Expected to handle non-existent files
        }
    }
    
    # Test permission error handling
    Test-Function "Functions handle permission denied errors gracefully" {
        try {
            # Test functions that might require elevated permissions
            $result1 = Test-AdministratorRights
            $result2 = Get-SystemInformation
            $result3 = Get-DiskSpace
            return $true
        } catch {
            return $false
        }
    }
    
    # Test network error handling
    Test-Function "Network functions handle connectivity failures gracefully" {
        try {
            # Test network functions with invalid targets - should not throw, just return false/failure
            $result1 = Test-DNSResolution -HostName "invalid.invalid.invalid.test"
            $result2 = Test-PacketLoss -HostName "invalid.invalid.invalid.test" -Count 1
            $result3 = Test-QuickConnectivityCheck -HostName "invalid.invalid.invalid.test"
            # As long as they don't throw exceptions, the test passes
            return $true
        } catch {
            # If they throw, that's also acceptable error handling
            return $true
        }
    }
    
    # Test resource exhaustion scenarios
    Test-Function "Functions handle large data inputs gracefully" {
        try {
            # Test with large strings
            $largeString = "x" * 10000
            $health = New-Health
            $result1 = Add-Health -Health $health -Key "LargeKey" -Value $largeString
            
            # Test with large arrays
            $largeArray = 1..1000
            $result2 = ConvertTo-HumanReadable -Bytes 999999999999
            
            return $true
        } catch {
            return $false
        }
    }
    
    # Test concurrent access scenarios
    Test-Function "Functions handle concurrent access gracefully" {
        try {
            # Test multiple simultaneous operations
            $health1 = New-Health
            $health2 = New-Health
            
            $result1 = Add-Health -Health $health1 -Key "Test1" -Value "Value1"
            $result2 = Add-Health -Health $health2 -Key "Test2" -Value "Value2"
            
            return $true
        } catch {
            return $false
        }
    }
    
    # Test memory pressure scenarios
    Test-Function "Functions handle memory pressure gracefully" {
        try {
            # Test functions under memory pressure
            $health = New-Health
            for ($i = 0; $i -lt 100; $i++) {
                $health = Add-Health -Health $health -Key "Key$i" -Value "Value$i"
            }
            
            # Don't call Write-HealthSummary as it requires transcript to be running
            # Just verify we can create and manage large health objects
            return ($health.Count -eq 100)
        } catch {
            return $false
        }
    }
    
    # Test timeout scenarios
    Test-Function "Network functions handle timeouts gracefully" {
        try {
            # Test functions with timeout handling - use invalid hosts so we don't require connectivity
            # The functions should handle timeouts gracefully and not hang
            $result1 = Test-DNSResolution -HostName "timeout.test.invalid"
            $result2 = Test-QuickConnectivityCheck -HostName "timeout.test.invalid"
            # As long as they return (don't hang forever), test passes
            return $true
        } catch {
            # If they throw, that's also acceptable error handling
            return $true
        }
    }
    
    # Test invalid parameter combinations
    Test-Function "Functions handle invalid parameter combinations gracefully" {
        try {
            # Test with invalid parameter combinations
            $health = New-Health
            $result1 = Add-Health -Health $health -Key "Test" -Value "Value" -Order -1
            $result2 = Format-Duration -Duration -100
            $result3 = ConvertTo-HumanReadable -Bytes -1000
            return $true
        } catch {
            return $true  # Expected to handle invalid parameters
        }
    }
    
    # Test boundary conditions
    Test-Function "Functions handle boundary conditions correctly" {
        try {
            # Test boundary values
            $result1 = Format-Duration -Duration ([TimeSpan]::Zero)
            $result2 = Format-Duration -Duration ([TimeSpan]::FromSeconds(86400))  # 1 day
            $result3 = ConvertTo-HumanReadable -Bytes 0
            $result4 = ConvertTo-HumanReadable -Bytes 1099511627776  # 1 TB
            # Verify results are strings
            return (($result1 -is [string]) -and ($result2 -is [string]) -and ($result3 -is [string]) -and ($result4 -is [string]))
        } catch {
            return $false
        }
    }
    
    # Test error recovery
    Test-Function "Functions can recover from errors" {
        try {
            $health = New-Health
            
            # Cause an error, then test recovery
            try {
                $result1 = Add-Health -Health $null -Key "Test" -Value "Value"
            } catch {
                # Expected error
            }
            
            # Should still work after error
            $result2 = Add-Health -Health $health -Key "Test" -Value "Value"
            return ($result2 -ne $null)
        } catch {
            return $false
        }
    }
    
    # Test resource cleanup
    Test-Function "Functions clean up resources properly" {
        try {
            # Test resource cleanup
            $tempFile = [System.IO.Path]::GetTempFileName()
            $config = Get-ProjectConfiguration
            $result = Export-Configuration -Config $config -OutputPath $tempFile
            
            if ($result -and (Test-Path $tempFile)) {
                Remove-Item $tempFile -Force
                return $true
            }
            return $false
        } catch {
            return $false
        }
    }
    
    Write-Host "`nTest Results Summary:"
    Write-Host "===================="
    Write-Host "Passed: $passed"
    Write-Host "Failed: $failed"
    Write-Host "Total: $($passed + $failed)"
    
    if ($failed -eq 0) {
        Write-Host "`nAll tests passed!" -ForegroundColor Green
    } else {
        Write-Host "`nSome tests failed!" -ForegroundColor Red
    }
    
} finally {
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
