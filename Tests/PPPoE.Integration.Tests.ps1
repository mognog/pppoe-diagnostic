# PPPoE.Integration.Tests.ps1 - Integration tests for the complete diagnostic workflow
# Tests how all modules work together

# Import all modules
$modulePaths = @(
    "..\Modules\PPPoE.Core.psm1",
    "..\Modules\PPPoE.Health.psm1",
    "..\Modules\PPPoE.Net.psm1",
    "..\Modules\PPPoE.Logging.psm1"
)

foreach ($modulePath in $modulePaths) {
    $fullPath = Join-Path $PSScriptRoot $modulePath
    Import-Module $fullPath -Force
}

# Check if Pester is available
$pesterAvailable = $false
try {
    Import-Module Pester -Force -ErrorAction Stop
    $pesterAvailable = $true
    Write-Host "✅ Pester available - using full test framework" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Pester not available - using basic validation" -ForegroundColor Yellow
}

if ($pesterAvailable) {
    Describe "PPPoE Integration Tests" {
        
        Describe "End-to-End Diagnostic Flow" {
            It "Should complete basic health check workflow" {
                # Test the health checking system
                $Health = New-Health
                
                # Simulate typical diagnostic checks
                $Health = Add-Health $Health 'PowerShell version' "OK ($($PSVersionTable.PSVersion))" 1
                $Health = Add-Health $Health 'Test connection' 'OK' 2
                
                $Health.Count | Should -BeGreaterThan 0
                $Health.ContainsKey('01_PowerShell version') | Should -Be $true
                $Health.ContainsKey('02_Test connection') | Should -Be $true
                
                # Test health summary generation
                { Write-HealthSummary -Health $Health } | Should -Not -Throw
            }
            
            It "Should handle network adapter detection workflow" {
                # Test the network adapter workflow
                $adapters = Get-CandidateEthernetAdapters
                $recommended = Get-RecommendedAdapter
                
                # Should return valid results (could be empty if no adapters)
                $adapters | Should -Not -BeNullOrEmpty
                if ($recommended) {
                    $recommended | Should -HaveMember "Name"
                    $recommended | Should -HaveMember "InterfaceDescription"
                }
            }
            
            It "Should handle connectivity testing workflow" {
                # Test basic connectivity (using localhost to avoid network dependencies)
                $result = Test-PingHost -TargetName "127.0.0.1" -Count 1
                
                $result | Should -BeOfType [bool]
                # Should succeed with localhost
                $result | Should -Be $true
            }
        }
        
        Describe "Module Integration" {
            It "Should integrate Core and Health modules" {
                # Test that Core functions work with Health system
                $Health = New-Health
                
                # Test PowerShell version check
                if (Test-PwshVersion7Plus) {
                    $Health = Add-Health $Health 'PowerShell version' "OK ($($PSVersionTable.PSVersion))" 1
                } else {
                    $Health = Add-Health $Health 'PowerShell version' "FAIL ($($PSVersionTable.PSVersion))" 1
                }
                
                $Health.Count | Should -BeGreaterThan 0
            }
            
            It "Should integrate Net and Health modules" {
                # Test that Network functions work with Health system
                $Health = New-Health
                
                # Test adapter detection
                $adapters = Get-CandidateEthernetAdapters
                if ($adapters -and $adapters.Count -gt 0) {
                    $Health = Add-Health $Health 'Physical adapter detected' "OK ($($adapters.Count) found)" 3
                } else {
                    $Health = Add-Health $Health 'Physical adapter detected' 'FAIL (none found)' 3
                }
                
                $Health.Count | Should -BeGreaterThan 0
            }
        }
        
        Describe "Error Handling Integration" {
            It "Should handle network errors gracefully" {
                # Test error handling in network functions
                $result = Test-PingHost -TargetName "nonexistent.invalid" -Count 1
                $result | Should -BeOfType [bool]
                $result | Should -Be $false
            }
            
            It "Should handle health system with errors" {
                $Health = New-Health
                
                # Add both success and failure items
                $Health = Add-Health $Health 'Success test' 'OK' 1
                $Health = Add-Health $Health 'Failure test' 'FAIL' 2
                
                $Health.Count | Should -Be 2
                { Write-HealthSummary -Health $Health } | Should -Not -Throw
            }
        }
        
        Describe "Logging Integration" {
            It "Should handle logging functions without errors" {
                # Test that logging functions work
                { Write-Log "Integration test message" } | Should -Not -Throw
                { Write-Ok "Integration test success" } | Should -Not -Throw
                { Write-Warn "Integration test warning" } | Should -Not -Throw
                { Write-Err "Integration test error" } | Should -Not -Throw
            }
        }
        
        Describe "Real-World Scenarios" {
            It "Should simulate complete diagnostic session" {
                # Simulate a complete diagnostic session
                $Health = New-Health
                
                # 1. PowerShell version check
                if (Test-PwshVersion7Plus) {
                    $Health = Add-Health $Health 'PowerShell version' "OK ($($PSVersionTable.PSVersion))" 1
                } else {
                    $Health = Add-Health $Health 'PowerShell version' "FAIL ($($PSVersionTable.PSVersion))" 1
                }
                
                # 2. Network adapter detection
                $adapters = Get-CandidateEthernetAdapters
                if ($adapters -and $adapters.Count -gt 0) {
                    $recommended = Get-RecommendedAdapter
                    if ($recommended) {
                        $Health = Add-Health $Health 'Physical adapter detected' "OK ($($recommended.InterfaceDescription))" 3
                    } else {
                        $Health = Add-Health $Health 'Physical adapter detected' 'WARN (no recommended adapter)' 3
                    }
                } else {
                    $Health = Add-Health $Health 'Physical adapter detected' 'FAIL (none found)' 3
                }
                
                # 3. Basic connectivity test
                $connectivityOk = Test-PingHost -TargetName "127.0.0.1" -Count 1
                $Health = Add-Health $Health 'Basic connectivity' ($connectivityOk ? 'OK' : 'FAIL') 10
                
                # Verify we have a reasonable number of health checks
                $Health.Count | Should -BeGreaterOrEqual 3
                
                # Verify health summary works
                { Write-HealthSummary -Health $Health } | Should -Not -Throw
            }
        }
    }
} else {
    # Basic validation without Pester
    Write-Host "🔍 Running basic integration tests..." -ForegroundColor Cyan
    
    $testResults = @{
        Passed = 0
        Failed = 0
        Tests = @()
    }
    
    function Test-Function {
        param([string]$TestName, [scriptblock]$TestScript)
        try {
            $result = & $TestScript
            $testResults.Tests += @{ Name = $TestName; Status = "PASS"; Result = $result }
            $testResults.Passed++
            Write-Host "✅ $TestName" -ForegroundColor Green
        } catch {
            $testResults.Tests += @{ Name = $TestName; Status = "FAIL"; Result = $_.Exception.Message }
            $testResults.Failed++
            Write-Host "❌ $TestName - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    # Test module integration
    Test-Function "All modules load successfully" {
        # Test that all modules are loaded and functions are available
        $requiredFunctions = @(
            "New-Health", "Add-Health", "Write-HealthSummary",  # Health module
            "Get-CandidateEthernetAdapters", "Test-PingHost",   # Net module
            "Test-PwshVersion7Plus", "Get-IpClass",            # Core module
            "Write-Log", "Write-Ok", "Write-Warn", "Write-Err" # Logging module
        )
        
        foreach ($func in $requiredFunctions) {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                throw "Function $func not available"
            }
        }
        return $true
    }
    
    # Test health system integration
    Test-Function "Health system integration works" {
        $Health = New-Health
        $Health = Add-Health $Health 'Integration test' 'OK' 1
        $Health = Add-Health $Health 'Another test' 'FAIL' 2
        
        if ($Health.Count -eq 2) {
            Write-HealthSummary -Health $Health | Out-Null
            return $true
        } else {
            throw "Expected 2 health items, got $($Health.Count)"
        }
    }
    
    # Test network integration
    Test-Function "Network functions integration works" {
        $adapters = Get-CandidateEthernetAdapters
        $recommended = Get-RecommendedAdapter
        $connectivity = Test-PingHost -TargetName "127.0.0.1" -Count 1
        
        if ($adapters -is [array] -and $connectivity -is [bool]) {
            return $true
        } else {
            throw "Network functions returned unexpected types"
        }
    }
    
    # Test core functions integration
    Test-Function "Core functions integration works" {
        $versionOk = Test-PwshVersion7Plus
        $ipClass = Get-IpClass -IPv4 "8.8.8.8"
        $asciiOk = Test-AsciiOnly "Hello World"
        
        if ($versionOk -is [bool] -and $ipClass -eq "PUBLIC" -and $asciiOk -eq $true) {
            return $true
        } else {
            throw "Core functions returned unexpected results"
        }
    }
    
    # Test logging integration
    Test-Function "Logging functions integration works" {
        Write-Log "Integration test" | Out-Null
        Write-Ok "Success test" | Out-Null
        Write-Warn "Warning test" | Out-Null
        Write-Err "Error test" | Out-Null
        return $true
    }
    
    # Test complete workflow
    Test-Function "Complete diagnostic workflow simulation" {
        $Health = New-Health
        
        # Simulate diagnostic checks
        $Health = Add-Health $Health 'PowerShell version' "OK ($($PSVersionTable.PSVersion))" 1
        $Health = Add-Health $Health 'Network adapters' "OK ($(Get-CandidateEthernetAdapters).Count found)" 2
        $Health = Add-Health $Health 'Local connectivity' (Test-PingHost -TargetName "127.0.0.1" -Count 1 ? 'OK' : 'FAIL') 3
        
        if ($Health.Count -ge 3) {
            Write-HealthSummary -Health $Health | Out-Null
            return $true
        } else {
            throw "Expected at least 3 health checks, got $($Health.Count)"
        }
    }
    
    # Summary
    Write-Host "`n📊 Integration Test Results Summary:" -ForegroundColor Cyan
    Write-Host "✅ Passed: $($testResults.Passed)" -ForegroundColor Green
    Write-Host "❌ Failed: $($testResults.Failed)" -ForegroundColor Red
    Write-Host "📈 Total: $($testResults.Passed + $testResults.Failed)" -ForegroundColor Yellow
    
    if ($testResults.Failed -gt 0) {
        Write-Host "`n❌ Failed Tests:" -ForegroundColor Red
        $testResults.Tests | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
            Write-Host "  - $($_.Name): $($_.Result)" -ForegroundColor Red
        }
        exit 1
    } else {
        Write-Host "`n🎉 All integration tests passed!" -ForegroundColor Green
        exit 0
    }
}
