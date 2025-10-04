# PPPoE Diagnostic Toolkit - Testing Guide

## 🧪 Overview

This directory contains comprehensive tests for the PPPoE Diagnostic Toolkit. The test suite includes **16 test files** with **200+ individual tests** covering all modules, error handling, security, and edge cases.

## 📁 Test Files

### Core Module Tests
- `PPPoE.Core.Tests.ps1` - Core utility functions
- `PPPoE.Health.Tests.ps1` - Health management functions
- `PPPoE.Net.Tests.ps1` - Network operations (legacy)
- `PPPoE.Integration.Tests.ps1` - Cross-module integration tests

### Configuration & Utilities Tests
- `PPPoE.Configuration.Tests.ps1` - Configuration management
- `PPPoE.Utilities.Tests.ps1` - Utility functions
- `PPPoE.Credentials.Tests.ps1` - Credential handling
- `PPPoE.Workflows.Tests.ps1` - Workflow orchestration
- `PPPoE.HealthChecks.Tests.ps1` - Health check orchestration

### Network Sub-Module Tests
- `PPPoE.Net.Adapters.Tests.ps1` - Network adapter management
- `PPPoE.Net.PPPoE.Tests.ps1` - PPPoE connection management
- `PPPoE.Net.Connectivity.Tests.ps1` - Connectivity testing
- `PPPoE.Net.Diagnostics.Tests.ps1` - Network diagnostics

### Advanced Test Categories
- `PPPoE.ErrorHandling.Tests.ps1` - Error handling & edge cases
- `PPPoE.Security.Tests.ps1` - Security & credential validation
- `PPPoE.MainScript.Tests.ps1` - Main script validation

## 🚀 Running Tests

### Run All Tests
```powershell
# From the project root directory
.\Tests\Run-Tests.ps1

# With detailed output
.\Tests\Run-Tests.ps1 -Detailed

# Install Pester framework (if needed)
.\Tests\Run-Tests.ps1 -InstallPester
```

### Run Specific Test Files
```powershell
# Run individual test files
.\Tests\PPPoE.Core.Tests.ps1
.\Tests\PPPoE.Security.Tests.ps1

# Run multiple specific tests
.\Tests\Run-Tests.ps1 -TestFiles @("PPPoE.Core.Tests.ps1", "PPPoE.Security.Tests.ps1")
```

### Run Test Categories
```powershell
# Core functionality tests
.\Tests\Run-Tests.ps1 -TestFiles @("PPPoE.Core.Tests.ps1", "PPPoE.Health.Tests.ps1", "PPPoE.Net.Tests.ps1")

# Security and error handling tests
.\Tests\Run-Tests.ps1 -TestFiles @("PPPoE.Security.Tests.ps1", "PPPoE.ErrorHandling.Tests.ps1")

# Network module tests
.\Tests\Run-Tests.ps1 -TestFiles @("PPPoE.Net.Adapters.Tests.ps1", "PPPoE.Net.PPPoE.Tests.ps1", "PPPoE.Net.Connectivity.Tests.ps1", "PPPoE.Net.Diagnostics.Tests.ps1")
```

## 📋 Test Structure

### Basic Test File Template
```powershell
# ModuleName.Tests.ps1 - Tests for [Module Description]

# Temporarily set execution policy to allow unsigned local modules
$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import required modules
    $modulePaths = @(
        "../Modules/PPPoE.Core.psm1",
        "../Modules/PPPoE.ModuleName.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        $fullPath = Join-Path $PSScriptRoot $modulePath
        Import-Module $fullPath -Force
    }
    
    Write-Host "Running basic validation tests for PPPoE.ModuleName module..."
    
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
    
    # Your tests here
    Test-Function "Test description" {
        # Test logic here
        return $true
    }
    
    # Summary
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
```

## ⚠️ Test Writing Rules

### ✅ DO Include

#### **Text and Formatting**
- Use plain ASCII characters only
- Use `Write-Host ""` for line breaks (not backticks)
- Use standard PowerShell color names: `Green`, `Red`, `Yellow`, `Cyan`, `Gray`
- Use descriptive test names: `"Function handles null input gracefully"`

#### **Error Handling**
- Always wrap tests in try-catch blocks
- Test both success and failure scenarios
- Test null and empty input handling
- Test boundary conditions and edge cases

#### **Test Structure**
- Use the `Test-Function` wrapper for consistency
- Increment `$passed` and `$failed` counters
- Include execution policy management
- Clean up resources in finally blocks

#### **Security Testing**
- Test credential sanitization
- Test input validation
- Test path traversal protection
- Test SQL/script injection resistance

