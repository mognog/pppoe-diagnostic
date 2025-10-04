Write-Host "=== Testing PPPoE connection detection ==="

# Try to connect to "Rise PPPoE" to see if it exists
Write-Host "Attempting to connect to 'Rise PPPoE'..."
try {
  $result = & rasdial.exe "Rise PPPoE" 2>&1
  Write-Host "Connection attempt result:"
  $result | ForEach-Object { Write-Host "  $_" }
} catch {
  Write-Host "Error attempting connection: $_"
}

Write-Host ""
Write-Host "=== Checking if connection exists by trying to disconnect ==="
try {
  $result = & rasdial.exe "Rise PPPoE" /disconnect 2>&1
  Write-Host "Disconnect attempt result:"
  $result | ForEach-Object { Write-Host "  $_" }
} catch {
  Write-Host "Error attempting disconnect: $_"
}
