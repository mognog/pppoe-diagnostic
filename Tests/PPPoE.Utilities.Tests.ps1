# PPPoE.Utilities.Tests.ps1 - Tests for utilities module

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot "../Modules/PPPoE.Utilities.psm1"
    Import-Module $modulePath -Force
    
    Write-Host "🔍 Running basic validation tests for PPPoE.Utilities module..."
    
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
    
    # Test Format-Duration
    Test-Function "Format-Duration formats seconds correctly" {
        $duration = [TimeSpan]::FromSeconds(30)
        $formatted = Format-Duration -Duration $duration
        return ($formatted -like "*seconds*" -and $formatted -match "30")
    }
    
    Test-Function "Format-Duration formats minutes correctly" {
        $duration = [TimeSpan]::FromMinutes(5)
        $formatted = Format-Duration -Duration $duration
        return ($formatted -like "*minutes*" -and $formatted -match "5")
    }
    
    # Test ConvertTo-HumanReadable
    Test-Function "ConvertTo-HumanReadable formats bytes correctly" {
        $formatted = ConvertTo-HumanReadable -Bytes 1024
        return ($formatted -like "*KB*" -and $formatted -match "1")
    }
    
    Test-Function "ConvertTo-HumanReadable formats large numbers" {
        $formatted = ConvertTo-HumanReadable -Bytes (1024 * 1024 * 1024)
        return ($formatted -like "*GB*" -and $formatted -match "1")
    }
    
    # Test Test-AdministratorRights
    Test-Function "Test-AdministratorRights returns boolean" {
        $isAdmin = Test-AdministratorRights
        return ($isAdmin -is [bool])
    }
    
    # Test Get-SystemInformation
    Test-Function "Get-SystemInformation returns system info" {
        $sysInfo = Get-SystemInformation
        return ($sysInfo -is [hashtable] -and 
                $sysInfo.ContainsKey('ComputerName') -and 
                $sysInfo.ContainsKey('PowerShellVersion') -and
                $sysInfo.ContainsKey('IsAdministrator'))
    }
    
    # Test Get-NetworkAdapterSummary
    Test-Function "Get-NetworkAdapterSummary returns adapter info" {
        $adapters = Get-NetworkAdapterSummary
        return ($adapters -is [array] -or $adapters -eq $null)
    }
    
    # Test Get-ProcessInformation
    Test-Function "Get-ProcessInformation returns process info" {
        $processes = Get-ProcessInformation
        # Return value should be an array (even if empty, which is normal if no PPP/RAS processes are running)
        return ($processes -is [array] -or $processes -eq $null)
    }
    
    # Test Test-PortAvailability
    Test-Function "Test-PortAvailability tests port correctly" {
        # Test a port that should be available (HTTP)
        $result = Test-PortAvailability -Port 80 -TimeoutMs 1000
        return ($result -is [bool])
    }
    
    # Test Get-DiskSpace
    Test-Function "Get-DiskSpace returns disk info" {
        $diskInfo = Get-DiskSpace -Drive 'C:'
        return ($diskInfo -is [hashtable] -or $diskInfo -eq $null)
    }
    
    # Test Get-ServiceStatus
    Test-Function "Get-ServiceStatus returns service info" {
        $services = Get-ServiceStatus
        return ($services -is [array])
    }
    
    # Test Measure-ExecutionTime
    Test-Function "Measure-ExecutionTime measures execution" {
        $result = Measure-ExecutionTime -ScriptBlock { Start-Sleep -Milliseconds 100 } -Description "Test sleep"
        return ($result -is [hashtable] -and 
                $result.ContainsKey('Duration') -and 
                $result.ContainsKey('Success') -and
                $result.Success -eq $true)
    }
    
    # Test Test-InternetConnectivity
    Test-Function "Test-InternetConnectivity tests connectivity" {
        # This test should not require actual internet connectivity
        # Just verify the function returns a result structure (may indicate failure if offline)
        $results = Test-InternetConnectivity -TestUrls @('https://www.google.com') -TimeoutSeconds 2
        # Should return an array regardless of connectivity status
        return ($results -is [array])
    }
    
    # Test Get-EnvironmentInfo
    Test-Function "Get-EnvironmentInfo returns environment info" {
        $envInfo = Get-EnvironmentInfo
        return ($envInfo -is [hashtable] -and 
                $envInfo.ContainsKey('PowerShellVersion') -and 
                $envInfo.ContainsKey('ComputerName') -and
                $envInfo.ContainsKey('WorkingDirectory'))
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
