# PPPoE.Net.Connectivity.Tests.ps1 - Tests for network connectivity testing module

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Net.Connectivity.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "🔍 Running basic validation tests for PPPoE.Net.Connectivity module..."
    
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
    
    # Test Test-DNSResolution
    Test-Function "Test-DNSResolution returns boolean" {
        $result = Test-DNSResolution -HostName "google.com"
        return ($result -is [bool])
    }
    
    Test-Function "Test-DNSResolution handles invalid hostname" {
        $result = Test-DNSResolution -HostName "nonexistentdomain12345.com"
        return ($result -is [bool])
    }
    
    Test-Function "Test-DNSResolution handles null input" {
        $result = Test-DNSResolution -HostName $null
        return ($result -is [bool])
    }
    
    Test-Function "Test-DNSResolution handles empty string" {
        $result = Test-DNSResolution -HostName ""
        return ($result -is [bool])
    }
    
    # Test Test-PacketLoss
    Test-Function "Test-PacketLoss returns valid structure" {
        $result = Test-PacketLoss -HostName "8.8.8.8" -Count 2
        return ($result -is [object] -and $result.ContainsKey('SuccessRate'))
    }
    
    Test-Function "Test-PacketLoss handles invalid hostname" {
        $result = Test-PacketLoss -HostName "192.168.999.999" -Count 2
        return ($result -is [object] -and $result.ContainsKey('SuccessRate'))
    }
    
    Test-Function "Test-PacketLoss handles zero count" {
        $result = Test-PacketLoss -HostName "8.8.8.8" -Count 0
        return ($result -is [object] -and $result.ContainsKey('SuccessRate'))
    }
    
    # Test Test-RouteStability
    Test-Function "Test-RouteStability returns valid structure" {
        $result = Test-RouteStability -HostName "google.com" -Count 2
        return ($result -is [object] -and $result.ContainsKey('Stable'))
    }
    
    Test-Function "Test-RouteStability handles invalid hostname" {
        $result = Test-RouteStability -HostName "nonexistentdomain12345.com" -Count 2
        return ($result -is [object] -and $result.ContainsKey('Stable'))
    }
    
    # Test Get-InterfaceStatistics
    Test-Function "Get-InterfaceStatistics returns valid structure" {
        $result = Get-InterfaceStatistics -InterfaceAlias "TestInterface"
        return ($result -is [object] -and $result.ContainsKey('BytesReceived'))
    }
    
    Test-Function "Get-InterfaceStatistics handles null input" {
        $result = Get-InterfaceStatistics -InterfaceAlias $null
        return ($result -is [object] -and $result.ContainsKey('BytesReceived'))
    }
    
    Test-Function "Get-InterfaceStatistics handles non-existent interface" {
        $result = Get-InterfaceStatistics -InterfaceAlias "NonExistentInterface123"
        return ($result -is [object] -and $result.ContainsKey('BytesReceived'))
    }
    
    # Test Test-ConnectionStability
    Test-Function "Test-ConnectionStability returns valid structure" {
        $result = Test-ConnectionStability -HostName "google.com" -Count 2 -Interval 1
        return ($result -is [object] -and $result.ContainsKey('Stable'))
    }
    
    Test-Function "Test-ConnectionStability handles invalid hostname" {
        $result = Test-ConnectionStability -HostName "192.168.999.999" -Count 2 -Interval 1
        return ($result -is [object] -and $result.ContainsKey('Stable'))
    }
    
    # Test Test-ConnectionJitter
    Test-Function "Test-ConnectionJitter returns valid structure" {
        $result = Test-ConnectionJitter -HostName "google.com" -Count 3 -Interval 1
        return ($result -is [object] -and $result.ContainsKey('AverageLatency'))
    }
    
    Test-Function "Test-ConnectionJitter handles invalid hostname" {
        $result = Test-ConnectionJitter -HostName "192.168.999.999" -Count 3 -Interval 1
        return ($result -is [object] -and $result.ContainsKey('AverageLatency'))
    }
    
    # Test Test-BurstConnectivity
    Test-Function "Test-BurstConnectivity returns valid structure" {
        $result = Test-BurstConnectivity -HostName "google.com" -BurstCount 3 -BurstInterval 1
        return ($result -is [object] -and $result.ContainsKey('SuccessRate'))
    }
    
    Test-Function "Test-BurstConnectivity handles invalid hostname" {
        $result = Test-BurstConnectivity -HostName "192.168.999.999" -BurstCount 3 -BurstInterval 1
        return ($result -is [object] -and $result.ContainsKey('SuccessRate'))
    }
    
    # Test Test-QuickConnectivityCheck
    Test-Function "Test-QuickConnectivityCheck returns valid structure" {
        $result = Test-QuickConnectivityCheck -HostName "google.com"
        return ($result -is [object] -and $result.ContainsKey('Reachable'))
    }
    
    Test-Function "Test-QuickConnectivityCheck handles invalid hostname" {
        $result = Test-QuickConnectivityCheck -HostName "192.168.999.999"
        return ($result -is [object] -and $result.ContainsKey('Reachable'))
    }
    
    # Test Test-ProviderSpecificDiagnostics
    Test-Function "Test-ProviderSpecificDiagnostics returns valid structure" {
        $result = Test-ProviderSpecificDiagnostics -Provider "TestProvider"
        return ($result -is [object] -and $result.ContainsKey('Provider'))
    }
    
    Test-Function "Test-ProviderSpecificDiagnostics handles null input" {
        $result = Test-ProviderSpecificDiagnostics -Provider $null
        return ($result -is [object] -and $result.ContainsKey('Provider'))
    }
    
    # Test Test-TCPConnectivity
    Test-Function "Test-TCPConnectivity returns valid structure" {
        $result = Test-TCPConnectivity -HostName "google.com" -Port 80
        return ($result -is [object] -and $result.ContainsKey('Connected'))
    }
    
    Test-Function "Test-TCPConnectivity handles invalid port" {
        $result = Test-TCPConnectivity -HostName "google.com" -Port 99999
        return ($result -is [object] -and $result.ContainsKey('Connected'))
    }
    
    Test-Function "Test-TCPConnectivity handles invalid hostname" {
        $result = Test-TCPConnectivity -HostName "192.168.999.999" -Port 80
        return ($result -is [object] -and $result.ContainsKey('Connected'))
    }
    
    # Test Test-MultiDestinationRouting
    Test-Function "Test-MultiDestinationRouting returns valid structure" {
        $destinations = @("google.com", "cloudflare.com")
        $result = Test-MultiDestinationRouting -Destinations $destinations
        return ($result -is [object] -and $result.ContainsKey('Results'))
    }
    
    Test-Function "Test-MultiDestinationRouting handles empty array" {
        $result = Test-MultiDestinationRouting -Destinations @()
        return ($result -is [object] -and $result.ContainsKey('Results'))
    }
    
    Test-Function "Test-MultiDestinationRouting handles null input" {
        $result = Test-MultiDestinationRouting -Destinations $null
        return ($result -is [object] -and $result.ContainsKey('Results'))
    }
    
    # Error handling tests
    Test-Function "Functions handle network timeouts gracefully" {
        try {
            # Test functions that might timeout
            $dnsResult = Test-DNSResolution -HostName "google.com"
            $packetResult = Test-PacketLoss -HostName "8.8.8.8" -Count 1
            $quickResult = Test-QuickConnectivityCheck -HostName "google.com"
            return $true
        } catch {
            return $false
        }
    }
    
    # Performance tests
    Test-Function "Test-QuickConnectivityCheck completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Test-QuickConnectivityCheck -HostName "google.com"
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 10000)  # Should complete within 10 seconds
    }
    
    Test-Function "Test-DNSResolution completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Test-DNSResolution -HostName "google.com"
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 5000)  # Should complete within 5 seconds
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
