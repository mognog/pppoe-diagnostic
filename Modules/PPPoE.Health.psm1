
# PPPoE.Health.psm1 - Health checks and summary

Set-StrictMode -Version Latest

function New-Health {
  @()
}

function Add-Health {
  param($Health, [string]$Key, [string]$Value, [int]$Order = 0)
  $healthItem = [PSCustomObject]@{
    Order = $Order
    Key = $Key
    Value = $Value
  }
  $Health = $Health + $healthItem
  return $Health
}

function Write-HealthSummary {
  param([array]$Health)
  Write-Log "=== HEALTH SUMMARY (ASCII) ==="
  
  # Sort by order, then by key for consistent display
  $sortedHealth = $Health | Sort-Object Order, Key
  
  $i = 1
  foreach ($item in $sortedHealth) {
    $dots = '.' * [Math]::Max(1, 28 - $item.Key.Length)
    Write-Log ("[{0}] {1} {2} {3}" -f $i, $item.Key, $dots, $item.Value)
    $i++
  }
  
  $hasFail = ($Health | Where-Object { $_.Value -match 'FAIL' })
  $hasWarn = ($Health | Where-Object { $_.Value -match 'WARN' })
  $overall = if ($hasFail) { 'FAIL' } elseif ($hasWarn) { 'WARN' } else { 'OK' }
  Write-Log ("OVERALL: {0}" -f $overall)
}

Export-ModuleMember -Function *
