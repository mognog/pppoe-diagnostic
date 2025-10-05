# PPPoE Diagnostic Toolkit - Tips & Troubleshooting

## ✅ DEFINITELY WORKS

### Basic Usage
```cmd
# Right-click Run-Diagnostics.cmd → Run as administrator
# OR run directly in PowerShell 7:
pwsh -NoProfile -ExecutionPolicy Bypass -File "Invoke-PppoeDiagnostics.ps1"
```

### PowerShell Script Structure
```powershell
# CORRECT: param() block must be at the top (after #Requires)
#Requires -Version 7.0

param(
  [string]$PppoeName = 'PPPoE',
  [string]$UserName,
  [string]$Password,
  [string]$TargetAdapter,
  [switch]$FullLog,
  [switch]$SkipWifiToggle,
  [switch]$KeepPPP
)

# CORRECT: Use strict mode version 3.0 (catches bugs but allows optional parameters)
Set-StrictMode -Version 3.0

# Rest of script...
```

### CMD File Structure (Working)
```cmd
@echo off
echo PPPoE Diagnostic Toolkit v11
echo =============================
echo.

:: Change to the directory where this script is located
cd /d "%~dp0"
echo Working directory: %CD%
echo.

where pwsh >nul 2>&1
if errorlevel 1 (
  echo ERROR: PowerShell 7 not found
  pause
  exit /b 1
)

echo Running diagnostics...
pwsh -NoProfile -ExecutionPolicy Bypass -File "Invoke-PppoeDiagnostics.ps1"
echo.
echo Press any key to close...
pause >nul
```

### Line Endings Fix
```powershell
# Convert Unix (LF) to Windows (CRLF) line endings:
(Get-Content file.ps1 -Raw) -replace "`n", "`r`n" | Set-Content file-fixed.ps1
```

### Module Loading
```powershell
# These work reliably:
Import-Module "$here/Modules/PPPoE.Core.psm1" -Force
Import-Module "$here/Modules/PPPoE.Net.psm1" -Force
Import-Module "$here/Modules/PPPoE.Logging.psm1" -Force
Import-Module "$here/Modules/PPPoE.Health.psm1" -Force
```

### Safe Array Indexing
```powershell
# CORRECT: Check array existence and count before indexing
if ($array -and $array.Count -gt 0) { 
  $firstItem = $array[0] 
} else { 
  $firstItem = $null 
}

# CORRECT: Safe property access on potentially null objects
$route = Get-NetRoute ... | Select-Object -First 1
$nextHop = if ($route) { $route.NextHop } else { $null }
```

### Safe Hashtable Method Calls
```powershell
# WRONG: Doesn't validate type before calling ContainsKey()
if ($result -and $result.ContainsKey('Health')) {
  # ❌ Fails if $result is a string or other non-hashtable type
}

# CORRECT: Type-check before calling hashtable-specific methods
if ($result -is [hashtable] -and $result.ContainsKey('Health')) {
  # ✓ Safe - only calls ContainsKey() on actual hashtables
  $health = $result.Health
}

# CORRECT: Alternative using try-catch
try {
  if ($result.ContainsKey('Health')) {
    $health = $result.Health
  }
} catch {
  # Handle case where $result isn't a hashtable
  $health = $null
}
```

### Array Return Behavior (PowerShell Gotchas)
```powershell
# PROBLEM: PowerShell functions can return null instead of empty arrays
function Bad-Function {
  $arr = @()
  return $arr  # ❌ May return null in some contexts
}

# PROBLEM: Where-Object on empty arrays returns null
$emptyArray = @()
$filtered = $emptyArray | Where-Object { $_.Status -eq "OK" }
# $filtered is $null, not an empty array!

# PROBLEM: Array count access without proper checking
$array = $null
$count = $array.Count  # ❌ "Cannot call method on null-valued expression"

# SOLUTION: Force array return behavior
function Good-Function {
  $arr = @()
  # Method 1: Use comma operator to force array
  return ,$arr
  
  # Method 2: Explicitly check and handle
  if ($arr.Count -eq 0) {
    return @()  # Explicit empty array
  } else {
    return $arr
  }
}

# SOLUTION: Safe array filtering and counting
function Safe-ArrayFilter {
  param($array)
  
  # Always ensure we have an array to work with
  if (-not $array) {
    $array = @()
  }
  
  $filtered = $array | Where-Object { $_.Status -eq "OK" }
  
  # Force array return - Where-Object can return null
  if (-not $filtered) {
    return ,@()
  } else {
    return ,$filtered
  }
}

# SOLUTION: Safe array count access
function Safe-ArrayCount {
  param($array)
  
  # Safe array count access pattern
  if ($array -and $array -is [array] -and $array.Count -gt 0) {
    return $array.Count
  } else {
    return 0
  }
}

