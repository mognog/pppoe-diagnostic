Write-Host "=== Checking RAS connections ==="

# Try to get RAS connections using rasphone.exe output
try {
  $rasOutput = & rasphone.exe -l 2>&1
  Write-Host "RAS output:"
  $rasOutput | ForEach-Object { Write-Host "  $_" }
} catch {
  Write-Host "Error running rasphone.exe: $_"
}

Write-Host ""
Write-Host "=== Checking for PPPoE in registry ==="
# Check if there are any PPPoE connections in the registry
try {
  $pppoeConnections = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\RAS PhoneBook" -ErrorAction SilentlyContinue
  if ($pppoeConnections) {
    Write-Host "Found RAS phone book entries:"
    $pppoeConnections | ForEach-Object { Write-Host "  $($_.Name)" }
  } else {
    Write-Host "No RAS phone book entries found"
  }
} catch {
  Write-Host "Error checking registry: $_"
}

Write-Host ""
Write-Host "=== Checking rasdial output ==="
try {
  $rasdialOutput = & rasdial.exe 2>&1
  Write-Host "rasdial output:"
  $rasdialOutput | ForEach-Object { Write-Host "  $_" }
} catch {
  Write-Host "Error running rasdial.exe: $_"
}
