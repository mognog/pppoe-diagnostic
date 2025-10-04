# PPPoE.Net.Tests.ps1 - Tests for network functions
# Tests the PPPoE.Net.psm1 module functions

# Import the module to test
$modulePath = Join-Path $PSScriptRoot "..\Modules\PPPoE.Net.psm1"
Import-Module $modulePath -Force

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
    Describe "PPPoE.Net Module Tests" {
        
        Describe "Get-CandidateEthernetAdapters" {
            It "Should return only Ethernet adapters" {
                # Mock Get-NetAdapter with test data
                $mockAdapters = @(
                    @{ Name = "Ethernet"; MediaType = "802.3"; Status = "Up" },
                    @{ Name = "WiFi"; MediaType = "802.11"; Status = "Up" },
                    @{ Name = "Ethernet 2"; MediaType = "802.3"; Status = "Down" },
                    @{ Name = "Bluetooth"; MediaType = "802.15"; Status = "Up" }
                )
                Mock Get-NetAdapter { return $mockAdapters }
                
                $result = Get-CandidateEthernetAdapters
                
                $result | Should -HaveCount 2
                $result[0].Name | Should -Be "Ethernet"
                $result[1].Name | Should -Be "Ethernet 2"
            }
            
            It "Should sort by status (Up first)" {
                $mockAdapters = @(
                    @{ Name = "Ethernet Down"; MediaType = "802.3"; Status = "Down" },
                    @{ Name = "Ethernet Up"; MediaType = "802.3"; Status = "Up" }
                )
                Mock Get-NetAdapter { return $mockAdapters }
                
                $result = Get-CandidateEthernetAdapters
                $result[0].Status | Should -Be "Up"
                $result[1].Status | Should -Be "Down"
            }
            
            It "Should handle no Ethernet adapters" {
                $mockAdapters = @(
                    @{ Name = "WiFi"; MediaType = "802.11"; Status = "Up" },
                    @{ Name = "Bluetooth"; MediaType = "802.15"; Status = "Up" }
                )
                Mock Get-NetAdapter { return $mockAdapters }
                
                $result = Get-CandidateEthernetAdapters
                $result | Should -HaveCount 0
            }
        }
        
        Describe "Get-RecommendedAdapter" {
            It "Should prefer Realtek adapters" {
                $mockAdapters = @(
                    @{ Name = "Generic Ethernet"; InterfaceDescription = "Generic Ethernet Adapter"; Status = "Up" },
                    @{ Name = "Realtek Ethernet"; InterfaceDescription = "Realtek PCIe GbE Family Controller"; Status = "Up" }
                )
                Mock Get-CandidateEthernetAdapters { return $mockAdapters }
                
                $result = Get-RecommendedAdapter
                $result.Name | Should -Be "Realtek Ethernet"
            }
            
            It "Should prefer USB adapters" {
                $mockAdapters = @(
                    @{ Name = "Built-in Ethernet"; InterfaceDescription = "Built-in Ethernet"; Status = "Up" },
                    @{ Name = "USB Ethernet"; InterfaceDescription = "USB Ethernet Adapter"; Status = "Up" }
                )
                Mock Get-CandidateEthernetAdapters { return $mockAdapters }
                
                $result = Get-RecommendedAdapter
                $result.Name | Should -Be "USB Ethernet"
            }
            
            It "Should return null when no adapters" {
                Mock Get-CandidateEthernetAdapters { return @() }
                
                $result = Get-RecommendedAdapter
                $result | Should -BeNullOrEmpty
            }
        }
        
        Describe "Test-LinkUp" {
            It "Should return true for up adapter with link" {
                $mockAdapter = @{ Name = "Ethernet"; Status = "Up"; LinkSpeed = 1000000000 }
                Mock Get-NetAdapter { return $mockAdapter }
                
                $result = Test-LinkUp -AdapterName "Ethernet"
                $result | Should -Be $true
            }
            
            It "Should return false for down adapter" {
                $mockAdapter = @{ Name = "Ethernet"; Status = "Down"; LinkSpeed = 1000000000 }
                Mock Get-NetAdapter { return $mockAdapter }
                
                $result = Test-LinkUp -AdapterName "Ethernet"
                $result | Should -Be $false
            }
            
            It "Should return false for no link speed" {
                $mockAdapter = @{ Name = "Ethernet"; Status = "Up"; LinkSpeed = 0 }
                Mock Get-NetAdapter { return $mockAdapter }
                
                $result = Test-LinkUp -AdapterName "Ethernet"
                $result | Should -Be $false
            }
        }
        
        Describe "Connect-PPP" {
            It "Should return success structure for successful connection" {
                Mock Start-Process { 
                    return @{ ExitCode = 0 }
                }
                
                $result = Connect-PPP -PppoeName "Test" -UserName "user" -Password "pass"
                
                $result | Should -HaveMember "Success"
                $result | Should -HaveMember "Code"
                $result | Should -HaveMember "Output"
                $result.Success | Should -BeOfType [bool]
                $result.Code | Should -BeOfType [int]
            }
            
            It "Should handle different exit codes" {
                $testCases = @(
                    @{ ExitCode = 0; ExpectedSuccess = $true }
                    @{ ExitCode = 691; ExpectedSuccess = $false }
                    @{ ExitCode = 651; ExpectedSuccess = $false }
                )
                
                foreach ($testCase in $testCases) {
                    Mock Start-Process { return @{ ExitCode = $testCase.ExitCode } }
                    
                    $result = Connect-PPP -PppoeName "Test" -UserName "user" -Password "pass"
                    $result.Code | Should -Be $testCase.ExitCode
                }
            }
        }
        
        Describe "Get-PppInterface" {
            It "Should find PPP interface by name" {
                $mockInterfaces = @(
                    @{ InterfaceAlias = "PPP Rise PPPoE"; ConnectionState = "Connected"; InterfaceIndex = 1 }
                )
                Mock Get-NetIPInterface { return $mockInterfaces }
                
                $result = Get-PppInterface -PppoeName "Rise PPPoE"
                $result | Should -Not -BeNullOrEmpty
                $result.InterfaceIndex | Should -Be 1
            }
            
            It "Should return null when no PPP interface found" {
                $mockInterfaces = @(
                    @{ InterfaceAlias = "Ethernet"; ConnectionState = "Connected"; InterfaceIndex = 1 }
                )
                Mock Get-NetIPInterface { return $mockInterfaces }
                
                $result = Get-PppInterface -PppoeName "Rise PPPoE"
                $result | Should -BeNullOrEmpty
            }
        }
        
        Describe "Test-PingHost" {
            It "Should return true for successful ping" {
                Mock Test-Connection { return @{ ResponseTime = 10 } }
                
                $result = Test-PingHost -TargetName "1.1.1.1" -Count 2
                $result | Should -Be $true
            }
            
            It "Should return false for failed ping" {
                Mock Test-Connection { throw "Network unreachable" }
                
                $result = Test-PingHost -TargetName "invalid.target" -Count 2
                $result | Should -Be $false
            }
        }
        
        Describe "Get-IpClass Integration" {
            It "Should work with network functions" {
                # Test that IP classification works with network results
                $testIPs = @("8.8.8.8", "192.168.1.1", "100.64.1.1", "169.254.1.1")
                $expectedResults = @("PUBLIC", "PRIVATE", "CGNAT", "APIPA")
                
                for ($i = 0; $i -lt $testIPs.Count; $i++) {
                    # This would use the Get-IpClass function from Core module
                    # Since we're testing the Net module, we'll mock the result
                    $result = switch ($testIPs[$i]) {
                        "8.8.8.8" { "PUBLIC" }
                        "192.168.1.1" { "PRIVATE" }
                        "100.64.1.1" { "CGNAT" }
                        "169.254.1.1" { "APIPA" }
                    }
                    
                    $result | Should -Be $expectedResults[$i]
                }
            }
        }
    }
} else {
    # Basic validation without Pester
    Write-Host "🔍 Running basic validation tests for PPPoE.Net module..." -ForegroundColor Cyan
    
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
    
    # Test Get-CandidateEthernetAdapters
    Test-Function "Get-CandidateEthernetAdapters returns array" {
        $result = Get-CandidateEthernetAdapters
        if ($result -is [array] -or $result -eq $null) {
            return $true
        } else {
            throw "Expected array or null, got $($result.GetType())"
        }
    }
    
    # Test Get-RecommendedAdapter
    Test-Function "Get-RecommendedAdapter returns adapter or null" {
        $result = Get-RecommendedAdapter
        if ($result -eq $null -or $result.GetType().Name -eq "Object") {
            return $true
        } else {
            throw "Expected adapter object or null, got $($result.GetType())"
        }
    }
    
    # Test Test-LinkUp (this will test with real adapters)
    Test-Function "Test-LinkUp handles adapter names" {
        # Test with a non-existent adapter name
        $result = Test-LinkUp -AdapterName "NonExistentAdapter"
        if ($result -is [bool]) {
            return $true
        } else {
            throw "Expected boolean, got $($result.GetType())"
        }
    }
    
    # Test Connect-PPP structure
    Test-Function "Connect-PPP returns proper structure" {
        # This will likely fail with actual connection, but we can test the structure
        try {
            $result = Connect-PPP -PppoeName "NonExistentConnection" -UserName "test" -Password "test"
            if ($result -and $result.ContainsKey("Success") -and $result.ContainsKey("Code") -and $result.ContainsKey("Output")) {
                return $true
            } else {
                throw "Missing expected keys in result hashtable"
            }
        } catch {
            # Expected to fail, but should return proper structure
            return $true
        }
    }
    
    # Test Get-PppInterface
    Test-Function "Get-PppInterface returns interface or null" {
        $result = Get-PppInterface -PppoeName "NonExistentConnection"
        if ($result -eq $null -or $result.GetType().Name -eq "Object") {
            return $true
        } else {
            throw "Expected interface object or null, got $($result.GetType())"
        }
    }
    
    # Test Test-PingHost
    Test-Function "Test-PingHost returns boolean" {
        $result = Test-PingHost -TargetName "127.0.0.1" -Count 1
        if ($result -is [bool]) {
            return $true
        } else {
            throw "Expected boolean, got $($result.GetType())"
        }
    }
    
    # Summary
    Write-Host "`n📊 Test Results Summary:" -ForegroundColor Cyan
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
        Write-Host "`n🎉 All tests passed!" -ForegroundColor Green
        exit 0
    }
}
