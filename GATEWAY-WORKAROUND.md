# PPPoE 0.0.0.0 Gateway Workaround

## The Problem
Your PPPoE connection authenticates and gets an IP address, but the gateway shows as `0.0.0.0`.
This is an **IPCP (IP Control Protocol) negotiation failure**.

## Quick Fix Attempts (In Order)

### **Fix #1: Restart RAS Service** (30 seconds)
```powershell
# Run PowerShell as Administrator
Restart-Service RasMan -Force
Start-Sleep -Seconds 5

# Reconnect your PPPoE
rasdial "Rise PPPoE" username password

# Check if gateway is now correct
Get-NetIPConfiguration -InterfaceAlias "Rise PPPoE" | Select-Object IPv4Address, IPv4DefaultGateway
```

**Success if:** Gateway shows real IP (not 0.0.0.0)

---

### **Fix #2: Manual Route Add** (Temporary workaround)
```powershell
# Run PowerShell as Administrator

# Find your PPPoE interface index
$pppInterface = Get-NetAdapter -Name "Rise PPPoE"
$ifIndex = $pppInterface.ifIndex

# Add manual default route (using your actual gateway from traceroute)
# Replace 100.66.0.3 with YOUR gateway from traceroute
New-NetRoute -DestinationPrefix "0.0.0.0/0" -InterfaceIndex $ifIndex -NextHop "100.66.0.3" -RouteMetric 1

# Test browsing now
Test-NetConnection google.com
```

**This is temporary** - Route disappears when you disconnect/reconnect!

---

### **Fix #3: PowerShell Script Auto-Fix** (Permanent-ish)
Create this script and run it AFTER each PPPoE connection:

```powershell
# Save as: Fix-PPPoEGateway.ps1
param([string]$PPPoEName = "Rise PPPoE")

# Wait for interface to stabilize
Start-Sleep -Seconds 3

# Get interface
$interface = Get-NetAdapter -Name $PPPoEName -ErrorAction SilentlyContinue
if (-not $interface) {
    Write-Host "ERROR: Interface $PPPoEName not found"
    exit 1
}

# Check current gateway
$currentGW = Get-NetIPConfiguration -InterfaceIndex $interface.ifIndex | 
             Select-Object -ExpandProperty IPv4DefaultGateway -ErrorAction SilentlyContinue

if ($currentGW -and $currentGW.NextHop -ne "0.0.0.0") {
    Write-Host "Gateway OK: $($currentGW.NextHop)"
    exit 0
}

Write-Host "Gateway is 0.0.0.0, running traceroute to detect real gateway..."

# Run traceroute to find actual gateway
$tracert = Test-NetConnection -ComputerName 8.8.8.8 -TraceRoute -WarningAction SilentlyContinue
$firstHop = $tracert.TraceRoute | Select-Object -First 1

if ($firstHop) {
    Write-Host "Detected gateway: $firstHop"
    Write-Host "Adding manual route..."
    
    # Remove any existing default routes on this interface
    Get-NetRoute -InterfaceIndex $interface.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
    
    # Add correct default route
    New-NetRoute -DestinationPrefix "0.0.0.0/0" -InterfaceIndex $interface.ifIndex -NextHop $firstHop -RouteMetric 1
    
    Write-Host "SUCCESS: Gateway fixed to $firstHop"
    Write-Host "Test browsing now!"
} else {
    Write-Host "ERROR: Could not detect gateway via traceroute"
    exit 1
}
```

**Usage:**
```cmd
# After connecting PPPoE:
pwsh -ExecutionPolicy Bypass -File Fix-PPPoEGateway.ps1 -PPPoEName "Rise PPPoE"
```

---

### **Fix #4: Registry Tweak** (Advanced)
Force Windows to accept gateway from IPCP:

```powershell
# Run PowerShell as Administrator

# Backup first!
reg export "HKLM\SYSTEM\CurrentControlSet\Services\RasMan" "C:\Temp\RasMan_Backup.reg"

# Enable verbose PPP logging
reg add "HKLM\SYSTEM\CurrentControlSet\Services\RasMan\PPP" /v Logging /t REG_DWORD /d 1 /f

# Force IPCP to wait for gateway
reg add "HKLM\SYSTEM\CurrentControlSet\Services\RasMan\PPP\IPCP" /v AcceptVJCompression /t REG_DWORD /d 0 /f

# Restart RAS service
Restart-Service RasMan -Force

# Reconnect and test
```

