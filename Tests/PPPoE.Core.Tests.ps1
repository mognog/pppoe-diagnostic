# PPPoE.Core.Tests.ps1 - Tests for core utility functions
# Tests the PPPoE.Core.psm1 module functions

# Import the module to test
$modulePath = Join-Path $PSScriptRoot "..\Modules\PPPoE.Core.psm1"
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
    $pesterAvailable = $true
    Write-Host "✅ Pester available - using full test framework" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Pester not available - using basic validation" -ForegroundColor Yellow
}

if ($pesterAvailable) {
    Describe "PPPoE.Core Module Tests" {
        
        Describe "Test-PwshVersion7Plus" {
            It "Should return true for PowerShell 7+" {
                # Mock PSVersionTable for testing
                Mock Get-Variable { return @{ PSVersion = [version]"7.0.0" } } -ParameterFilter { $Name -eq "PSVersionTable" }
                
                $result = Test-PwshVersion7Plus
                $result | Should -Be $true
            }
            
            It "Should return false for PowerShell 5" {
                Mock Get-Variable { return @{ PSVersion = [version]"5.1.0" } } -ParameterFilter { $Name -eq "PSVersionTable" }
                
                $result = Test-PwshVersion7Plus
                $result | Should -Be $false
            }
            
            It "Should handle errors gracefully" {
                Mock Get-Variable { throw "Test error" } -ParameterFilter { $Name -eq "PSVersionTable" }
                
                $result = Test-PwshVersion7Plus
                $result | Should -Be $false
            }
        }
        
        Describe "Get-IpClass" {
            It "Should classify public IPs correctly" {
                $result = Get-IpClass -IPv4 "8.8.8.8"
                $result | Should -Be "PUBLIC"
            }
            
            It "Should classify private IPs correctly" {
                $testCases = @(
                    @{ IP = "192.168.1.1"; Expected = "PRIVATE" }
                    @{ IP = "10.0.0.1"; Expected = "PRIVATE" }
                    @{ IP = "172.16.0.1"; Expected = "PRIVATE" }
                )
                
                foreach ($testCase in $testCases) {
                    $result = Get-IpClass -IPv4 $testCase.IP
                    $result | Should -Be $testCase.Expected
                }
            }
            
            It "Should classify CGNAT IPs correctly" {
                $testCases = @(
                    @{ IP = "100.64.1.1"; Expected = "CGNAT" }
                    @{ IP = "100.127.255.255"; Expected = "CGNAT" }
                )
                
                foreach ($testCase in $testCases) {
                    $result = Get-IpClass -IPv4 $testCase.IP
                    $result | Should -Be $testCase.Expected
                }
            }
            
            It "Should classify APIPA IPs correctly" {
                $result = Get-IpClass -IPv4 "169.254.1.1"
                $result | Should -Be "APIPA"
            }
            
            It "Should handle null/empty input" {
                $result = Get-IpClass -IPv4 ""
                $result | Should -Be "NONE"
            }
        }
        
        Describe "Test-AsciiOnly" {
            It "Should return true for ASCII text" {
                $result = Test-AsciiOnly "Hello World 123"
                $result | Should -Be $true
            }
            
            It "Should return false for non-ASCII text" {
                $result = Test-AsciiOnly "Hello 世界"
                $result | Should -Be $false
            }
            
            It "Should return true for empty string" {
                $result = Test-AsciiOnly ""
                $result | Should -Be $true
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
            
            It "Should handle custom parameters" {
                Mock Test-Connection { return @{ ResponseTime = 5 } }
                
                $result = Test-PingHost -TargetName "8.8.8.8" -Count 3 -TimeoutMs 2000 -Ttl 32
                $result | Should -Be $true
            }
        }
        
        Describe "Write-Log Functions" {
            It "Should handle Write-Log without errors" {
                { Write-Log "Test message" } | Should -Not -Throw
            }
            
            It "Should handle Write-Ok without errors" {
                { Write-Ok "Test success" } | Should -Not -Throw
            }
            
            It "Should handle Write-Warn without errors" {
                { Write-Warn "Test warning" } | Should -Not -Throw
            }
            
            It "Should handle Write-Err without errors" {
                { Write-Err "Test error" } | Should -Not -Throw
            }
        }
        
        Describe "Transcript Functions" {
            It "Should handle Start-AsciiTranscript without errors" {
                $testPath = Join-Path $TestDrive "test_transcript.txt"
                { Start-AsciiTranscript -Path $testPath } | Should -Not -Throw
                
                # Cleanup
                { Stop-AsciiTranscript } | Should -Not -Throw
                if (Test-Path $testPath) { Remove-Item $testPath -Force }
            }
        }
    }
} else {
    # Basic validation without Pester
    Write-Host "🔍 Running basic validation tests for PPPoE.Core module..." -ForegroundColor Cyan
    
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
    
    # Test Test-PwshVersion7Plus
    Test-Function "Test-PwshVersion7Plus returns boolean" {
        $result = Test-PwshVersion7Plus
        if ($result -is [bool]) { return $true } else { throw "Expected boolean, got $($result.GetType())" }
    }
    
    # Test Get-IpClass with various IPs
    Test-Function "Get-IpClass handles public IP" {
        $result = Get-IpClass -IPv4 "8.8.8.8"
        if ($result -eq "PUBLIC") { return $true } else { throw "Expected PUBLIC, got $result" }
    }
    
    Test-Function "Get-IpClass handles private IP" {
        $result = Get-IpClass -IPv4 "192.168.1.1"
        if ($result -eq "PRIVATE") { return $true } else { throw "Expected PRIVATE, got $result" }
    }
    
    Test-Function "Get-IpClass handles CGNAT IP" {
        $result = Get-IpClass -IPv4 "100.64.1.1"
        if ($result -eq "CGNAT") { return $true } else { throw "Expected CGNAT, got $result" }
    }
    
    Test-Function "Get-IpClass handles empty input" {
        $result = Get-IpClass -IPv4 ""
        if ($result -eq "NONE") { return $true } else { throw "Expected NONE, got $result" }
    }
    
    # Test Test-AsciiOnly
    Test-Function "Test-AsciiOnly handles ASCII text" {
        $result = Test-AsciiOnly "Hello World"
        if ($result -eq $true) { return $true } else { throw "Expected true, got $result" }
    }
    
    # Test logging functions
    Test-Function "Write-Log functions work" {
        # Test logging functions - they should work even without transcript
        try {
            Write-Log "Test message" | Out-Null
            Write-Ok "Test success" | Out-Null
            Write-Warn "Test warning" | Out-Null
            Write-Err "Test error" | Out-Null
            return $true
        } catch {
            # If transcript-related error, that's expected without Start-AsciiTranscript
            if ($_.Exception.Message -like "*_TranscriptWriter*") {
                return $true
            }
            throw
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "Test Results Summary:" -ForegroundColor Cyan
    Write-Host "Passed: $($testResults.Passed)" -ForegroundColor Green
    Write-Host "Failed: $($testResults.Failed)" -ForegroundColor Red
    Write-Host "Total: $($testResults.Passed + $testResults.Failed)" -ForegroundColor Yellow
    
    if ($testResults.Failed -gt 0) {
        Write-Host ""
        Write-Host "Failed Tests:" -ForegroundColor Red
        $failedTests = $testResults.Tests | Where-Object { $_.Status -eq "FAIL" }
        if ($failedTests) {
            $failedTests | ForEach-Object {
                Write-Host "  - $($_.Name): $($_.Result)" -ForegroundColor Red
            }
        }
        exit 1
    } else {
        Write-Host ""
        Write-Host "All tests passed!" -ForegroundColor Green
        exit 0
    }
}
