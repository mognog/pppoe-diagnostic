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

## ⚡ Writing Optimized Tests (Start Here!)

Before writing any tests, understand these key principles to avoid creating slow tests:

### 🎯 Golden Rules for Fast Tests

1. **Expensive operations run ONCE, assertions run MANY times**
2. **Use silent loggers**: `{ param($msg) }` instead of `{ param($msg) Write-Host $msg }`
3. **Test parameter existence vs. execution** when possible
4. **Group related tests** to share setup
5. **Use static analysis** for code quality checks

### 📐 Test Design Pattern: Shared Setup

**❌ ANTI-PATTERN: Repeated Expensive Operations**
```powershell
# BAD: Each test runs full hardware scan (20s × 10 = 200s total)
Test-Function "Test 1" {
    $result = Invoke-QuickDiagnosticWorkflow -WriteLog { param($msg) Write-Host $msg }
    return $result.Health -is [hashtable]
}

Test-Function "Test 2" {
    $result = Invoke-QuickDiagnosticWorkflow -WriteLog { param($msg) Write-Host $msg }
    return $result.Adapter -ne $null
}
# ... 8 more tests, each taking 20s
# TOTAL TIME: 200 seconds
```

**✅ BEST PRACTICE: Shared Setup Pattern**
```powershell
# GOOD: Run expensive operation once, test many assertions
Write-Host "[1/2] Running workflow once (silent mode)..."
$silentLogger = { param($msg) }  # No output = faster
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$sharedResult = Invoke-QuickDiagnosticWorkflow -WriteLog $silentLogger
$stopwatch.Stop()
Write-Host "  Completed in $($stopwatch.ElapsedMilliseconds)ms"

Write-Host "[2/2] Testing assertions (10 tests)..."
Test-Function "Test 1" { $sharedResult.Health -is [hashtable] }      # Instant
Test-Function "Test 2" { $sharedResult.Adapter -ne $null }           # Instant
Test-Function "Test 3" { $sharedResult.PPPInterface -eq $null }      # Instant
# ... 7 more instant tests
# TOTAL TIME: 20 seconds (10x faster!)
```

### 🔍 Identifying Expensive Operations

Operations that should run **once** and be shared:
- ✋ Hardware scans: `Get-NetAdapter`, `Get-CandidateEthernetAdapters`
- ✋ Network calls: `Test-PingHost`, `Test-Connection`, PPPoE connections
- ✋ Full workflows: `Invoke-QuickDiagnosticWorkflow`, `Invoke-PPPoEDiagnosticWorkflow`
- ✋ System queries: `Get-NetRoute`, `Get-Process`, registry access
- ✋ File I/O: Large file reads, directory scans

Operations that are **fast** and can run per test:
- ✅ Type checks: `$result -is [hashtable]`
- ✅ Property access: `$result.Property`
- ✅ String operations: `-match`, `-replace`, `.Contains()`
- ✅ Simple arithmetic: comparisons, calculations
- ✅ Parameter existence: `(Get-Command).Parameters.ContainsKey()`

### 📋 Template for Optimized Tests

