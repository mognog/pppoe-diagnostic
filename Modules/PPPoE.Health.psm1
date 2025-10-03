
# PPPoE.Health.psm1 - Health checks and summary

Set-StrictMode -Version Latest

function New-Health {
  [ordered]@{}
}

function Add-Health {
  param($Health, [string]$Key, [string]$Value)
  $Health[$Key] = $Value
}

function Write-HealthSummary {
  param([hashtable]$Health)
  Write-Log "=== HEALTH SUMMARY (ASCII) ==="
  $i=1
  foreach ($k in $Health.Keys) {
    $v = $Health[$k]
    $dots = '.' * [Math]::Max(1, 28 - $k.Length)
    Write-Log ("[{0}] {1} {2} {3}" -f $i, $k, $dots, $v)
    $i++
  }
  $hasFail = ($Health.Values | Where-Object { $_ -match 'FAIL' })
  $hasWarn = ($Health.Values | Where-Object { $_ -match 'WARN' })
  $overall = if ($hasFail) { 'FAIL' } elseif ($hasWarn) { 'WARN' } else { 'OK' }
  Write-Log ("OVERALL: {0}" -f $overall)
}

Export-ModuleMember -Function *
