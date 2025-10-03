
# PPPoE Diagnostic Toolkit (v11a)

A provider‑agnostic PowerShell 7+ toolkit to test Windows PPPoE end‑to‑end and produce an **ASCII‑only transcript** that's safe to send to ISP support.

## Highlights (v11a)

- **✅ FIXED**: Line ending issues that caused CMD file failures
- **✅ FIXED**: PowerShell script parameter parsing issues
- **✅ FIXED**: Health summary logic and null array indexing errors
- **✅ ENHANCED**: PPPoE connection detection (finds existing connections even when disconnected)
- **✅ ENHANCED**: Dual ping tests (1.1.1.1 and 8.8.8.8) for comprehensive connectivity validation
- **Stage‑by‑stage Health Summary** (each step shows PASS/FAIL/WARN).
- **Robust "connected" check**: authenticated PPP interface must exist, have a non‑APIPA IP, and (optionally) be the default route.
- **Link‑state gate**: don't even try PPP if NIC is down/0 bps.
- **Credential clarity**: shows if we used saved vs supplied creds; maps rasdial errors (e.g., 691).
- **Public‑IP class detection**: Public / Private RFC1918 / CGNAT 100.64/10 / APIPA; warns on CGNAT ("works but not ideal for inbound").
- **Provider‑agnostic** (no hardcoded ISP names).
- **Safe restore** of adapters & clean disconnect.
- **ASCII‑only transcript**.

## Structure

```
pppoe-diagnostic-v11a/
├── Invoke-PppoeDiagnostics.ps1       # Main entry script
├── Run-Diagnostics.cmd               # Admin + PowerShell 7 launcher
├── README.md                         # This file
├── TIPS.md                           # Troubleshooting & best practices
├── Modules/
│   ├── PPPoE.Core.psm1               # Transcript, ASCII normaliser, helpers
│   ├── PPPoE.Net.psm1                # NIC/PPP operations
│   ├── PPPoE.Logging.psm1            # Banners, logging helpers
│   └── PPPoE.Health.psm1             # Health checks & summary builder
├── tools/
│   └── Normalize-Ascii.ps1           # Stub ASCII normaliser (pass‑through)
└── logs/
    └── pppoe_transcript_<timestamp>.txt
```

## Quick start

1) Right‑click `Run-Diagnostics.cmd` → **Run as administrator**.  
   (It now works reliably and relaunches in **PowerShell 7+** with elevation if needed.)

**Or** run manually in PowerShell 7:
```powershell
.\Invoke-PppoeDiagnostics.ps1 -PppoeName 'PPPoE' -UserName 'svc_xxx@isp' -Password 'secret' -FullLog
```

**Troubleshooting**: See `TIPS.md` for common issues and solutions.

### Parameters (main script)

- `-PppoeName` (default: `PPPoE`) – Windows dial‑up connection name
- `-UserName` / `-Password` – optional; if not provided we try saved credentials
- `-TargetAdapter` – optional NIC alias; auto‑selects if omitted
- `-FullLog` – include verbose dumps
- `-SkipWifiToggle` – don’t toggle Wi‑Fi
- `-KeepPPP` – don’t disconnect at the end (for post checks)

## Example Health Summary (ASCII)

```
=== HEALTH SUMMARY (ASCII) ===
[1] PowerShell version .................. OK (7.5.3)
[2] PPPoE connections configured ........ OK (1 found: Rise PPPoE)
[3] Physical adapter detected ........... OK (Realtek USB 5GbE @ 1 Gbps)
[4] Ethernet link state ................. OK (Up)
[5] Credentials source .................. WARN (Using saved credentials)
[6] PPPoE authentication ................ FAIL (691 bad credentials)
[7] PPP interface present ............... FAIL (not created)
[8] PPP IPv4 assignment ................. FAIL (no non‑APIPA IPv4)
[9] Default route via PPP ............... FAIL (still via 192.168.55.1)
[10] Public IP classification ........... N/A
[11] Gateway reachability ............... N/A
[12] Ping (1.1.1.1) via PPP ............ N/A
[13] Ping (8.8.8.8) via PPP ............ N/A
[14] MTU probe (DF) ..................... N/A
OVERALL: FAIL
```

On success:

```
=== HEALTH SUMMARY (ASCII) ===
[1] PowerShell version .................. OK (7.5.3)
[2] PPPoE connections configured ........ OK (1 found: Rise PPPoE)
[3] Physical adapter detected ........... OK (Realtek USB 5GbE @ 1 Gbps)
[4] Ethernet link state ................. OK (Up)
[5] Credentials source .................. OK (Supplied at runtime)
[6] PPPoE authentication ................ OK
[7] PPP interface present ............... OK (IfIndex 23, 'PPPoE')
[8] PPP IPv4 assignment ................. OK (86.xxx.xxx.xxx/32)
[9] Default route via PPP ............... OK
[10] Public IP classification ........... OK (Public)
[11] Gateway reachability ............... OK
[12] Ping (1.1.1.1) via PPP ............ OK
[13] Ping (8.8.8.8) via PPP ............ OK
[14] MTU probe (DF) ..................... OK (~1492, payload 1472)
OVERALL: OK
```

## Notes

- **CGNAT (100.64.0.0/10)** is flagged as `WARN` (works, but inbound services/port‑forwarding not viable).
- **Private RFC1918** on PPP is also `WARN/FAIL` depending on context.
- Logs are **ASCII‑normalized** to avoid Unicode issues in plain‑text.
- **PPPoE connection detection**: Automatically finds existing PPPoE connections (e.g., "Rise PPPoE") even when disconnected.
- **Dual ping tests**: Tests connectivity to both 1.1.1.1 (Cloudflare) and 8.8.8.8 (Google DNS) for comprehensive validation.
- **v11a fixes**: Resolved line ending issues, PowerShell script parameter parsing problems, health summary logic, and null array indexing errors.

## Troubleshooting

For detailed troubleshooting information, common issues, and best practices, see **[TIPS.md](TIPS.md)**.

### Quick Fixes
- **CMD file closes immediately**: Usually a line ending issue - see TIPS.md
- **PowerShell parameter errors**: Ensure param() block is at the top of script
- **"was was unexpected at this time"**: Unix line endings in CMD file - convert to Windows format
- **"script file not recognized"**: CMD file running from wrong directory - ensure `cd /d "%~dp0"` is included

### Current Testing Status
- **✅ PPPoE connection detection**: Successfully detects existing connections
- **✅ Physical adapter detection**: Works with various USB Ethernet adapters
- **✅ Link state validation**: Correctly identifies when cable is disconnected
- **✅ Health summary logic**: Proper FAIL/OK status reporting
- **🔄 Full connectivity test**: Ready for testing with ISP connection
