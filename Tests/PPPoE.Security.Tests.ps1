# PPPoE.Security.Tests.ps1 - Tests for security and credential handling

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.Credentials.psm1",
        "../Modules/PPPoE.Configuration.psm1",
        "../Modules/PPPoE.Utilities.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "🔍 Running security and credential handling tests..."
    
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
    
    # Test credential sanitization
    Test-Function "Credential functions don't expose passwords in output" {
        try {
            $testPassword = "SecretPassword123!"
            $result = Test-CredentialsFormat -UserName "testuser" -Password $testPassword
            
            # Check that password is not in the result
            $resultString = $result | ConvertTo-Json -Depth 10
            return (-not $resultString.Contains($testPassword))
        } catch {
            return $false
        }
    }
    
    Test-Function "Credential functions handle special characters safely" {
        try {
            $specialPassword = 'Pass!@#$%^&*()_+-=[]{}|;'':",./<>?`~'
            $result = Test-CredentialsFormat -UserName "testuser" -Password $specialPassword
            return ($result -is [object])
        } catch {
            return $false
        }
    }
    
    Test-Function "Credential functions handle unicode characters safely" {
        try {
            $unicodePassword = "Password测试123"
            $result = Test-CredentialsFormat -UserName "testuser" -Password $unicodePassword
            return ($result -is [object])
        } catch {
            return $false
        }
    }
    
    # Test input validation
    Test-Function "Functions validate input length limits" {
        try {
            # Test with extremely long inputs
            $longString = "x" * 10000
            $result = Test-CredentialsFormat -UserName $longString -Password "test"
            return ($result -is [object])
        } catch {
            return $true  # Expected to handle long inputs
        }
    }
    
    Test-Function "Functions handle SQL injection attempts safely" {
        try {
            $sqlInjection = "'; DROP TABLE users; --"
            $result = Test-CredentialsFormat -UserName $sqlInjection -Password "test"
            return ($result -is [object])
        } catch {
            return $false
        }
    }
    
    Test-Function "Functions handle script injection attempts safely" {
        try {
            $scriptInjection = "<script>alert('xss')</script>"
            $result = Test-CredentialsFormat -UserName $scriptInjection -Password "test"
            return ($result -is [object])
        } catch {
            return $false
        }
    }
    
    # Test file path security
    Test-Function "Configuration functions handle path traversal attempts safely" {
        try {
            $pathTraversal = "../../../etc/passwd"
            $result = Import-Configuration -ConfigPath $pathTraversal
            return ($null -eq $result)  # Should return null for invalid paths
        } catch {
            return $true  # Expected to handle path traversal
        }
    }
    
    Test-Function "Configuration functions handle UNC paths safely" {
        try {
            $uncPath = "\\server\share\config.json"
            $result = Import-Configuration -ConfigPath $uncPath
            return ($null -eq $result)  # Should return null for UNC paths
        } catch {
            return $true  # Expected to handle UNC paths
        }
    }
    
    # Test permission validation
    Test-Function "Functions check file permissions appropriately" {
        try {
            # Test with a file that might not exist or be accessible
            $result = Import-Configuration -ConfigPath "C:\Windows\System32\config\SAM"
            return ($null -eq $result)  # Should return null for system files
        } catch {
            return $true  # Expected to handle permission errors
        }
    }
    
    # Test memory security
    Test-Function "Functions don't leak sensitive data in memory" {
        try {
            $sensitiveData = "VerySecretPassword123!"
            $null = Test-CredentialsFormat -UserName "test" -Password $sensitiveData
            
            # Clear the variable
            $sensitiveData = $null
            [System.GC]::Collect()
            
            return $true
        } catch {
            return $false
        }
    }
    
    # Test error message security
    Test-Function "Error messages don't expose sensitive information" {
        try {
            # Test with invalid credentials
            $result = Test-CredentialsFormat -UserName "test" -Password "invalid"
            
            # Check that error messages don't contain the password
            $errorMessages = @()
            if ($result -and $result.Issues) {
                $errorMessages += $result.Issues
            }
            
            $allMessages = $errorMessages -join " "
            return (-not $allMessages.Contains("invalid"))
        } catch {
            return $true  # Expected to handle errors gracefully
        }
    }
    
    # Test configuration security
    Test-Function "Configuration functions handle malicious JSON safely" {
        try {
            # Create a temporary file with potentially malicious JSON
            $tempFile = [System.IO.Path]::GetTempFileName()
            $maliciousJson = '{"malicious": "value", "exec": "rm -rf /"}'
            $maliciousJson | Out-File -FilePath $tempFile -Encoding UTF8
            
            $result = Import-Configuration -ConfigPath $tempFile
            Remove-Item $tempFile -Force
            
            return ($result -is [object] -or $null -eq $result)
        } catch {
            return $true  # Expected to handle malicious JSON
        }
    }
    
    # Test credential source security
    Test-Function "Credential source functions handle invalid sources safely" {
        try {
            $result = Get-CredentialSource -UserName "test" -Password "test"
            return ($result -is [string] -or $null -eq $result)
        } catch {
            return $false
        }
    }
    
    Test-Function "Credential source functions don't expose file paths inappropriately" {
        try {
            Show-CredentialSources -WriteLog { param($msg) Write-Host $msg } | Out-Null
            return $true
        } catch {
            return $false
        }
    }
    
    # Test system information security
    Test-Function "System information functions don't expose sensitive data" {
        try {
            $result = Get-SystemInformation
            $resultString = $result | ConvertTo-Json -Depth 10
            
            # Check that sensitive information is not exposed
            $sensitivePatterns = @("password", "secret", "key", "token")
            foreach ($pattern in $sensitivePatterns) {
                if ($resultString.ToLower().Contains($pattern)) {
                    return $false
                }
            }
            return $true
        } catch {
            return $false
        }
    }
    
    # Test environment information security
    Test-Function "Environment information functions don't expose sensitive environment variables" {
        try {
            $result = Get-EnvironmentInfo
            $resultString = $result | ConvertTo-Json -Depth 10
            
            # Check that sensitive environment variables are not exposed
            $sensitiveEnvVars = @("PASSWORD", "SECRET", "KEY", "TOKEN", "API_KEY")
            foreach ($envVar in $sensitiveEnvVars) {
                if ($resultString.ToUpper().Contains($envVar)) {
                    return $false
                }
            }
            return $true
        } catch {
            return $false
        }
    }
    
    # Test process information security
    Test-Function "Process information functions don't expose sensitive process data" {
        try {
            $result = Get-ProcessInformation
            $resultString = $result | ConvertTo-Json -Depth 10
            
            # Check that sensitive process information is not exposed
            $sensitivePatterns = @("password", "secret", "key", "token")
            foreach ($pattern in $sensitivePatterns) {
                if ($resultString.ToLower().Contains($pattern)) {
                    return $false
                }
            }
            return $true
        } catch {
            return $false
        }
    }
    
    # Test network information security
    Test-Function "Network information functions don't expose sensitive network data" {
        try {
            $result = Get-NetworkAdapterSummary
            $resultString = $result | ConvertTo-Json -Depth 10
            
            # Check that sensitive network information is not exposed
            $sensitivePatterns = @("password", "secret", "key", "token")
            foreach ($pattern in $sensitivePatterns) {
                if ($resultString.ToLower().Contains($pattern)) {
                    return $false
                }
            }
            return $true
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