# SOLUTION: Handle single-item arrays correctly
function Handle-SingleItem {
  $items = @("single-item")
  # Single-item arrays can be returned as strings!
  if ($items -is [string]) {
    return ,@($items)  # Force to array
  } else {
    return $items
  }
}

# VERIFICATION: Always test array returns
$result = Your-Function
Write-Host "Is array: $($result -is [array])"
Write-Host "Is null: $($result -eq $null)"
Write-Host "Count: $($result.Count)"
```

## ❌ DEFINITELY DOESN'T WORK

### PowerShell Script Issues
```powershell
# WRONG: param() block after other code
Set-StrictMode -Version Latest
param([string]$UserName)  # ❌ This will fail

# WRONG: Set-StrictMode -Version Latest with optional parameters
Set-StrictMode -Version Latest  # ❌ Causes "variable not set" errors

# WRONG: No strict mode at all (hides important bugs)
# Set-StrictMode commented out  # ❌ Allows typos and undefined variables

# WRONG: Complex delayed expansion in CMD
set "VAR=value"
echo !VAR!  # ❌ Can cause "was was unexpected at this time"
```

### CMD File Issues
```cmd
# WRONG: Complex PowerShell command with delayed expansion
powershell -Command "Start-Process -FilePath '!PWSH!' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','""!PS1!""' -WorkingDirectory '""!SCRIPT_DIR!""' -Verb RunAs"

# WRONG: Unix line endings in .cmd files
# File with LF (0A) instead of CRLF (0D 0A) causes batch errors
```

### File Encoding Issues
```powershell
# WRONG: UTF-8 with BOM in PowerShell scripts
# Can cause parameter parsing issues

# WRONG: Mixed line endings
# Some lines CRLF, others LF - causes parsing errors
```

## 🔧 COMMON FIXES

### "was was unexpected at this time"
- **Cause**: Unix line endings in .cmd files or complex delayed expansion
- **Fix**: Convert to Windows line endings: `(Get-Content file.cmd -Raw) -replace "`n", "`r`n" | Set-Content file.cmd`
- **Alternative**: Simplify the CMD file structure

### "The argument 'Invoke-PppoeDiagnostics.ps1' is not recognized as the name of a script file"
- **Cause**: CMD file running from wrong directory (usually C:\Windows\System32\ when run as admin)
- **Fix**: Add `cd /d "%~dp0"` at the beginning of CMD file to change to script's directory
- **Prevention**: Always include directory change in CMD files that reference other files

### "The variable '$UserName' cannot be retrieved because it has not been set"
- **Cause**: `Set-StrictMode -Version Latest` with optional parameters
- **Fix**: Use `Set-StrictMode -Version 3.0` (recommended - catches bugs while allowing optional parameters)
- **Alternative**: Move param() block to very top of script
- **Last Resort**: Comment out strict mode entirely (NOT recommended - hides important bugs)

### "Cannot index into a null array"
- **Cause**: Array indexing without checking if array exists and has elements
- **Fix**: Always check array existence and count before indexing: `if ($array -and $array.Count -gt 0) { $array[0] }`
- **Common locations**: `Get-RecommendedAdapter`, `Get-PppInterface` functions

### "You cannot call a method on a null-valued expression"
- **Cause**: Function returned null instead of expected array
- **Fix**: Use comma operator to force array return: `return ,@()` or `return ,$array`
- **Prevention**: Always test function returns: `$result = Your-Function; if ($result -is [array]) { ... }`

### "Method invocation failed because [System.String] does not contain a method named 'ContainsKey'"
- **Cause**: Calling `.ContainsKey()` on a variable without verifying it's a hashtable first
- **Wrong**: `if ($result -and $result.ContainsKey('Key'))` - fails if $result is a string
- **Fix**: `if ($result -is [hashtable] -and $result.ContainsKey('Key'))` - type-check first
- **Prevention**: Always validate type before calling type-specific methods
- **Common locations**: Workflow functions that receive hashtable returns from health check functions

### Array type changes unexpectedly (array becomes string)
- **Cause**: PowerShell converts single-item arrays to strings in some contexts
- **Fix**: Use comma operator or explicit array creation: `return ,@($singleItem)`
- **Detection**: `$result -is [string]` when expecting array

### "The term 'param' is not recognized"
- **Cause**: param() block not at the beginning of script
- **Fix**: Move param() block right after #Requires statement

### PowerShell 7 Not Found
- **Cause**: pwsh.exe not in PATH
- **Fix**: Install PowerShell 7 from Microsoft Store or GitHub releases
- **Check**: `where pwsh` should return a path

### Module Import Warnings
```powershell
# This warning is harmless but can be suppressed:
WARNING: The names of some imported commands from the module 'PPPoE.Net' include unapproved verbs
# Fix: Add -WarningAction SilentlyContinue to Import-Module calls
```

## 🚀 PERFORMANCE TIPS

### Faster Execution
```powershell
# Use -NoProfile for faster startup
pwsh -NoProfile -ExecutionPolicy Bypass -File "script.ps1"

