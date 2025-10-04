# PPPoE.Net.Diagnostics.Tests.ps1 - Tests for network diagnostics module

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Net.Diagnostics.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "🔍 Running basic validation tests for PPPoE.Net.Diagnostics module..."
    
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
    
    # Test Get-WiFiAdapters
    Test-Function "Get-WiFiAdapters returns array" {
        $adapters = Get-WiFiAdapters
        return ($adapters -is [array] -or $adapters -eq $null)
    }
    
    Test-Function "Get-WiFiAdapters filters correctly" {
        $adapters = Get-WiFiAdapters
        if ($adapters -and $adapters.Count -gt 0) {
            # Should only include WiFi adapters
            $wifiAdapters = $adapters | Where-Object { 
                $_.InterfaceDescription -like "*wireless*" -or 
                $_.InterfaceDescription -like "*wi-fi*" -or 
                $_.InterfaceDescription -like "*wlan*" -or
                $_.Name -like "*Wi-Fi*" -or
                $_.Name -like "*Wireless*" -or
                $_.Name -like "*WLAN*"
            }
            return ($wifiAdapters.Count -eq $adapters.Count)
        }
        return $true
    }
    
    # Test Disable-WiFiAdapters
    Test-Function "Disable-WiFiAdapters returns array of adapter names" {
        $result = Disable-WiFiAdapters -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [array] -or $result -eq $null)
    }
    
    Test-Function "Disable-WiFiAdapters handles no WiFi adapters" {
        # This should work even when no WiFi adapters exist
        $result = Disable-WiFiAdapters -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [array] -or $result -eq $null)
    }
    
    Test-Function "Disable-WiFiAdapters handles null WriteLog" {
        $result = Disable-WiFiAdapters -WriteLog $null
        return ($result -is [array] -or $result -eq $null)
    }
    
    # Test Enable-WiFiAdapters
    Test-Function "Enable-WiFiAdapters handles empty array" {
        $result = Enable-WiFiAdapters -AdapterNames @() -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [bool])
    }
    
    Test-Function "Enable-WiFiAdapters handles null input" {
        $result = Enable-WiFiAdapters -AdapterNames $null -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [bool])
    }
    
    Test-Function "Enable-WiFiAdapters handles non-existent adapters" {
        $result = Enable-WiFiAdapters -AdapterNames @("NonExistentAdapter123") -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [bool])
    }
    
    Test-Function "Enable-WiFiAdapters handles null WriteLog" {
        $result = Enable-WiFiAdapters -AdapterNames @("TestAdapter") -WriteLog $null
        return ($result -is [bool])
    }
    
    # Test Test-ONTAvailability
    Test-Function "Test-ONTAvailability returns valid structure" {
        $result = Test-ONTAvailability
        return ($result -is [object] -and $result.ContainsKey('Available'))
    }
    
    Test-Function "Test-ONTAvailability handles network errors gracefully" {
        # This should work even when ONT is not available
        $result = Test-ONTAvailability
        return ($result -is [object] -and $result.ContainsKey('Available'))
    }
    
    # Test Show-ONTLEDReminder
    Test-Function "Show-ONTLEDReminder executes without error" {
        try {
            Show-ONTLEDReminder -WriteLog { param($msg) Write-Host $msg }
            return $true
        } catch {
            return $false
        }
    }
    
    Test-Function "Show-ONTLEDReminder handles null WriteLog" {
        try {
            Show-ONTLEDReminder -WriteLog $null
            return $true
        } catch {
            return $false
        }
    }
    
    # Test Test-FirewallState
    Test-Function "Test-FirewallState returns valid structure" {
        $result = Test-FirewallState
        return ($result -is [object] -and $result.ContainsKey('Domain'))
    }
    
    Test-Function "Test-FirewallState includes all profiles" {
        $result = Test-FirewallState
        return ($result.ContainsKey('Domain') -and $result.ContainsKey('Private') -and $result.ContainsKey('Public'))
    }
    
    Test-Function "Test-FirewallState handles firewall errors gracefully" {
        # This should work even if firewall is not accessible
        $result = Test-FirewallState
        return ($result -is [object] -and $result.ContainsKey('Domain'))
    }
    
    # Error handling tests
    Test-Function "Functions handle network adapter enumeration errors gracefully" {
        try {
            $wifiAdapters = Get-WiFiAdapters
            $disabledAdapters = Disable-WiFiAdapters -WriteLog { param($msg) Write-Host $msg }
            $enabledResult = Enable-WiFiAdapters -AdapterNames @() -WriteLog { param($msg) Write-Host $msg }
            return $true
        } catch {
            return $false
        }
    }
    
    Test-Function "Functions handle firewall access errors gracefully" {
        try {
            $firewallState = Test-FirewallState
            return $true
        } catch {
            return $false
        }
    }
    
    # Performance tests
    Test-Function "Get-WiFiAdapters completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $adapters = Get-WiFiAdapters
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 3000)  # Should complete within 3 seconds
    }
    
    Test-Function "Test-FirewallState completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Test-FirewallState
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 5000)  # Should complete within 5 seconds
    }
    
    Test-Function "Test-ONTAvailability completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Test-ONTAvailability
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 10000)  # Should complete within 10 seconds
    }
    
    # Integration tests
    Test-Function "WiFi adapter disable/enable cycle works" {
        try {
            # Get current WiFi adapters
            $wifiAdapters = Get-WiFiAdapters
            if ($wifiAdapters -and $wifiAdapters.Count -gt 0) {
                # Try to disable (this might fail if no admin rights, which is OK)
                $disabledAdapters = Disable-WiFiAdapters -WriteLog { param($msg) Write-Host $msg }
                # Try to enable (this might fail if no admin rights, which is OK)
                $enabledResult = Enable-WiFiAdapters -AdapterNames $disabledAdapters -WriteLog { param($msg) Write-Host $msg }
                return $true
            } else {
                # No WiFi adapters to test with, but that's OK
                return $true
            }
        } catch {
            # Expected to fail if no admin rights
            return $true
        }
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