```powershell
# OptimizedTest.Tests.ps1

$originalPolicy = Get-ExecutionPolicy -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

try {
    # Import modules
    Import-Module "./Modules/YourModule.psm1" -Force
    
    Write-Host "Running optimized tests..." -ForegroundColor Cyan
    
    function Test-Assertion {
        param([string]$Name, [scriptblock]$TestScript)
        try {
            $result = & $TestScript
            if ($result) {
                Write-Host "  PASS: $Name" -ForegroundColor Green
                return $true
            } else {
                Write-Host "  FAIL: $Name" -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "  FAIL: $Name - $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    $passed = 0
    $failed = 0
    $totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    # ================================================
    # PHASE 1: Run expensive operations ONCE
    # ================================================
    Write-Host "[1/3] Running expensive setup once..." -ForegroundColor Cyan
    $silentLogger = { param($msg) }  # Silent for speed
    
    try {
        $sharedResult = Invoke-ExpensiveOperation -WriteLog $silentLogger
        $setupSuccess = $true
    } catch {
        $sharedResult = $null
        $setupSuccess = $false
        $setupError = $_.Exception.Message
    }
    
    Write-Host ""
    
    # ================================================
    # PHASE 2: Test structure (fast assertions)
    # ================================================
    Write-Host "[2/3] Testing structure (5 assertions)..." -ForegroundColor Cyan
    
    if (Test-Assertion "Setup succeeded" { $setupSuccess }) { $passed++ } else { $failed++ }
    if (Test-Assertion "Returns hashtable" { $sharedResult -is [hashtable] }) { $passed++ } else { $failed++ }
    if (Test-Assertion "Has required keys" { $sharedResult.ContainsKey('Key1') }) { $passed++ } else { $failed++ }
    if (Test-Assertion "Property is valid" { $sharedResult.Property -ne $null }) { $passed++ } else { $failed++ }
    if (Test-Assertion "No errors occurred" { -not $setupError }) { $passed++ } else { $failed++ }
    
    Write-Host ""
    
    # ================================================
    # PHASE 3: Static analysis (no execution needed)
    # ================================================
    Write-Host "[3/3] Static analysis (3 assertions)..." -ForegroundColor Cyan
    
    if (Test-Assertion "Function exported" { Get-Command Invoke-ExpensiveOperation -EA SilentlyContinue }) { $passed++ } else { $failed++ }
    if (Test-Assertion "Has required parameter" { 
        (Get-Command Invoke-ExpensiveOperation).Parameters.ContainsKey('WriteLog')
    }) { $passed++ } else { $failed++ }
    if (Test-Assertion "Code uses best practices" {
        $content = Get-Content "./Modules/YourModule.psm1" -Raw
        $content -match '-is \[hashtable\] -and'  # Verify type checking
    }) { $passed++ } else { $failed++ }
    
    $totalStopwatch.Stop()
    
    # ================================================
    # Summary
    # ================================================
    Write-Host ""
    Write-Host "Test Results:" -ForegroundColor Cyan
    Write-Host "  Passed: $passed" -ForegroundColor Green
    Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Gray' })
    Write-Host "  Time: $([math]::Round($totalStopwatch.Elapsed.TotalSeconds, 1))s" -ForegroundColor White
    
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
    Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force
}
```

### 🎨 Optimization Techniques

#### 1. Silent Loggers for Speed
```powershell
# SLOW: Verbose logging (writes to console every time)
$verboseLogger = { param($msg) Write-Host $msg }
$result = Invoke-Workflow -WriteLog $verboseLogger

# FAST: Silent logging (no console overhead)
$silentLogger = { param($msg) }
$result = Invoke-Workflow -WriteLog $silentLogger
```

#### 2. Test Parameter Existence Instead of Execution
```powershell
# SLOW: Run workflow to test parameter (20 seconds)
Test-Function "Accepts SkipWifiToggle parameter" {
    $result = Invoke-QuickDiagnosticWorkflow -SkipWifiToggle -WriteLog { param($msg) }
    return $result -ne $null
}

# FAST: Check parameter exists (instant)
Test-Function "Has SkipWifiToggle parameter" {
    return (Get-Command Invoke-QuickDiagnosticWorkflow).Parameters.ContainsKey('SkipWifiToggle')
}
```

#### 3. Static Analysis for Code Quality
```powershell
# FAST: Verify code patterns without execution (instant)
Test-Function "Uses safe hashtable access" {
    $content = Get-Content "Modules/MyModule.psm1" -Raw
    $unsafeCalls = $content | Select-String -Pattern '\$\w+ -and \$\w+\.ContainsKey' -AllMatches
    $safeCalls = $content | Select-String -Pattern '-is \[hashtable\] -and \$\w+\.ContainsKey' -AllMatches
    
    # All ContainsKey calls should be protected with type check
    return $unsafeCalls.Matches.Count -eq $safeCalls.Matches.Count
}
```

#### 4. Batch Related Tests
```powershell
# GOOD: Group tests by shared setup requirements
Write-Host "=== Testing Network Functions (shared network state) ==="
$adapters = Get-NetAdapter  # Get once
Test-Function "Has adapters" { $adapters.Count -gt 0 }
Test-Function "First adapter valid" { $adapters[0].Status -ne $null }
Test-Function "Has Ethernet" { $adapters | Where-Object { $_.Name -match 'Ethernet' } }
```

### 📊 Performance Benchmarking

Always measure test performance during development:

```powershell
# Add timing to your test template
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# ... run tests ...

$stopwatch.Stop()
Write-Host "Total time: $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s" -ForegroundColor $(
    if ($stopwatch.Elapsed.TotalSeconds -lt 30) { 'Green' }
    elseif ($stopwatch.Elapsed.TotalSeconds -lt 60) { 'Yellow' }
    else { 'Red' }
)

# Guidelines:
# - Unit tests: < 5 seconds (Green)
# - Integration tests: < 30 seconds (Yellow)
# - Full workflow tests: < 60 seconds (acceptable)
# - Anything > 60s: Needs optimization (Red)
```

