# PPPoE.Configuration.Tests.ps1 - Tests for configuration management module

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot "../Modules/PPPoE.Configuration.psm1"
    Import-Module $modulePath -Force
    
    Write-Host "Running basic validation tests for PPPoE.Configuration module..."
    
    # Test function wrapper
    function Test-Function {
        param([string]$Name, [scriptblock]$TestScript)
        try {
            $result = & $TestScript
            if ($result) {
                Write-Host "PASS: $Name" -ForegroundColor Green
                return $true
            } else {
                Write-Host "FAIL: $Name" -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "FAIL: $Name - Error: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    $passed = 0
    $failed = 0
    
    # Test Get-ProjectConfiguration
    Test-Function "Get-ProjectConfiguration returns default config" {
        $config = Get-ProjectConfiguration
        return ($config -is [hashtable] -and $config.ContainsKey('Logging') -and $config.ContainsKey('Network'))
    }
    
    Test-Function "Get-ProjectConfiguration has required sections" {
        $config = Get-ProjectConfiguration
        $requiredSections = @('Logging', 'Network', 'HealthChecks', 'Credentials', 'WiFi')
        $hasAllSections = $true
        foreach ($section in $requiredSections) {
            if (-not $config.ContainsKey($section)) {
                $hasAllSections = $false
                break
            }
        }
        return $hasAllSections
    }
    
    # Test Set-LoggingConfiguration
    Test-Function "Set-LoggingConfiguration modifies config" {
        $config = Get-ProjectConfiguration
        $originalLogDir = $config.Logging.LogDirectory
        $modifiedConfig = Set-LoggingConfiguration -Config $config -LogDirectory "test_logs"
        return ($modifiedConfig.Logging.LogDirectory -eq "test_logs" -and $originalLogDir -ne "test_logs")
    }
    
    # Test Get-DefaultParameters
    Test-Function "Get-DefaultParameters returns parameter hashtable" {
        $config = Get-ProjectConfiguration
        $params = Get-DefaultParameters -Config $config
        return ($params -is [hashtable] -and $params.ContainsKey('PppoeName'))
    }
    
    # Test Test-Configuration
    Test-Function "Test-Configuration validates default config" {
        $config = Get-ProjectConfiguration
        $validation = Test-Configuration -Config $config
        return ($validation -is [hashtable] -and $validation.ContainsKey('IsValid') -and $validation.IsValid)
    }
    
    Test-Function "Test-Configuration detects invalid config" {
        $invalidConfig = @{
            Logging = @{
                LogDirectory = $null
                MaxLogFiles = 0
            }
            Network = @{
                DefaultPPPoEName = $null
                PingTimeout = 50
                PingCount = 0
            }
        }
        $validation = Test-Configuration -Config $invalidConfig
        return ($validation -is [hashtable] -and -not $validation.IsValid -and $validation.Issues.Count -gt 0)
    }
    
    # Test Merge-Configuration
    Test-Function "Merge-Configuration merges configs correctly" {
        $default = @{
            Logging = @{
                LogDirectory = "logs"
                LogLevel = "INFO"
            }
            Network = @{
                DefaultPPPoEName = "PPPoE"
            }
        }
        $override = @{
            Logging = @{
                LogLevel = "DEBUG"
            }
            NewSection = @{
                NewValue = "test"
            }
        }
        $merged = Merge-Configuration -Default $default -Override $override
        return ($merged.Logging.LogDirectory -eq "logs" -and 
                $merged.Logging.LogLevel -eq "DEBUG" -and 
                $merged.Network.DefaultPPPoEName -eq "PPPoE" -and
                $merged.NewSection.NewValue -eq "test")
    }
    
    # Test Export-Configuration and Import-Configuration
    Test-Function "Export-Configuration creates valid JSON file" {
        $config = Get-ProjectConfiguration
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            $result = Export-Configuration -Config $config -OutputPath $tempFile
            $fileExists = Test-Path $tempFile
            $hasContent = (Get-Content $tempFile -Raw).Length -gt 0
            return ($result -and $fileExists -and $hasContent)
        } finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        }
    }
    
    Test-Function "Import-Configuration loads valid config file" {
        $config = Get-ProjectConfiguration
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            Export-Configuration -Config $config -OutputPath $tempFile | Out-Null
            $importedConfig = Import-Configuration -ConfigPath $tempFile
            return ($importedConfig -is [hashtable] -and $importedConfig.ContainsKey('Logging'))
        } finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        }
    }
    
    # Count results
    $total = $passed + $failed
    
    Write-Host ""
    Write-Host "Test Results Summary:" -ForegroundColor Cyan
    Write-Host "Passed: $passed" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor Red
    Write-Host "Total: $total" -ForegroundColor Cyan
    
    if ($failed -eq 0) {
        Write-Host ""
        Write-Host "All tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "Some tests failed!" -ForegroundColor Red
        exit 1
    }
    
} finally {
    # Restore original execution policy
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
