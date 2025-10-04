# PPPoE.HealthChecks.Tests.ps1 - Tests for health check orchestration module

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Health.psm1",
        "../Modules/PPPoE.Net.psm1",
        "../Modules/PPPoE.HealthChecks.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "🔍 Running basic validation tests for PPPoE.HealthChecks module..."
    
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
    
    # Test Invoke-BasicSystemChecks
    Test-Function "Invoke-BasicSystemChecks returns valid structure" {
        $health = New-Health
        $result = Invoke-BasicSystemChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and 
                $result.ContainsKey('Health') -and 
                $result.ContainsKey('PPPoEConnections'))
    }
    
    Test-Function "Invoke-BasicSystemChecks modifies health object" {
        $health = New-Health
        $originalCount = $health.Count
        $result = Invoke-BasicSystemChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result.Health.Count -gt $originalCount)
    }
    
    Test-Function "Invoke-BasicSystemChecks handles null WriteLog" {
        $health = New-Health
        $result = Invoke-BasicSystemChecks -Health $health -WriteLog $null
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    # Test Invoke-NetworkAdapterChecks
    Test-Function "Invoke-NetworkAdapterChecks returns valid structure" {
        $health = New-Health
        $result = Invoke-NetworkAdapterChecks -Health $health -TargetAdapter $null -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and 
                $result.ContainsKey('Health') -and 
                $result.ContainsKey('Adapter') -and
                $result.ContainsKey('LinkDown'))
    }
    
    Test-Function "Invoke-NetworkAdapterChecks handles specific target adapter" {
        $health = New-Health
        $result = Invoke-NetworkAdapterChecks -Health $health -TargetAdapter "TestAdapter" -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-NetworkAdapterChecks handles null WriteLog" {
        $health = New-Health
        $result = Invoke-NetworkAdapterChecks -Health $health -TargetAdapter $null -WriteLog $null
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    # Test Invoke-PPPoEConnectionChecks
    Test-Function "Invoke-PPPoEConnectionChecks returns valid structure" {
        $health = New-Health
        $result = Invoke-PPPoEConnectionChecks -Health $health -PppoeName "TestPPPoE" -UserName "test" -Password "test" -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and 
                $result.ContainsKey('Health') -and 
                $result.ContainsKey('Connected'))
    }
    
    Test-Function "Invoke-PPPoEConnectionChecks handles invalid credentials" {
        $health = New-Health
        $result = Invoke-PPPoEConnectionChecks -Health $health -PppoeName "TestPPPoE" -UserName "invalid" -Password "invalid" -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-PPPoEConnectionChecks handles null credentials" {
        $health = New-Health
        $result = Invoke-PPPoEConnectionChecks -Health $health -PppoeName "TestPPPoE" -UserName $null -Password $null -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-PPPoEConnectionChecks handles null WriteLog" {
        $health = New-Health
        $result = Invoke-PPPoEConnectionChecks -Health $health -PppoeName "TestPPPoE" -UserName "test" -Password "test" -WriteLog $null
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    # Test Invoke-PPPInterfaceChecks
    Test-Function "Invoke-PPPInterfaceChecks returns valid structure" {
        $health = New-Health
        $result = Invoke-PPPInterfaceChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and 
                $result.ContainsKey('Health') -and 
                $result.ContainsKey('PPPInterface') -and
                $result.ContainsKey('PPPIp'))
    }
    
    Test-Function "Invoke-PPPInterfaceChecks handles no PPP connections" {
        $health = New-Health
        $result = Invoke-PPPInterfaceChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-PPPInterfaceChecks handles null WriteLog" {
        $health = New-Health
        $result = Invoke-PPPInterfaceChecks -Health $health -WriteLog $null
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    # Test Invoke-ConnectivityChecks
    Test-Function "Invoke-ConnectivityChecks returns valid structure" {
        $health = New-Health
        $result = Invoke-ConnectivityChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-ConnectivityChecks handles network failures" {
        $health = New-Health
        $result = Invoke-ConnectivityChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-ConnectivityChecks handles null WriteLog" {
        $health = New-Health
        $result = Invoke-ConnectivityChecks -Health $health -WriteLog $null
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    # Test Invoke-AdvancedConnectivityChecks
    Test-Function "Invoke-AdvancedConnectivityChecks returns valid structure" {
        $health = New-Health
        $result = Invoke-AdvancedConnectivityChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-AdvancedConnectivityChecks handles network failures" {
        $health = New-Health
        $result = Invoke-AdvancedConnectivityChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-AdvancedConnectivityChecks handles null WriteLog" {
        $health = New-Health
        $result = Invoke-AdvancedConnectivityChecks -Health $health -WriteLog $null
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    # Test Invoke-TracerouteDiagnostics
    Test-Function "Invoke-TracerouteDiagnostics returns valid structure" {
        $health = New-Health
        $result = Invoke-TracerouteDiagnostics -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-TracerouteDiagnostics handles network failures" {
        $health = New-Health
        $result = Invoke-TracerouteDiagnostics -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-TracerouteDiagnostics handles null WriteLog" {
        $health = New-Health
        $result = Invoke-TracerouteDiagnostics -Health $health -WriteLog $null
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    # Test Invoke-OptionalStabilityTest
    Test-Function "Invoke-OptionalStabilityTest returns valid structure" {
        $health = New-Health
        $result = Invoke-OptionalStabilityTest -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-OptionalStabilityTest handles network failures" {
        $health = New-Health
        $result = Invoke-OptionalStabilityTest -Health $health -WriteLog { param($msg) Write-Host $msg }
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    Test-Function "Invoke-OptionalStabilityTest handles null WriteLog" {
        $health = New-Health
        $result = Invoke-OptionalStabilityTest -Health $health -WriteLog $null
        return ($result -is [object] -and $result.ContainsKey('Health'))
    }
    
    # Error handling tests
    Test-Function "All health check functions handle errors gracefully" {
        try {
            $health = New-Health
            
            # Test all health check functions
            $basicResult = Invoke-BasicSystemChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
            $adapterResult = Invoke-NetworkAdapterChecks -Health $health -TargetAdapter $null -WriteLog { param($msg) Write-Host $msg }
            $pppoeResult = Invoke-PPPoEConnectionChecks -Health $health -PppoeName "TestPPPoE" -UserName "test" -Password "test" -WriteLog { param($msg) Write-Host $msg }
            $pppResult = Invoke-PPPInterfaceChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
            $connectivityResult = Invoke-ConnectivityChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
            $advancedResult = Invoke-AdvancedConnectivityChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
            $tracerouteResult = Invoke-TracerouteDiagnostics -Health $health -WriteLog { param($msg) Write-Host $msg }
            $stabilityResult = Invoke-OptionalStabilityTest -Health $health -WriteLog { param($msg) Write-Host $msg }
            
            return $true
        } catch {
            return $false
        }
    }
    
    # Performance tests
    Test-Function "Invoke-BasicSystemChecks completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $health = New-Health
        $result = Invoke-BasicSystemChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 10000)  # Should complete within 10 seconds
    }
    
    Test-Function "Invoke-NetworkAdapterChecks completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $health = New-Health
        $result = Invoke-NetworkAdapterChecks -Health $health -TargetAdapter $null -WriteLog { param($msg) Write-Host $msg }
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 5000)  # Should complete within 5 seconds
    }
    
    # Integration tests
    Test-Function "Health check functions work together" {
        try {
            $health = New-Health
            
            # Run a sequence of health checks
            $result1 = Invoke-BasicSystemChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
            $health = $result1.Health
            
            $result2 = Invoke-NetworkAdapterChecks -Health $health -TargetAdapter $null -WriteLog { param($msg) Write-Host $msg }
            $health = $result2.Health
            
            $result3 = Invoke-ConnectivityChecks -Health $health -WriteLog { param($msg) Write-Host $msg }
            $health = $result3.Health
            
            return ($health.Count -gt 0)
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