### ⚠️ Common Pitfalls to Avoid

#### 1. Don't Call Workflows in Loops
```powershell
# ❌ BAD: 100 seconds for 5 tests
$testCases = @('Case1', 'Case2', 'Case3', 'Case4', 'Case5')
foreach ($case in $testCases) {
    Test-Function "Test $case" {
        $result = Invoke-QuickDiagnosticWorkflow  # 20s each time!
        return $result.SomeProperty -eq $case
    }
}

# ✅ GOOD: 20 seconds for 5 tests
$sharedResult = Invoke-QuickDiagnosticWorkflow  # Once
foreach ($case in $testCases) {
    Test-Function "Test $case" {
        return $sharedResult.SomeProperty -eq $case  # Instant
    }
}
```

#### 2. Don't Use Verbose Logging in Tests
```powershell
# ❌ BAD: Slows down execution significantly
$result = Invoke-Workflow -WriteLog { param($msg) Write-Host $msg -Verbose }

# ✅ GOOD: Use silent logger unless debugging
$result = Invoke-Workflow -WriteLog { param($msg) }
```

#### 3. Don't Test Implementation Details
```powershell
# ❌ BAD: Tests internal implementation (brittle and slow)
Test-Function "Uses specific adapter selection logic" {
    # Reading source code, checking internal function calls, etc.
}

# ✅ GOOD: Test public interface and behavior
Test-Function "Returns valid adapter" {
    $adapter = Get-RecommendedAdapter
    return $adapter -ne $null -and $adapter.Status -eq 'Up'
}
```

### 🎯 Test Speed Goals

| Test Type | Target Time | Example |
|-----------|-------------|---------|
| **Unit Test** | < 5s | Test single function with mocks |
| **Integration Test** | < 30s | Test module interaction, shared setup |
| **Workflow Test** | < 60s | Test full diagnostic, run once |
| **Full Suite** | < 120s | All optimized tests |

### 📈 Real-World Examples

See these optimized test files for reference:
- `Tests/PPPoE.WorkflowErrorHandling.Tests.ps1` - 13.5x faster (283s → 21s)
- `Tests/PPPoE.Workflows.Tests.Fast.ps1` - 4x faster (170s → 41s)
- `Tests/PPPoE.HealthChecks.Tests.Fast.ps1` - 10x faster (206s → 21s)

---

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

### Run Fast Tests Only (Recommended for Development)
```powershell
# Fast test suite (~99 seconds vs ~692 seconds)
.\Tests\Run-Tests-Fast.ps1

# Individual optimized tests
.\Tests\PPPoE.Workflows.Tests.Fast.ps1        # 41s
.\Tests\PPPoE.HealthChecks.Tests.Fast.ps1     # 21s
.\Tests\PPPoE.WorkflowErrorHandling.Tests.ps1 # 21s
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

### Optimizing Expensive Tests (Shared Setup Pattern)
```powershell
# SLOW: Running expensive operation for each test (12x slower)
Test-Function "Test 1" {
    $result = Invoke-ExpensiveWorkflow  # Takes 20 seconds
    return $result.Property1 -eq "expected"
}
Test-Function "Test 2" {
    $result = Invoke-ExpensiveWorkflow  # Takes 20 seconds again
    return $result.Property2 -eq "expected"
}
# Total: 40 seconds for 2 tests

# FAST: Run expensive operation once, test multiple assertions (12x faster)
Write-Host "Running workflow once..."
$sharedResult = Invoke-ExpensiveWorkflow  # Takes 20 seconds once
Write-Host "Testing assertions..."

Test-Function "Test 1" {
    return $sharedResult.Property1 -eq "expected"  # Instant
}
Test-Function "Test 2" {
    return $sharedResult.Property2 -eq "expected"  # Instant
}
# Total: 20 seconds for 2 tests

# Use silent loggers for faster execution
$silentLogger = { param($msg) }  # No output
$result = Invoke-Workflow -WriteLog $silentLogger
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
9. **Optimize Expensive Operations** - Run workflows/hardware scans once, test multiple assertions against the same result
10. **Use Silent Loggers in Tests** - Use `{ param($msg) }` instead of verbose logging for faster test execution

## 📈 Test Coverage Goals

- **100% Function Coverage** - Every exported function has tests
- **100% Error Path Coverage** - Every error condition is tested
- **100% Security Coverage** - All security-sensitive functions tested
- **Performance Baselines** - All functions have performance tests
- **Integration Coverage** - All module interactions tested

---

*For more information about the PPPoE Diagnostic Toolkit, see the main README.md file.*
*Last updated: October 2025*
