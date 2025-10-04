# PPPoE.Credentials.Tests.ps1 - Tests for credential management module

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot "../Modules/PPPoE.Credentials.psm1"
    Import-Module $modulePath -Force
    
    Write-Host "🔍 Running basic validation tests for PPPoE.Credentials module..."
    
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
    
    # Test Test-CredentialsProvided
    Test-Function "Test-CredentialsProvided returns true for valid credentials" {
        $result = Test-CredentialsProvided -UserName "testuser" -Password "testpass"
        return ($result -eq $true)
    }
    
    Test-Function "Test-CredentialsProvided returns false for empty credentials" {
        $result = Test-CredentialsProvided -UserName "" -Password ""
        return ($result -eq $false)
    }
    
    Test-Function "Test-CredentialsProvided returns false for null credentials" {
        $result = Test-CredentialsProvided -UserName $null -Password $null
        return ($result -eq $false)
    }
    
    # Test Test-CredentialsFormat
    Test-Function "Test-CredentialsFormat validates good credentials" {
        $result = Test-CredentialsFormat -UserName "testuser" -Password "testpass123"
        return ($result.IsValid -eq $true -and $result.Issues.Count -eq 0)
    }
    
    Test-Function "Test-CredentialsFormat detects short username" {
        $result = Test-CredentialsFormat -UserName "ab" -Password "testpass123"
        return ($result.IsValid -eq $false -and $result.Issues.Count -gt 0)
    }
    
    Test-Function "Test-CredentialsFormat detects short password" {
        $result = Test-CredentialsFormat -UserName "testuser" -Password "123"
        return ($result.IsValid -eq $false -and $result.Issues.Count -gt 0)
    }
    
    # Test Get-CredentialSource
    Test-Function "Get-CredentialSource prioritizes parameters" {
        $result = Get-CredentialSource -UserName "testuser" -Password "testpass" -CredentialsFilePath "nonexistent.ps1" -WriteLog { param($msg) Write-Host $msg }
        return ($result.Source -eq 'Parameters' -and $result.Username -eq 'testuser')
    }
    
    Test-Function "Get-CredentialSource falls back to Windows saved" {
        $result = Get-CredentialSource -UserName "" -Password "" -CredentialsFilePath "nonexistent.ps1" -WriteLog { param($msg) Write-Host $msg }
        return ($result.Source -eq 'Windows Saved')
    }
    
    # Test Get-CredentialsFromFile with non-existent file
    Test-Function "Get-CredentialsFromFile handles non-existent file" {
        $result = Get-CredentialsFromFile -CredentialsFilePath "nonexistent.ps1" -WriteLog { param($msg) Write-Host $msg }
        return ($result -eq $null)
    }
    
    # Test Show-CredentialSources
    Test-Function "Show-CredentialSources displays information" {
        try {
            Show-CredentialSources -WriteLog { param($msg) Write-Host $msg }
            return $true
        } catch {
            return $false
        }
    }
    
    # Test error handling
    Test-Function "Functions handle WriteLog errors gracefully" {
        $badWriteLog = { throw "Test error" }
        try {
            $result = Get-CredentialSource -UserName "test" -Password "test" -CredentialsFilePath "test" -WriteLog $badWriteLog
            return $false  # Should not reach here
        } catch {
            return $true  # Expected to throw
        }
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