# Skip verbose logging unless needed
.\Invoke-PppoeDiagnostics.ps1  # Default: concise logs
.\Invoke-PppoeDiagnostics.ps1 -FullLog  # Verbose logs
```

### Memory Management
```powershell
# The script automatically:
# - Cleans up PPP connections
# - Restores adapter states
# - Disposes transcript writers
# - Exits cleanly
```

## 📁 FILE STRUCTURE REQUIREMENTS

```
pppoe-diagnostic-v11a/
├── Invoke-PppoeDiagnostics.ps1  # Main script (CRLF line endings)
├── Run-Diagnostics.cmd          # Launcher (CRLF line endings)
├── Modules/
│   ├── PPPoE.Core.psm1          # Core functions
│   ├── PPPoE.Net.psm1           # Network operations
│   ├── PPPoE.Logging.psm1       # Logging helpers
│   └── PPPoE.Health.psm1        # Health checks
├── logs/                        # Auto-created
│   └── pppoe_transcript_*.txt   # Output logs
└── tools/
    └── Normalize-Ascii.ps1      # ASCII normalizer
```

## 🎯 QUICK DEBUGGING

### Test Components Individually
```cmd
# Test CMD file:
.\Run-Diagnostics.cmd

# Test PowerShell script directly:
pwsh -NoProfile -ExecutionPolicy Bypass -File "Invoke-PppoeDiagnostics.ps1"

# Test modules:
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Import-Module '.\Modules\PPPoE.Core.psm1' -Force; Write-Host 'OK'"
```

### Check File Encoding
```powershell
# Check line endings:
Get-Content file.ps1 -Raw | Format-Hex | Select-Object -First 5

# Should show 0D 0A (CRLF) for Windows files
# 0A only (LF) indicates Unix line endings - convert with fix above
```

### Verify PowerShell Version
```powershell
# Check version:
$PSVersionTable.PSVersion

# Should be 7.x or higher
# Script requires #Requires -Version 7.0
```

## 📋 TROUBLESHOOTING CHECKLIST

1. **File Issues**
   - [ ] Line endings are CRLF (Windows format)
   - [ ] No UTF-8 BOM in PowerShell files
   - [ ] param() block at top of PowerShell script
   - [ ] Set-StrictMode commented out or set to 3.0

2. **Environment Issues**
   - [ ] PowerShell 7+ installed (`where pwsh` works)
   - [ ] Running as Administrator (for network operations)
   - [ ] Execution policy allows scripts

3. **Network Issues**
   - [ ] Ethernet adapter detected
   - [ ] No competing network connections
   - [ ] PPPoE credentials available (saved or provided)

4. **Script Issues**
   - [ ] All modules in Modules/ directory
   - [ ] logs/ directory exists (auto-created)
   - [ ] No syntax errors in PowerShell scripts

## 🔍 LOG ANALYSIS

### Health Summary Interpretation
```
=== HEALTH SUMMARY (ASCII) ===
[1] PowerShell version .................. OK (7.5.3)
[2] Adapter detected/ready .............. OK (Realtek USB 5GbE @ 1 Gbps)
[3] Ethernet link state ................. OK (Up)
[4] Credentials source .................. WARN (Using saved credentials)
[5] PPPoE authentication ................ FAIL (691 bad credentials)
[6] PPP interface present ............... FAIL (not created)
OVERALL: FAIL
```

**Key indicators:**
- `OK` = Working correctly
- `WARN` = Works but not ideal (e.g., using saved credentials)
- `FAIL` = Problem that needs attention
- `N/A` = Skipped due to earlier failure

### Common Error Codes
- **691**: Bad username/password
- **651**: Modem/device error
- **619**: Port disconnected
- **678**: No answer from server (no PADO)

## 💡 BEST PRACTICES

1. **Always test with minimal parameters first**
2. **Use -SkipWifiToggle during development**
3. **Check logs/ directory for detailed transcripts**
4. **Run as Administrator for full network access**
5. **Keep scripts in dedicated directory with proper structure**
6. **Use version control for script changes**
7. **Test on clean Windows installations when possible**
8. **Test array-returning functions thoroughly**
   ```powershell
   # Always verify array functions return proper arrays
   $result = Your-Function
   if ($result -is [array]) {
     Write-Host "✓ Function returned array with $($result.Count) items"
   } else {
     Write-Host "✗ Function returned $($result.GetType().Name), expected array"
   }
   ```

---

*Last updated: October 2025*
*Version: v11a (Fixed line endings and script structure)*
