Write-Host "=== VPN Connections ==="
Get-VpnConnection -ErrorAction SilentlyContinue | ForEach-Object { 
  Write-Host "Name: $($_.Name), Type: $($_.ConnectionType)" 
}

Write-Host ""
Write-Host "=== Network Adapters ==="
Get-NetAdapter | ForEach-Object { 
  Write-Host "Name: $($_.Name), Description: $($_.InterfaceDescription)" 
}

Write-Host ""
Write-Host "=== PPPoE-specific adapters ==="
Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'PPPOE|PPP' } | ForEach-Object { 
  Write-Host "Name: $($_.Name), Description: $($_.InterfaceDescription)" 
}
