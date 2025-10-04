# PPPoE.Net.psm1 - Network operations module (refactored)
# This module now imports and re-exports functions from specialized sub-modules

Set-StrictMode -Version 3.0

# Import all sub-modules
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import sub-modules
Import-Module "$here\PPPoE.Net.Adapters.psm1" -Force
Import-Module "$here\PPPoE.Net.PPPoE.psm1" -Force
Import-Module "$here\PPPoE.Net.Connectivity.psm1" -Force
Import-Module "$here\PPPoE.Net.Diagnostics.psm1" -Force

# Re-export all functions from sub-modules to maintain backward compatibility
Export-ModuleMember -Function *