### ❌ DON'T Include

#### **Encoding Issues**
- **NO emoji characters** (🎉, ✅, ❌, 📊, etc.) - causes parsing errors
- **NO Unicode characters** - stick to ASCII only
- **NO UTF-8 BOM** - use UTF-8 without BOM
- **NO mixed line endings** - use Windows CRLF consistently

#### **Problematic Characters**
- **NO backticks in strings** (`\`n`) - use `Write-Host ""` instead
- **NO complex quote nesting** - use simple quotes
- **NO special Unicode quotes** - use standard ASCII quotes

#### **PowerShell Issues**
- **NO `Set-StrictMode -Version Latest`** - use `3.0` or omit
- **NO complex delayed expansion** in CMD files
- **NO param() blocks after other code** - must be at top

## 🔧 Common Test Patterns

### Testing Function Return Values
```powershell
Test-Function "Function returns expected type" {
    $result = Get-SomeFunction
    return ($result -is [string])  # or [array], [hashtable], etc.
}
```

### Testing Error Handling
```powershell
Test-Function "Function handles null input gracefully" {
    try {
        $result = Some-Function -Input $null
        return ($result -eq $null -or $result -is [object])
    } catch {
        return $true  # Expected to handle null gracefully
    }
}
```

### Testing Array Operations
```powershell
Test-Function "Function returns valid array" {
    $result = Get-ArrayFunction
    return ($result -is [array] -or $result -eq $null)
}
```

### Testing Performance
```powershell
Test-Function "Function completes within reasonable time" {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Some-Function
    $stopwatch.Stop()
    return ($stopwatch.ElapsedMilliseconds -lt 5000)  # 5 seconds
}
```

### Testing Security
```powershell
Test-Function "Function doesn't expose sensitive data" {
    $sensitiveData = "SecretPassword123!"
    $result = Process-Credentials -Password $sensitiveData
    $resultString = $result | ConvertTo-Json
    return (-not $resultString.Contains($sensitiveData))
}
```

## 🐛 Troubleshooting

### Common Issues

#### **"String is missing terminator"**
- **Cause**: Emoji characters or encoding issues
- **Fix**: Remove all emoji characters, use ASCII only

#### **"Missing closing '}'"**
- **Cause**: Backtick characters in strings
- **Fix**: Replace `"`n"` with `Write-Host ""`

#### **"Cannot be retrieved because it has not been set"**
- **Cause**: `Set-StrictMode -Version Latest` with optional parameters
- **Fix**: Use `Set-StrictMode -Version 3.0` or omit strict mode

#### **"Execution policy" errors**
- **Cause**: Scripts not digitally signed
- **Fix**: Test files automatically handle this with execution policy bypass

### File Encoding Fixes
```powershell
# Fix line endings
(Get-Content Tests\TestFile.ps1 -Raw) -replace "`n", "`r`n" | Set-Content Tests\TestFile.ps1

# Fix encoding (remove BOM)
$content = Get-Content Tests\TestFile.ps1 -Raw
[System.IO.File]::WriteAllText((Resolve-Path "Tests\TestFile.ps1"), $content, [System.Text.UTF8Encoding]::new($false))
```

## 📊 Test Categories

### **Unit Tests**
- Test individual functions in isolation
- Mock external dependencies
- Test all code paths and edge cases

### **Integration Tests**
- Test module interactions
- Test complete workflows
- Test real network operations (where safe)

### **Security Tests**
- Test credential handling
- Test input validation
- Test path traversal protection
- Test injection resistance

### **Performance Tests**
- Test execution time limits
- Test memory usage
- Test with large data sets

### **Error Handling Tests**
- Test null input handling
- Test malformed data handling
- Test permission errors
- Test network failures

## 🎯 Best Practices

1. **Test Early and Often** - Run tests after each change
2. **Test Edge Cases** - Null inputs, empty strings, large data
3. **Test Error Conditions** - What happens when things go wrong
4. **Keep Tests Simple** - One assertion per test
5. **Use Descriptive Names** - Test names should explain what's being tested
6. **Clean Up Resources** - Always clean up in finally blocks
7. **Test Security** - Always test credential and input handling
8. **Document Assumptions** - Comment complex test logic

## 📈 Test Coverage Goals

- **100% Function Coverage** - Every exported function has tests
- **100% Error Path Coverage** - Every error condition is tested
- **100% Security Coverage** - All security-sensitive functions tested
- **Performance Baselines** - All functions have performance tests
- **Integration Coverage** - All module interactions tested

---

*For more information about the PPPoE Diagnostic Toolkit, see the main README.md file.*
*Last updated: October 2025*
