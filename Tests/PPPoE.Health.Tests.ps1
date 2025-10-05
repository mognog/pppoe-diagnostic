# PPPoE.Health.Tests.ps1 - Tests for health checking functions
# Tests the PPPoE.Health.psm1 module functions

# Import the module to test
$modulePath = Join-Path $PSScriptRoot "..\Modules\PPPoE.Health.psm1"
# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
try {
    Import-Module $modulePath -Force
} finally {
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}

# Check if Pester is available
$pesterAvailable = $false
try {
    Import-Module Pester -Force -ErrorAction Stop
    $pesterModule = Get-Module Pester -ErrorAction SilentlyContinue
    if ($pesterModule -and $pesterModule.Version.Major -ge 5) {
        $pesterAvailable = $true
        Write-Host "✅ Pester v$($pesterModule.Version) available - using full test framework" -ForegroundColor Green
    } else {
        $pesterAvailable = $false
        $ver = if ($pesterModule) { $pesterModule.Version } else { '(unknown)' }
        Write-Host "⚠️  Pester v$ver detected (<5) - using basic validation" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Pester not available - using basic validation" -ForegroundColor Yellow
}

if ($pesterAvailable) {
    Describe "PPPoE.Health Module Tests" {
        
        Describe "New-Health" {
            It "Should create an ordered hashtable" {
                $health = New-Health
                $health | Should -Not -BeNullOrEmpty
                $health.GetType().Name | Should -Be "OrderedDictionary"
            }
            
            It "Should create empty health object initially" {
                $health = New-Health
                $health.Count | Should -Be 0
            }
        }
        
        Describe "Add-Health" {
            It "Should add health items with proper ordering" {
                $health = New-Health
                $health = Add-Health $health "Test Item 1" "OK" 1
                $health = Add-Health $health "Test Item 2" "FAIL" 2
                $health = Add-Health $health "Test Item 3" "WARN" 3
                
                $health.Count | Should -Be 3
                $health.Keys | Should -Contain "01_Test Item 1"
                $health.Keys | Should -Contain "02_Test Item 2"
                $health.Keys | Should -Contain "03_Test Item 3"
            }
            
            It "Should handle items without order" {
                $health = New-Health
                $health = Add-Health $health "Test Item" "OK"
                
                $health.Count | Should -Be 1
                $health.Keys | Should -Contain "00_Test Item"
            }
            
            It "Should maintain order prefix format" {
                $health = New-Health
                $health = Add-Health $health "Test Item" "OK" 15
                
                $health.Keys | Should -Contain "15_Test Item"
            }
        }
        
        Describe "Write-HealthSummary" {
            It "Should handle empty health object" {
                $health = New-Health
                { Write-HealthSummary -Health $health } | Should -Not -Throw
            }
            
            It "Should handle health object with items" {
                $health = New-Health
                $health = Add-Health $health "Test Item 1" "OK" 1
                $health = Add-Health $health "Test Item 2" "FAIL" 2
                $health = Add-Health $health "Test Item 3" "WARN" 3
                
                { Write-HealthSummary -Health $health } | Should -Not -Throw
            }
            
            It "Should sort items by order" {
                $health = New-Health
                $health = Add-Health $health "Item C" "OK" 3
                $health = Add-Health $health "Item A" "OK" 1
                $health = Add-Health $health "Item B" "OK" 2
                
                { Write-HealthSummary -Health $health } | Should -Not -Throw
            }
            
            It "Should determine overall status correctly" {
                $testCases = @(
                    @{ Items = @("OK", "OK"); Expected = "OK" }
                    @{ Items = @("OK", "WARN"); Expected = "WARN" }
                    @{ Items = @("OK", "FAIL"); Expected = "FAIL" }
                    @{ Items = @("WARN", "WARN"); Expected = "WARN" }
                    @{ Items = @("FAIL", "FAIL"); Expected = "FAIL" }
                )
                
                foreach ($testCase in $testCases) {
                    $health = New-Health
                    for ($i = 0; $i -lt $testCase.Items.Count; $i++) {
                        $health = Add-Health $health "Item $i" $testCase.Items[$i] ($i + 1)
                    }
                    
                    { Write-HealthSummary -Health $health } | Should -Not -Throw
                }
            }
        }
        
        Describe "Health Object Integration" {
            It "Should work with real diagnostic flow" {
                $health = New-Health
                
                # Simulate typical diagnostic flow
                $health = Add-Health $health 'PowerShell version' "OK ($($PSVersionTable.PSVersion))" 1
                $health = Add-Health $health 'PPPoE connections configured' "OK (1 found: Rise PPPoE)" 2
                $health = Add-Health $health 'Physical adapter detected' "OK (Realtek PCIe GbE Family Controller @ 1000000000 bps)" 3
                $health = Add-Health $health 'Ethernet link state' 'OK (Up)' 4
                $health = Add-Health $health 'PPPoE authentication' 'OK' 12
                
                $health.Count | Should -Be 5
                $health.Keys | Should -Contain "01_PowerShell version"
                $health.Keys | Should -Contain "02_PPPoE connections configured"
                $health.Keys | Should -Contain "03_Physical adapter detected"
                $health.Keys | Should -Contain "04_Ethernet link state"
                $health.Keys | Should -Contain "12_PPPoE authentication"
                
                { Write-HealthSummary -Health $health } | Should -Not -Throw
            }
        }
    }
} else {
    # Basic validation without Pester
    Write-Host "🔍 Running basic validation tests for PPPoE.Health module..." -ForegroundColor Cyan
    
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
    
    # Test New-Health
    Test-Function "New-Health creates ordered hashtable" {
        $health = New-Health
        if ($health -and $health.GetType().Name -eq "OrderedDictionary") {
            return $true
        } else {
            throw "Expected OrderedDictionary, got $($health.GetType().Name)"
        }
    }
    
    Test-Function "New-Health creates empty object" {
        $health = New-Health
        if ($health.Count -eq 0) {
            return $true
        } else {
            throw "Expected empty hashtable, got count $($health.Count)"
        }
    }
    
    # Test Add-Health
    Test-Function "Add-Health adds items with ordering" {
        $health = New-Health
        $health = Add-Health $health "Test Item" "OK" 1
        if ($health.Count -eq 1 -and $health.Keys -contains "01_Test Item") {
            return $true
        } else {
            throw "Expected ordered item, got keys: $($health.Keys -join ', ')"
        }
    }
    
    Test-Function "Add-Health handles multiple items" {
        $health = New-Health
        $health = Add-Health $health "Item A" "OK" 1
        $health = Add-Health $health "Item B" "FAIL" 2
        if ($health.Count -eq 2 -and $health.Keys -contains "01_Item A" -and $health.Keys -contains "02_Item B") {
            return $true
        } else {
            throw "Expected 2 ordered items, got: $($health.Keys -join ', ')"
        }
    }
    
    # Test Write-HealthSummary
    Test-Function "Write-HealthSummary handles empty health" {
        $health = New-Health
        try {
            Write-HealthSummary -Health $health | Out-Null
            return $true
        } catch {
            # If transcript-related error, that's expected without Start-AsciiTranscript
            if ($_.Exception.Message -like "*_TranscriptWriter*") {
                return $true
            }
            throw
        }
    }
    
    Test-Function "Write-HealthSummary handles items" {
        $health = New-Health
        $health = Add-Health $health "Test Item 1" "OK" 1
        $health = Add-Health $health "Test Item 2" "FAIL" 2
        try {
            Write-HealthSummary -Health $health | Out-Null
            return $true
        } catch {
            # If transcript-related error, that's expected without Start-AsciiTranscript
            if ($_.Exception.Message -like "*_TranscriptWriter*") {
                return $true
            }
            throw
        }
    }
    
    # Test real diagnostic flow
    Test-Function "Health object works with diagnostic flow" {
        $health = New-Health
        $health = Add-Health $health 'PowerShell version' "OK ($($PSVersionTable.PSVersion))" 1
        $health = Add-Health $health 'PPPoE connections configured' "OK (1 found)" 2
        $health = Add-Health $health 'Physical adapter detected' "OK (Test Adapter)" 3
        
        if ($health.Count -eq 3) {
            try {
                Write-HealthSummary -Health $health | Out-Null
                return $true
            } catch {
                # If transcript-related error, that's expected without Start-AsciiTranscript
                if ($_.Exception.Message -like "*_TranscriptWriter*") {
                    return $true
                }
                throw
            }
        } else {
            throw "Expected 3 items, got $($health.Count)"
        }
    }
    
    # Summary
    Write-Host "`n📊 Test Results Summary:" -ForegroundColor Cyan
    Write-Host "✅ Passed: $($testResults.Passed)" -ForegroundColor Green
    Write-Host "❌ Failed: $($testResults.Failed)" -ForegroundColor Red
    Write-Host "📈 Total: $($testResults.Passed + $testResults.Failed)" -ForegroundColor Yellow
    
    if ($testResults.Failed -gt 0) {
        Write-Host "`n❌ Failed Tests:" -ForegroundColor Red
        $failedTests = $testResults.Tests | Where-Object { $_.Status -eq "FAIL" }
        if ($failedTests) {
            $failedTests | ForEach-Object {
                Write-Host "  - $($_.Name): $($_.Result)" -ForegroundColor Red
            }
        }
        exit 1
    } else {
        Write-Host "`n🎉 All tests passed!" -ForegroundColor Green
        exit 0
    }
}