**Check logs after:** `C:\Windows\System32\LogFiles\` (look for PPP logs)

---

### **Fix #5: Use Third-Party PPPoE Client** (Alternative)
If Windows RAS keeps failing:

1. **RASPPPoE** (free, older but works)
   - Download: Search for "RASPPPoE Windows"
   - Better IPCP handling than Windows built-in

2. **Use a Router in Bridge Mode**
   - Connect router between ONT and PC
   - Router does PPPoE (works correctly)
   - PC connects to router via normal DHCP
   - **This usually works** because router PPPoE clients are more robust

---

## Diagnostic Commands

### Check Current Gateway:
```powershell
Get-NetIPConfiguration -InterfaceAlias "Rise PPPoE" | Format-List
```

### Check Routing Table:
```powershell
Get-NetRoute -InterfaceAlias "Rise PPPoE" | Format-Table
```

### Check What Traceroute Shows:
```powershell
Test-NetConnection 8.8.8.8 -TraceRoute | Select-Object -ExpandProperty TraceRoute | Select-Object -First 3
```

### View PPP Event Logs:
```powershell
Get-EventLog -LogName System -Source "RasMan" -Newest 20 | Format-List
```

---

## Contact ISP With This

**Subject:** "PPPoE IPCP Not Providing Default Gateway"

**Message:**
```
My PPPoE connection to your service authenticates successfully and I receive
an IP address (100.66.x.x/32), but the IPCP negotiation is not providing a
default gateway address.

Windows reports gateway as 0.0.0.0, which prevents normal internet access.
Traceroute shows the actual gateway is 100.66.0.3, but this is not being
communicated during PPPoE session establishment.

Direct TCP connections work (e.g., to 1.1.1.1:443), DNS resolution succeeds,
but traffic requiring proper routing (web browsing, streaming) fails.

This appears to be a PPPoE server/BNG configuration issue where IPCP
completes successfully but the gateway option is not being sent or is being
sent incorrectly.

Can you please check:
1. PPPoE server IPCP configuration
2. BNG (Broadband Network Gateway) settings for my circuit
3. Whether gateway address should be negotiated or is static

Technical details:
- Connection: PPPoE
- Auth: Successful
- IP: Assigned correctly (100.66.x.x/32)
- Gateway: Shows as 0.0.0.0 (should be 100.66.0.3 based on traceroute)
- DNS: Works (1.1.1.1, 8.8.8.8 reachable)
- Symptom: Browsing fails despite connection success
```

---

## Why This Happens

**Common Causes:**

1. **ISP PPPoE Server Misconfiguration**
   - IPCP doesn't send gateway option
   - BNG software bug
   - Recent ISP configuration change

2. **Windows RAS Bug**
   - Windows parsing IPCP incorrectly
   - Happens on some Windows builds
   - Fixed by updates usually

3. **MTU Issues**
   - IPCP packets fragmented
   - Gateway option in fragment gets dropped

4. **Point-to-Point /32 Subnet Confusion**
   - /32 subnet means "no other hosts"
   - Some implementations don't set gateway for /32
   - But Windows requires it for routing

---

## Test If Workaround Works

After applying any fix:

```powershell
# 1. Check gateway is NOT 0.0.0.0
Get-NetIPConfiguration -InterfaceAlias "Rise PPPoE"

# 2. Try browsing
Test-NetConnection google.com -Port 443

# 3. Try actual browser
Start-Process "https://google.com"
```

---

## Automated Fix Script Location

The main diagnostic tool will soon have an automated fix option.

For now, use **Fix #2** (manual route) or **Fix #3** (PowerShell script) above.

---

## Last Resort: Use Router

If nothing works, the ISP PPPoE server is fundamentally broken.

**Workaround:** Use ANY router in PPPoE mode:
- Router connects via PPPoE (it has better IPCP handling)
- PC connects to router via normal DHCP
- This almost always works because router PPPoE stacks are more tolerant

Cheap option: TP-Link Archer C6 (~£30) or any basic router with PPPoE support.

---

*This is a known issue with certain ISP PPPoE implementations. It's not your equipment's fault.*
