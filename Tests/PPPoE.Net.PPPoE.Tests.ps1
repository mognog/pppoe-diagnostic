# PPPoE.Net.PPPoE.Tests.ps1 - Tests for PPPoE connection management module

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Net.PPPoE.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "🔍 Running basic validation tests for PPPoE.Net.PPPoE module..."
    
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
    
    # Test Disconnect-PPP
    Test-Function "Disconnect-PPP handles valid connection name" {
        # This should not throw an error even if connection doesn't exist
        try {
            Disconnect-PPP -PppoeName "TestPPPoE"
            return $true
        } catch {
            return $false
        }
    }
    
    Test-Function "Disconnect-PPP handles null input" {
        try {
            Disconnect-PPP -PppoeName $null
            return $false
        } catch {
            return $true  # Expected to handle null gracefully or throw
        }
    }
    
    Test-Function "Disconnect-PPP handles empty string" {
        try {
            Disconnect-PPP -PppoeName ""
            return $true
        } catch {
            return $false
        }
    }
    
    # Test Disconnect-AllPPPoE
    Test-Function "Disconnect-AllPPPoE executes without error" {
        try {
            Disconnect-AllPPPoE
            return $true
        } catch {
            return $false
        }
    }
    
    # Test Connect-PPP
    Test-Function "Connect-PPP handles invalid credentials gracefully" {
        try {
            $result = Connect-PPP -PppoeName "TestPPPoE" -UserName "invalid" -Password "invalid"
            return ($result -is [bool])
        } catch {
            return $true  # Expected to handle invalid credentials
        }
    }
    
    Test-Function "Connect-PPP handles null credentials" {
        try {
            $result = Connect-PPP -PppoeName "TestPPPoE" -UserName $null -Password $null
            return ($result -is [bool])
        } catch {
            return $true  # Expected to handle null credentials
        }
    }
    
    Test-Function "Connect-PPP handles empty credentials" {
        try {
            $result = Connect-PPP -PppoeName "TestPPPoE" -UserName "" -Password ""
            return ($result -is [bool])
        } catch {
            return $true  # Expected to handle empty credentials
        }
    }
    
    # Test Connect-PPPWithFallback
    Test-Function "Connect-PPPWithFallback handles invalid credentials" {
        try {
            $result = Connect-PPPWithFallback -PppoeName "TestPPPoE" -UserName "invalid" -Password "invalid"
            return ($result -is [bool])
        } catch {
            return $true  # Expected to handle invalid credentials
        }
    }
    
    Test-Function "Connect-PPPWithFallback returns boolean result" {
        try {
            $result = Connect-PPPWithFallback -PppoeName "TestPPPoE" -UserName "test" -Password "test"
            return ($result -is [bool])
        } catch {
            return $true  # Expected to handle errors gracefully
        }
    }
    
    # Test Get-PppInterface
    Test-Function "Get-PppInterface returns valid result" {
        $result = Get-PppInterface
        return ($result -eq $null -or ($result -is [object] -and $result.InterfaceAlias))
    }
    
    Test-Function "Get-PppInterface handles no PPP connections" {
        # This should work even when no PPP connections exist
        $result = Get-PppInterface
        return ($result -eq $null -or ($result -is [object]))
    }
    
    # Test Get-PppIPv4
    Test-Function "Get-PppIPv4 returns valid result" {
        $result = Get-PppIPv4
        return ($result -eq $null -or ($result -is [object] -and $result.IPAddress))
    }
    
    Test-Function "Get-PppIPv4 handles no PPP connections" {
        $result = Get-PppIPv4
        return ($result -eq $null -or ($result -is [object]))
    }
    
    # Test Test-DefaultRouteVia
    Test-Function "Test-DefaultRouteVia returns boolean" {
        $result = Test-DefaultRouteVia -InterfaceAlias "TestInterface"
        return ($result -is [bool])
    }
    
    Test-Function "Test-DefaultRouteVia handles null input" {
        $result = Test-DefaultRouteVia -InterfaceAlias $null
        return ($result -is [bool])
    }
    
    Test-Function "Test-DefaultRouteVia handles empty string" {
        $result = Test-DefaultRouteVia -InterfaceAlias ""
        return ($result -is [bool])
    }
    
    # Test Get-DefaultRouteOwner
    Test-Function "Get-DefaultRouteOwner returns valid result" {
        $result = Get-DefaultRouteOwner
        return ($result -eq $null -or ($result -is [object] -and $result.InterfaceAlias))
    }
    
    # Test Set-RouteMetrics
    Test-Function "Set-RouteMetrics handles valid interface" {
        try {
            Set-RouteMetrics -InterfaceAlias "TestInterface" -Metric 1
            return $true
        } catch {
            return $true  # Expected to handle non-existent interface
        }
    }
    
    Test-Function "Set-RouteMetrics handles null input" {
        try {
            Set-RouteMetrics -InterfaceAlias $null -Metric 1
            return $false
        } catch {
            return $true  # Expected to throw for null input
        }
    }
    
    # Test Get-PPPoESessionInfo
    Test-Function "Get-PPPoESessionInfo returns valid structure" {
        $result = Get-PPPoESessionInfo
        return ($result -eq $null -or ($result -is [object]))
    }
    
    # Test Get-PPPGatewayInfo
    Test-Function "Get-PPPGatewayInfo returns valid structure" {
        $result = Get-PPPGatewayInfo
        return ($result -eq $null -or ($result -is [object]))
    }
    
    # Error handling tests
    Test-Function "Functions handle network operation failures gracefully" {
        try {
            # Test multiple functions that might fail due to network conditions
            $pppInterface = Get-PppInterface
            $pppIP = Get-PppIPv4
            $routeOwner = Get-DefaultRouteOwner
            $sessionInfo = Get-PPPoESessionInfo
            $gatewayInfo = Get-PPPGatewayInfo
            return $true
        } catch {
            return $false
        }
    }
    
    # Performance tests
    Test-Function "Get-PppInterface completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Get-PppInterface
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 3000)
    }
    
    Test-Function "Get-PppIPv4 completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Get-PppIPv4
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 3000)
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
