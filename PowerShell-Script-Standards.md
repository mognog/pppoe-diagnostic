# PowerShell Script Standards for PPPoE Diagnostic Project

## Overview

This document establishes coding standards and best practices for PowerShell scripts in the PPPoE Diagnostic Toolkit project. These standards promote maintainability, readability, and scalability while ensuring consistent code quality across the project.

## Table of Contents

1. [File Size and Structure](#file-size-and-structure)
2. [DRY (Don't Repeat Yourself) Principles](#dry-dont-repeat-yourself-principles)
3. [SOLID Principles](#solid-principles)
4. [Modular Design with Reusable Functions](#modular-design-with-reusable-functions)
5. [Naming Conventions](#naming-conventions)
6. [Code Organization](#code-organization)
7. [Error Handling](#error-handling)
8. [Documentation Standards](#documentation-standards)
9. [Performance Considerations](#performance-considerations)
10. [Security Best Practices](#security-best-practices)
11. [Testing Standards](#testing-standards)

---

## File Size and Structure

### Maximum File Length
- **Target: 300 lines per file**
- **Hard limit: 400 lines**
- When approaching limits, refactor into smaller modules or functions
- Main entry scripts should focus on orchestration, not implementation

### File Structure Template
```powershell
# ScriptName.ps1 - Brief description
#Requires -Version 7.0

<#
.SYNOPSIS
    Brief description of script purpose

.DESCRIPTION
    Detailed description of functionality

.PARAMETER ParameterName
    Description of parameter

.EXAMPLE
    Example usage

.NOTES
    Additional notes and requirements
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ParameterName,
    
    [switch]$OptionalSwitch
)

# Set error handling
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

# Import required modules
Import-Module ".\Modules\ModuleName.psm1" -Force

# Main script logic
try {
    # Implementation here
} catch {
    # Error handling
} finally {
    # Cleanup
}
```

---

## DRY (Don't Repeat Yourself) Principles

### Function Extraction
- Extract repeated code blocks into reusable functions
- Identify patterns in parameter handling, error checking, and logging
- Create utility functions for common operations

### Examples of DRY Violations to Avoid
```powershell
# BAD: Repeated code
Write-Log "Starting operation 1..."
$result1 = Test-Connection -TargetName "1.1.1.1" -Count 2
if ($result1) {
    Write-Log "Operation 1 successful"
} else {
    Write-Log "Operation 1 failed"
}

Write-Log "Starting operation 2..."
$result2 = Test-Connection -TargetName "8.8.8.8" -Count 2
if ($result2) {
    Write-Log "Operation 2 successful"
} else {
    Write-Log "Operation 2 failed"
}
```

### Good: DRY Implementation
```powershell
# GOOD: Extracted function
function Test-ConnectivityWithLogging {
    param(
        [string]$TargetName,
        [string]$OperationName
    )
    
    Write-Log "Starting $OperationName..."
    $result = Test-Connection -TargetName $TargetName -Count 2
    if ($result) {
        Write-Log "$OperationName successful"
        return $true
    } else {
        Write-Log "$OperationName failed"
        return $false
    }
}

# Usage
Test-ConnectivityWithLogging -TargetName "1.1.1.1" -OperationName "Cloudflare test"
Test-ConnectivityWithLogging -TargetName "8.8.8.8" -OperationName "Google DNS test"
```

---

## SOLID Principles

### Single Responsibility Principle (SRP)
- Each function should have one clear purpose
- Separate concerns (logging, networking, health checks, etc.)
- Functions should be testable in isolation

```powershell
# GOOD: Single responsibility
function Get-NetworkAdapterStatus {
    param([string]$AdapterName)
    # Only handles adapter status retrieval
}

function Test-AdapterConnectivity {
    param([string]$AdapterName)
    # Only handles connectivity testing
}

# BAD: Multiple responsibilities
function Get-NetworkAdapterStatusAndTestConnectivity {
    param([string]$AdapterName)
    # Handles both status retrieval AND connectivity testing
}
```

### Open/Closed Principle (OCP)
- Design functions to be extensible without modification
- Use parameters and switch statements for different behaviors

```powershell
# GOOD: Extensible design
function Test-NetworkConnectivity {
    param(
        [string]$Target,
        [ValidateSet('Ping', 'TCP', 'HTTP')]
        [string]$TestType = 'Ping'
    )
    
    switch ($TestType) {
        'Ping' { return Test-PingConnectivity -Target $Target }
        'TCP' { return Test-TCPConnectivity -Target $Target }
        'HTTP' { return Test-HTTPConnectivity -Target $Target }
    }
}
```

### Interface Segregation Principle (ISP)
- Functions should accept only necessary parameters
- Avoid "god functions" with too many optional parameters
- Create specialized functions for specific use cases

### Dependency Inversion Principle (DIP)
- Depend on abstractions (interfaces) rather than concrete implementations
- Use dependency injection patterns where appropriate

```powershell
# GOOD: Dependency injection
function Write-HealthSummary {
    param(
        [hashtable]$Health,
        [scriptblock]$WriteLogFunction = ${function:Write-Log}
    )
    
    & $WriteLogFunction "Health Summary:"
    # Implementation using injected function
}
```

---

## Modular Design with Reusable Functions

### Module Organization
- Group related functions into modules (`.psm1` files)
- Use clear module boundaries (Core, Network, Health, Logging)
- Export only necessary functions

### Function Design Guidelines
- **Single purpose**: One function, one responsibility
- **Pure functions**: Minimize side effects when possible
- **Idempotent**: Functions should be safe to call multiple times
- **Consistent return types**: Use standardized return objects

### Example Module Structure
```powershell
# PPPoE.Core.psm1
Set-StrictMode -Version 3.0

function Start-AsciiTranscript {
    param([string]$Path)
    # Implementation
}

function Write-Log {
    param([string]$Message)
    # Implementation
}

function Test-PwshVersion7Plus {
    # Implementation
}

Export-ModuleMember -Function Start-AsciiTranscript, Write-Log, Test-PwshVersion7Plus
```

### Reusable Function Patterns
```powershell
# Standard return object pattern
function Test-Connectivity {
    param([string]$Target)
    
    try {
        $result = Test-Connection -TargetName $Target -Count 2 -ErrorAction Stop
        return @{
            Success = $true
            Target = $Target
            Latency = $result.ResponseTime
            Error = $null
        }
    } catch {
        return @{
            Success = $false
            Target = $Target
            Latency = $null
            Error = $_.Exception.Message
        }
    }
}
```

---

## Naming Conventions

### Functions
- **Verb-Noun format**: `Get-NetworkAdapter`, `Test-Connectivity`
- **Use approved verbs**: Get, Set, Test, New, Remove, etc.
- **Descriptive nouns**: `Get-AdapterDriverInfo` not `Get-Driver`

### Variables
- **PascalCase**: `$AdapterName`, `$ConnectionResult`
- **Descriptive names**: `$pppInterface` not `$if`
- **Avoid abbreviations**: `$InterfaceIndex` not `$ifIdx`

### Constants
- **UPPER_CASE**: `$DEFAULT_TIMEOUT_SECONDS`, `$MAX_RETRY_COUNT`

### Parameters
- **PascalCase**: `[string]$AdapterName`
- **Use parameter attributes**: `[Parameter(Mandatory=$true)]`

---

## Code Organization

### File Organization
```
pppoe-diagnostic-v11a/
├── Modules/                 # Reusable modules
│   ├── PPPoE.Core.psm1      # Core utilities
│   ├── PPPoE.Net.psm1       # Network operations
│   ├── PPPoE.Health.psm1    # Health checking
│   └── PPPoE.Logging.psm1   # Logging utilities
├── Tests/                   # Unit tests (keeps root clean)
│   ├── PPPoE.Core.Tests.ps1
│   ├── PPPoE.Net.Tests.ps1
│   ├── PPPoE.Health.Tests.ps1
│   └── PPPoE.Integration.Tests.ps1
├── logs/                    # Diagnostic transcripts
├── tools/                   # Utility scripts
│   └── Normalize-Ascii.ps1
├── Invoke-PppoeDiagnostics.ps1  # Main entry script
├── Run-Diagnostics.cmd      # Easy launcher
├── credentials.ps1          # Credential configuration
├── PowerShell-Script-Standards.md
├── Refactoring-Recommendations.md
└── README.md
```

### Code Flow
1. **Parameter validation** at the top
2. **Module imports** after parameters
3. **Main logic** in try-catch blocks
4. **Cleanup** in finally blocks

### Function Organization Within Files
1. **Private functions** (internal use)
2. **Public functions** (exported)
3. **Export statements** at the end

---

## Error Handling

### Error Action Preference
```powershell
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
```

### Try-Catch Patterns
```powershell
# Standard pattern
try {
    $result = Some-Operation -ErrorAction Stop
    return $result
} catch {
    Write-Log "Error in Some-Operation: $($_.Exception.Message)"
    return $null
}

# With specific error types
try {
    $result = Test-Connection -TargetName $Target -ErrorAction Stop
} catch [System.Net.NetworkInformation.PingException] {
    Write-Log "Network unreachable: $Target"
} catch {
    Write-Log "Unexpected error: $($_.Exception.Message)"
}
```

### Error Return Patterns
```powershell
# Consistent error return format
function Test-Operation {
    try {
        # Operation logic
        return @{
            Success = $true
            Result = $data
            Error = $null
        }
    } catch {
        return @{
            Success = $false
            Result = $null
            Error = $_.Exception.Message
        }
    }
}
```

---

## Documentation Standards

### Comment-Based Help
```powershell
function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Tests network connectivity to a specified target
    
    .DESCRIPTION
        Performs a comprehensive connectivity test to the specified target,
        including ping and TCP port tests. Returns detailed results about
        the connection status.
    
    .PARAMETER TargetName
        The hostname or IP address to test connectivity to
    
    .PARAMETER Port
        The TCP port to test (optional)
    
    .PARAMETER Count
        Number of ping attempts (default: 2)
    
    .EXAMPLE
        Test-NetworkConnectivity -TargetName "google.com"
    
    .EXAMPLE
        Test-NetworkConnectivity -TargetName "192.168.1.1" -Port 80 -Count 5
    
    .OUTPUTS
        System.Hashtable. Returns a hashtable with Success, Latency, and Error properties
    
    .NOTES
        Requires PowerShell 7.0 or later
        Requires network connectivity for accurate results
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetName,
        
        [int]$Port,
        
        [int]$Count = 2
    )
    
    # Implementation here
}
```

### Inline Comments
```powershell
# Check if adapter exists before testing connectivity
if (-not $adapter) {
    Write-Log "Adapter not found: $AdapterName"
    return $false
}

# Test connectivity with 2 ping attempts and 2-second timeout
$result = Test-Connection -TargetName $Target -Count 2 -TimeoutSeconds 2
```

---

## Performance Considerations

### Efficient Operations
- Use `-ErrorAction SilentlyContinue` for non-critical operations
- Cache frequently accessed data
- Minimize external command calls
- Use parallel processing where appropriate

### Memory Management
- Dispose of objects when no longer needed
- Avoid creating large arrays in memory
- Use streaming operations for large datasets

### Example: Efficient Network Testing
```powershell
function Test-MultipleTargets {
    param([string[]]$Targets)
    
    # Use parallel processing for multiple targets
    $jobs = @()
    foreach ($target in $Targets) {
        $jobs += Start-Job -ScriptBlock {
            param($t)
            Test-Connection -TargetName $t -Count 2 -Quiet
        } -ArgumentList $target
    }
    
    # Collect results
    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job
    
    return $results
}
```

---

## Security Best Practices

### Credential Handling
- Never hardcode credentials in scripts
- Use `Get-Credential` or secure credential files
- Avoid logging sensitive information

### Input Validation
```powershell
function Test-Connectivity {
    param(
        [Parameter(Mandatory=$true)]
        [ValidatePattern('^[a-zA-Z0-9.-]+$')]
        [string]$TargetName
    )
    
    # Implementation with validated input
}
```

### File Path Security
```powershell
# Use Resolve-Path for safe path handling
$logPath = Resolve-Path -Path $logPath -ErrorAction Stop
```

---

## Testing Standards

### PowerShell Testing with Pester

PowerShell has excellent testing support through **Pester**, the industry-standard testing framework. For a diagnostic utility, testing ensures reliability without adding complexity.

### Installation
```powershell
# Install Pester (run once)
Install-Module -Name Pester -Force -SkipPublisherCheck
```

### Test File Structure
```
pppoe-diagnostic-v11a/
├── Modules/
│   ├── PPPoE.Core.psm1
│   ├── PPPoE.Net.psm1
│   ├── PPPoE.Health.psm1
│   └── PPPoE.Logging.psm1
├── Tests/
│   ├── PPPoE.Core.Tests.ps1
│   ├── PPPoE.Net.Tests.ps1
│   ├── PPPoE.Health.Tests.ps1
│   └── PPPoE.Integration.Tests.ps1
├── Invoke-PppoeDiagnostics.ps1
├── Run-Diagnostics.cmd
├── credentials.ps1
├── PowerShell-Script-Standards.md
├── Refactoring-Recommendations.md
└── README.md
```

### Unit Test Examples
```powershell
# Tests/PPPoE.Core.Tests.ps1
Import-Module "..\Modules\PPPoE.Core.psm1" -Force

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
}

Describe "Get-IpClass" {
    It "Should classify public IPs correctly" {
        $result = Get-IpClass -IPv4 "8.8.8.8"
        $result | Should -Be "PUBLIC"
    }
    
    It "Should classify private IPs correctly" {
        $result = Get-IpClass -IPv4 "192.168.1.1"
        $result | Should -Be "PRIVATE"
    }
    
    It "Should classify CGNAT IPs correctly" {
        $result = Get-IpClass -IPv4 "100.64.1.1"
        $result | Should -Be "CGNAT"
    }
}
```

### Network Function Testing (with Mocking)
```powershell
# Tests/PPPoE.Net.Tests.ps1
Import-Module "..\Modules\PPPoE.Net.psm1" -Force

Describe "Test-PingHost" {
    It "Should return true for successful ping" {
        # Mock Test-Connection to simulate success
        Mock Test-Connection { return @{ ResponseTime = 10 } }
        
        $result = Test-PingHost -TargetName "1.1.1.1" -Count 2
        $result | Should -Be $true
    }
    
    It "Should return false for failed ping" {
        # Mock Test-Connection to simulate failure
        Mock Test-Connection { throw "Network unreachable" }
        
        $result = Test-PingHost -TargetName "invalid.target" -Count 2
        $result | Should -Be $false
    }
}

Describe "Get-CandidateEthernetAdapters" {
    It "Should return only Ethernet adapters" {
        # Mock Get-NetAdapter with test data
        $mockAdapters = @(
            @{ Name = "Ethernet"; MediaType = "802.3"; Status = "Up" },
            @{ Name = "WiFi"; MediaType = "802.11"; Status = "Up" },
            @{ Name = "Ethernet 2"; MediaType = "802.3"; Status = "Down" }
        )
        Mock Get-NetAdapter { return $mockAdapters }
        
        $result = Get-CandidateEthernetAdapters
        
        $result | Should -HaveCount 2
        $result[0].Name | Should -Be "Ethernet"
        $result[1].Name | Should -Be "Ethernet 2"
    }
}
```

### Integration Testing
```powershell
# Tests/PPPoE.Integration.Tests.ps1
Describe "End-to-End Diagnostic Flow" {
    It "Should complete basic health checks" {
        # Test the actual diagnostic workflow
        $Health = New-Health
        
        # Test with localhost to avoid network dependencies
        $Health = Add-Health $Health 'Test Check' 'OK' 1
        
        $Health.Count | Should -BeGreaterThan 0
        $Health.ContainsKey('01_Test Check') | Should -Be $true
    }
}
```

### Running Tests
```powershell
# Run all tests from project root
Invoke-Pester .\Tests\

# Run specific test file
Invoke-Pester .\Tests\PPPoE.Core.Tests.ps1

# Run with detailed output
Invoke-Pester .\Tests\ -Output Detailed

# Run and generate coverage report
Invoke-Pester .\Tests\ -CodeCoverage .\Modules\PPPoE.Core.psm1

# Run tests from within Tests folder
cd Tests
Invoke-Pester
```

### Test Categories for Diagnostic Utilities
- **Unit tests**: Individual function testing with mocked dependencies
- **Integration tests**: Module interaction testing with real PowerShell cmdlets
- **Smoke tests**: Basic functionality verification (no network calls)

### Testing Best Practices for Diagnostic Scripts
- **Mock external dependencies**: Network calls, file operations, registry access
- **Test error conditions**: Invalid inputs, network failures, permission issues
- **Test return value structure**: Ensure consistent hashtable returns
- **Test parameter validation**: Verify input validation works correctly

### Simple Test Template
```powershell
# Template for testing any function
Describe "Function-Name" {
    Context "Valid inputs" {
        It "Should handle normal case" {
            $result = Function-Name -Parameter "valid_input"
            $result.Success | Should -Be $true
        }
    }
    
    Context "Invalid inputs" {
        It "Should handle null input" {
            $result = Function-Name -Parameter $null
            $result.Success | Should -Be $false
        }
    }
    
    Context "Error conditions" {
        It "Should handle network errors gracefully" {
            Mock External-Cmdlet { throw "Network error" }
            
            $result = Function-Name -Parameter "test"
            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }
}
```

---

## Project-Specific Guidelines

### Current Project Structure Compliance
Based on the existing PPPoE Diagnostic Toolkit:

1. **Main Entry Point**: `Invoke-PppoeDiagnostics.ps1` (649 lines - needs refactoring)
2. **Modules**: Well-organized into Core, Net, Health, and Logging modules
3. **Logging**: Consistent ASCII transcript logging
4. **Health System**: Structured health checking with ordered results

### Recommended Refactoring for Large Files
For files exceeding 300 lines:

1. **Extract diagnostic functions** into separate modules
2. **Create specialized health check modules**
3. **Separate network testing functions**
4. **Modularize credential handling**

### Example Refactoring Strategy
```powershell
# Current: Invoke-PppoeDiagnostics.ps1 (649 lines)
# Proposed structure:

# Scripts/Invoke-PppoeDiagnostics.ps1 (main orchestration, ~100 lines)
# Modules/PPPoE.Diagnostics.psm1 (diagnostic functions, ~200 lines)
# Modules/PPPoE.Credentials.psm1 (credential handling, ~150 lines)
# Modules/PPPoE.Advanced.psm1 (advanced tests, ~200 lines)
```

---

## Quality Assurance Standards

### Code Quality Validation
Before committing any changes, ensure:

- [ ] **No linter errors** - Run PowerShell Script Analyzer
- [ ] **All tests pass** - Run complete test suite
- [ ] **Documentation is current** - README reflects actual functionality
- [ ] **Code follows standards** - Adheres to all guidelines in this document

### PowerShell Script Analyzer Integration
```powershell
# Install PowerShell Script Analyzer (run once)
Install-Module -Name PSScriptAnalyzer -Force

# Check all modules for issues
Invoke-ScriptAnalyzer .\Modules\*.psm1

# Check main script
Invoke-ScriptAnalyzer .\Invoke-PppoeDiagnostics.ps1

# Check with specific rules
Invoke-ScriptAnalyzer .\Modules\ -IncludeRule PSUseApprovedVerbs, PSUseDeclaredVarsMoreThanAssignments

# Fix common issues automatically where possible
Invoke-ScriptAnalyzer .\Modules\ -Fix
```

### Pre-Commit Validation Script
```powershell
# validate-project.ps1 - Run before committing
Write-Host "🔍 Validating PowerShell Script Standards..." -ForegroundColor Cyan

# 1. Check file sizes
Write-Host "📏 Checking file sizes..." -ForegroundColor Yellow
$largeFiles = Get-ChildItem .\Modules\*.psm1 | Where-Object { (Get-Content $_.FullName | Measure-Object -Line).Lines -gt 300 }
if ($largeFiles) {
    Write-Host "❌ Files exceeding 300 lines:" -ForegroundColor Red
    $largeFiles | ForEach-Object { Write-Host "  - $($_.Name): $((Get-Content $_.FullName | Measure-Object -Line).Lines) lines" }
    exit 1
}

# 2. Run linter
Write-Host "🔍 Running PowerShell Script Analyzer..." -ForegroundColor Yellow
$lintResults = Invoke-ScriptAnalyzer .\Modules\*.psm1, .\Invoke-PppoeDiagnostics.ps1 -Severity Error, Warning
if ($lintResults) {
    Write-Host "❌ Linter issues found:" -ForegroundColor Red
    $lintResults | ForEach-Object { Write-Host "  - $($_.RuleName): $($_.Message)" }
    exit 1
}

# 3. Run tests
Write-Host "🧪 Running tests..." -ForegroundColor Yellow
if (Test-Path .\Tests\) {
    $testResults = Invoke-Pester .\Tests\ -PassThru
    if ($testResults.FailedCount -gt 0) {
        Write-Host "❌ Tests failed: $($testResults.FailedCount) failures" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ All tests passed: $($testResults.PassedCount) tests" -ForegroundColor Green
}

Write-Host "✅ All validations passed!" -ForegroundColor Green
```

### Documentation Standards

#### README.md Requirements
The README must include:

- [ ] **Clear project description** - What the diagnostic tool does
- [ ] **Installation instructions** - How to set up and run
- [ ] **Usage examples** - Command-line examples with parameters
- [ ] **Testing instructions** - How to run tests and validation
- [ ] **Troubleshooting section** - Common issues and solutions
- [ ] **File structure explanation** - What each folder/file contains
- [ ] **Credential setup** - How to configure authentication
- [ ] **System requirements** - PowerShell version, OS requirements

#### Example README Structure
```markdown
# PPPoE Diagnostic Toolkit

## Overview
Brief description of what this diagnostic tool does and why it's useful.

## Quick Start
```powershell
# Run with default settings
.\Run-Diagnostics.cmd

# Run with custom parameters
.\Invoke-PppoeDiagnostics.ps1 -PppoeName "MyISP" -FullLog
```

## Testing
```powershell
# Install Pester (first time only)
Install-Module -Name Pester -Force

# Run all tests
Invoke-Pester .\Tests\

# Run with detailed output
Invoke-Pester .\Tests\ -Output Detailed
```

## Project Structure
- `Modules/` - PowerShell modules containing diagnostic functions
- `Tests/` - Unit and integration tests
- `logs/` - Diagnostic output transcripts
- `tools/` - Utility scripts

## Troubleshooting
Common issues and their solutions...
```

### Validation Workflow
```powershell
# Complete validation before committing
.\validate-project.ps1

# If validation passes, commit changes
git add .
git commit -m "feat: Add new diagnostic function with tests"

# If validation fails, fix issues and re-run
```

## Implementation Checklist

When creating or modifying PowerShell scripts:

- [ ] File length is under 300 lines (400 max)
- [ ] Functions follow DRY principles
- [ ] SOLID principles are applied
- [ ] Functions are modular and reusable
- [ ] Naming conventions are followed
- [ ] Error handling is implemented
- [ ] Documentation is complete
- [ ] Security best practices are followed
- [ ] Performance is optimized
- [ ] Tests are written and passing
- [ ] **No linter errors** (PSScriptAnalyzer)
- [ ] **All tests pass** (Pester)
- [ ] **README is current** and comprehensive
- [ ] **Validation script passes** before committing

---

## Conclusion

These standards ensure that PowerShell scripts in the PPPoE Diagnostic Toolkit project are:
- **Maintainable**: Easy to understand and modify
- **Reliable**: Consistent error handling and validation
- **Reusable**: Modular design with clear interfaces
- **Secure**: Proper credential and input handling
- **Performant**: Optimized for efficiency

Regular code reviews should verify compliance with these standards, and the project should evolve these guidelines as new patterns emerge.
