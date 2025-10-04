# Refactoring Recommendations for PPPoE Diagnostic Toolkit

## Current File Analysis

Based on the PowerShell Script Standards and current project analysis:

| File | Current Lines | Standard Limit | Status |
|------|---------------|----------------|--------|
| `Invoke-PppoeDiagnostics.ps1` | 609 lines | 300 lines | ⚠️ **EXCEEDS LIMIT** |
| `Modules/PPPoE.Net.psm1` | 1,246 lines | 300 lines | ⚠️ **SIGNIFICANTLY EXCEEDS** |
| `Modules/PPPoE.Core.psm1` | 76 lines | 300 lines | ✅ **WITHIN LIMIT** |
| `Modules/PPPoE.Health.psm1` | 35 lines | 300 lines | ✅ **WITHIN LIMIT** |
| `Modules/PPPoE.Logging.psm1` | 10 lines | 300 lines | ✅ **WITHIN LIMIT** |

## Priority 1: Refactor PPPoE.Net.psm1 (1,246 lines)

### Current Issues
- **Massive file size** (4x over limit)
- **Multiple responsibilities** (violates SRP)
- **Hard to maintain and test**
- **Difficult to navigate**

### Proposed Module Split

#### 1. PPPoE.Net.Adapters.psm1 (~200 lines)
**Functions to extract:**
- `Get-CandidateEthernetAdapters`
- `Get-RecommendedAdapter`
- `Select-NetworkAdapter`
- `Test-LinkUp`
- `Get-WiFiAdapters`
- `Disable-WiFiAdapters`
- `Enable-WiFiAdapters`
- `Get-LinkHealth`
- `Get-AdapterDriverInfo`

#### 2. PPPoE.Net.PPPoE.psm1 (~250 lines)
**Functions to extract:**
- `Disconnect-PPP`
- `Disconnect-AllPPPoE`
- `Connect-PPP`
- `Connect-PPPWithFallback`
- `Get-PppInterface`
- `Get-PppIPv4`
- `Test-DefaultRouteVia`
- `Get-DefaultRouteOwner`
- `Set-RouteMetrics`
- `Get-PPPoESessionInfo`

#### 3. PPPoE.Net.Connectivity.psm1 (~300 lines)
**Functions to extract:**
- `Test-PacketLoss`
- `Test-RouteStability`
- `Test-ConnectionStability`
- `Test-ConnectionJitter`
- `Test-BurstConnectivity`
- `Test-QuickConnectivityCheck`
- `Test-ProviderSpecificDiagnostics`
- `Test-TCPConnectivity`
- `Test-MultiDestinationRouting`
- `Get-InterfaceStatistics`

#### 4. PPPoE.Net.Diagnostics.psm1 (~200 lines)
**Functions to extract:**
- `Test-ONTAvailability`
- `Show-ONTLEDReminder`
- `Get-PPPGatewayInfo`
- `Test-FirewallState`
- `Test-DNSResolution`

#### 5. Update PPPoE.Net.psm1 (~100 lines)
**Remaining functions:**
- Core network utilities only
- Re-export functions from sub-modules
- Module documentation and metadata

### Implementation Steps

1. **Create new module files:**
   ```powershell
   # Create new modules
   New-Item "Modules\PPPoE.Net.Adapters.psm1"
   New-Item "Modules\PPPoE.Net.PPPoE.psm1"
   New-Item "Modules\PPPoE.Net.Connectivity.psm1"
   New-Item "Modules\PPPoE.Net.Diagnostics.psm1"
   ```

2. **Move functions to appropriate modules:**
   ```powershell
   # Extract function groups using search and replace
   # Update Import-Module statements in main script
   ```

3. **Update main script imports:**
   ```powershell
   # In Invoke-PppoeDiagnostics.ps1
   Import-Module "$here/Modules/PPPoE.Net.Adapters.psm1" -Force
   Import-Module "$here/Modules/PPPoE.Net.PPPoE.psm1" -Force
   Import-Module "$here/Modules/PPPoE.Net.Connectivity.psm1" -Force
   Import-Module "$here/Modules/PPPoE.Net.Diagnostics.psm1" -Force
   ```

## Priority 2: Refactor Invoke-PppoeDiagnostics.ps1 (609 lines)

### Current Issues
- **2x over recommended limit**
- **Mixed orchestration and implementation**
- **Complex health checking logic**
- **Hard to test individual components**

### Proposed Structure

#### 1. Extract Health Check Orchestration (~150 lines)
**Create:** `Modules/PPPoE.HealthChecks.psm1`
- Extract all health checking logic
- Centralize health check ordering and execution
- Return structured health results

#### 2. Extract Diagnostic Workflows (~200 lines)
**Create:** `Modules/PPPoE.Workflows.psm1`
- `Invoke-BasicSystemChecks`
- `Invoke-NetworkDiagnostics`
- `Invoke-ConnectivityTests`
- `Invoke-AdvancedDiagnostics`

