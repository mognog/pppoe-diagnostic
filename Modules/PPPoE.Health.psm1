
# PPPoE.Health.psm1 - Health checks and summary

Set-StrictMode -Version Latest

function New-Health {
  return [ordered]@{}
}

function Add-Health {
  param($Health, [string]$Key, [string]$Value, [int]$Order = 0)
  # Store the order as a prefix in the key for sorting
  $orderedKey = "{0:D2}_{1}" -f $Order, $Key
  $Health[$orderedKey] = $Value
  return $Health
}

function Write-HealthSummary {
  param([hashtable]$Health)
  Write-Log "=== HEALTH SUMMARY (ASCII) ==="
  
  # Sort by the prefixed key (which includes order)
  $sortedKeys = $Health.Keys | Sort-Object
  
  $i = 1
  foreach ($key in $sortedKeys) {
    # Remove the order prefix from the display
    $displayKey = $key -replace '^\d{2}_', ''
    $value = $Health[$key]
    $dots = '.' * [Math]::Max(1, 28 - $displayKey.Length)
    Write-Log ("[{0}] {1} {2} {3}" -f $i, $displayKey, $dots, $value)
    $i++
  }
  
  $hasFail = ($Health.Values | Where-Object { $_ -match 'FAIL' })
  $hasWarn = ($Health.Values | Where-Object { $_ -match 'WARN' })
  $overall = if ($hasFail) { 'FAIL' } elseif ($hasWarn) { 'WARN' } else { 'OK' }
  Write-Log ("OVERALL: {0}" -f $overall)
}

Export-ModuleMember -Function *

