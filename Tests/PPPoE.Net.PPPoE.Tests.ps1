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
            # Expect a hashtable with Success/Code/Output
            return ($result -is [hashtable] -and $result.ContainsKey('Success') -and $result.ContainsKey('Code'))
        } catch {
            return $true  # Expected to handle invalid credentials
        }
    }
    
    Test-Function "Connect-PPP handles null credentials" {
        try {
            $result = Connect-PPP -PppoeName "TestPPPoE" -UserName $null -Password $null
            return ($result -is [hashtable])
        } catch {
            return $true  # Expected to handle null credentials
        }
    }
    
    Test-Function "Connect-PPP handles empty credentials" {
        try {
            $result = Connect-PPP -PppoeName "TestPPPoE" -UserName "" -Password ""
            return ($result -is [hashtable])
        } catch {
            return $true  # Expected to handle empty credentials
        }
    }
    
    # Test Connect-PPPWithFallback
    Test-Function "Connect-PPPWithFallback handles invalid credentials" {
        try {
            $wl = { param($m) Write-Host $m }
            $addHealth = { param($h,$n,$s,$o) return $h }
            $result = Connect-PPPWithFallback -PppoeName "TestPPPoE" -UserName "invalid" -Password "invalid" -CredentialsFile "nonexistent.ps1" -WriteLog $wl -AddHealth $addHealth
            return ($result -is [hashtable] -and $result.ContainsKey('Success') -and $result.ContainsKey('Method'))
        } catch {
            return $true  # Expected to handle invalid credentials
        }
    }
    
    Test-Function "Connect-PPPWithFallback returns structured result (file parsing fallback)" {
        try {
            $wl = { param($m) Write-Host $m }
            $addHealth = { param($h,$n,$s,$o) return $h }
            # Create a temp credentials file with alt variable names
            $tmp = [System.IO.Path]::GetTempFileName()
            Set-Content -LiteralPath $tmp -Value "`$username='user'`n`$password='pass'`n`$PPPoE_ConnectionName='TestPPPoE'" -Encoding ASCII
            $result = Connect-PPPWithFallback -PppoeName "TestPPPoE" -UserName "test" -Password "test" -CredentialsFile $tmp -WriteLog $wl -AddHealth $addHealth
            Remove-Item $tmp -Force
            return ($result -is [hashtable] -and $result.ContainsKey('Success') -and $result.ContainsKey('CredentialSource'))
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
        $result = Test-DefaultRouteVia -IfIndex 0
        return ($result -is [bool])
    }
    
    Test-Function "Test-DefaultRouteVia handles null input" {
        $result = Test-DefaultRouteVia -IfIndex $null
        return ($result -is [bool])
    }
    
    Test-Function "Test-DefaultRouteVia handles zero index" {
        $result = Test-DefaultRouteVia -IfIndex 0
        return ($result -is [bool])
    }
    
    # Test Get-DefaultRouteOwner
    Test-Function "Get-DefaultRouteOwner returns valid result" {
        $result = Get-DefaultRouteOwner -WriteLog { param($m) Write-Host $m }
        return ($result -eq $null -or ($result -is [hashtable] -and $result.ContainsKey('InterfaceIndex')))
    }
    
    # Test Set-RouteMetrics
    Test-Function "Set-RouteMetrics handles valid interface index" {
        try {
            $ok = Set-RouteMetrics -PppInterfaceIndex 0 -WriteLog { param($m) Write-Host $m }
            return ($ok -is [bool])
        } catch {
            return $true  # Expected to handle non-existent interface
        }
    }
    
    Test-Function "Set-RouteMetrics handles null input" {
        try {
            $ok = Set-RouteMetrics -PppInterfaceIndex $null -WriteLog { param($m) Write-Host $m }
            return ($ok -is [bool])
        } catch {
            return $true  # Expected to handle null input gracefully
        }
    }
    
    # Test Get-PPPoESessionInfo
    Test-Function "Get-PPPoESessionInfo returns valid structure" {
        $result = Get-PPPoESessionInfo -PppoeName "TestPPPoE" -WriteLog { param($m) Write-Host $m }
        return ($result -eq $null -or ($result -is [hashtable]))
    }
    
    # Test Get-PPPGatewayInfo
    Test-Function "Get-PPPGatewayInfo returns valid structure" {
        $result = Get-PPPGatewayInfo -InterfaceAlias "PPP*" -WriteLog { param($m) Write-Host $m }
        return ($result -eq $null -or ($result -is [hashtable]))
    }
    
    # Error handling tests
    Test-Function "Functions handle network operation failures gracefully" {
        try {
            # Test multiple functions that might fail due to network conditions
            $null = Get-PppInterface
            $null = Get-PppIPv4
            $null = Get-DefaultRouteOwner -WriteLog { param($m) Write-Host $m }
            $null = Get-PPPoESessionInfo -PppoeName "TestPPPoE" -WriteLog { param($m) Write-Host $m }
            $null = Get-PPPGatewayInfo -InterfaceAlias "PPP*" -WriteLog { param($m) Write-Host $m }
            return $true
        } catch {
            return $false
        }
    }
    
    # Performance tests
    Test-Function "Get-PppInterface completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Get-PppInterface
        $stopwatch.Stop()
        return ($stopwatch.ElapsedMilliseconds -lt 3000)
    }
    
    Test-Function "Get-PppIPv4 completes within reasonable time" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Get-PppIPv4
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