#### 3. Extract Credential Management (~100 lines)
**Create:** `Modules/PPPoE.Credentials.psm1`
- `Get-CredentialsFromFile`
- `Get-CredentialsFromParameters`
- `Test-CredentialSources`
- `Connect-WithCredentialFallback`

#### 4. Streamline Main Script (~150 lines)
**Remaining in main script:**
- Parameter handling
- Module imports
- High-level orchestration
- Error handling and cleanup

### Implementation Steps

1. **Extract health check functions:**
   ```powershell
   # Move health checking logic to PPPoE.HealthChecks.psm1
   function Invoke-HealthCheckSuite {
       param([hashtable]$Health, [string]$AdapterName, ...)
       # All health checking logic here
   }
   ```

2. **Create workflow functions:**
   ```powershell
   # Move diagnostic workflows to PPPoE.Workflows.psm1
   function Invoke-BasicDiagnostics { ... }
   function Invoke-NetworkDiagnostics { ... }
   function Invoke-ConnectivityDiagnostics { ... }
   ```

3. **Simplify main script:**
   ```powershell
   # Invoke-PppoeDiagnostics.ps1 becomes orchestration only
   try {
       Start-AsciiTranscript -Path $logPath
       Show-Banner
       
       $Health = New-Health
       $Health = Invoke-BasicDiagnostics -Health $Health -AdapterName $nic.Name
       $Health = Invoke-NetworkDiagnostics -Health $Health -PppoeName $connectionNameToUse
       $Health = Invoke-ConnectivityDiagnostics -Health $Health -PppIP $pppIP
       
       Write-HealthSummary -Health $Health
   } finally {
       # Cleanup
   }
   ```

## Priority 3: Create Missing Modules

### PPPoE.Configuration.psm1 (~100 lines)
**Purpose:** Centralized configuration management
**Functions:**
- `Get-ProjectConfiguration`
- `Set-LoggingConfiguration`
- `Get-DefaultParameters`
- `Validate-Configuration`

### PPPoE.Utilities.psm1 (~150 lines)
**Purpose:** Common utility functions
**Functions:**
- `Format-Duration`
- `ConvertTo-HumanReadable`
- `Test-AdministratorRights`
- `Get-SystemInformation`

## Implementation Timeline

### Phase 1: PPPoE.Net.psm1 Refactoring (Week 1)
- [ ] Create new module files
- [ ] Move adapter-related functions
- [ ] Move PPPoE-related functions
- [ ] Update imports and test

### Phase 2: Main Script Refactoring (Week 2)
- [ ] Extract health check orchestration
- [ ] Create workflow modules
- [ ] Simplify main script
- [ ] Update documentation

### Phase 3: Additional Modules (Week 3)
- [ ] Create configuration module
- [ ] Create utilities module
- [ ] Add comprehensive tests
- [ ] Update README and documentation

## Benefits of Refactoring

### Maintainability
- **Smaller, focused files** are easier to understand
- **Single responsibility** makes debugging simpler
- **Modular design** allows independent testing

### Reusability
- **Specialized modules** can be used independently
- **Clear interfaces** between components
- **Easier to extend** with new functionality

### Testing
- **Unit tests** for individual functions
- **Integration tests** for module interactions
- **Isolated testing** of specific features

### Performance
- **Selective loading** of required modules
- **Parallel development** by multiple developers
- **Easier optimization** of specific components

## Migration Strategy

### Backward Compatibility
- Keep existing function signatures
- Maintain current parameter patterns
- Ensure existing scripts continue to work

### Testing Strategy
1. **Create comprehensive tests** before refactoring
2. **Test each module** in isolation
3. **Integration testing** after each phase
4. **End-to-end testing** of complete workflows

### Documentation Updates
- Update README.md with new structure
- Document new module interfaces
- Create migration guide for users
- Update inline documentation

## Quality Assurance

### Code Review Checklist
- [ ] File sizes are under 300 lines
- [ ] Functions follow DRY principles
- [ ] SOLID principles are applied
- [ ] Error handling is consistent
- [ ] Documentation is complete
- [ ] Tests are written and passing

### Performance Validation
- [ ] Module loading times are acceptable
- [ ] Memory usage is optimized
- [ ] No regression in execution time
- [ ] Error handling doesn't impact performance

## Conclusion

This refactoring will transform the PPPoE Diagnostic Toolkit from a monolithic structure into a well-organized, maintainable, and extensible PowerShell project that follows industry best practices. The modular design will make it easier to:

- **Maintain** individual components
- **Test** functionality in isolation
- **Extend** with new features
- **Debug** issues more effectively
- **Collaborate** on development

The investment in refactoring will pay dividends in reduced maintenance overhead, improved reliability, and enhanced developer productivity.
