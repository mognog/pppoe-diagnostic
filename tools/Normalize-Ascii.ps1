
# tools/Normalize-Ascii.ps1 (stub)
param([Parameter(ValueFromPipeline=$true)][string]$InputObject)
process { $InputObject -replace '[^\x00-\x7F]', '?' }
