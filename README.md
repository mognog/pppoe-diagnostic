
# PPPoE Diagnostic Toolkit

A comprehensive PowerShell 7+ toolkit to test Windows PPPoE connections end-to-end and produce an **ASCII-only transcript** that's safe to send to ISP support.

## What This Tool Does

This diagnostic tool helps you troubleshoot PPPoE (Point-to-Point Protocol over Ethernet) internet connections on Windows. It performs a complete health check of your PPPoE setup and generates a detailed report that you can share with your ISP's technical support.

### Key Features

- **Complete PPPoE Health Check**: Tests every aspect of your PPPoE connection from physical adapter to internet connectivity
- **Stage-by-stage Health Summary**: Each step shows PASS/FAIL/WARN status with detailed explanations
- **Robust Connection Validation**: Ensures authenticated PPP interface exists with proper IP assignment and routing
- **Link-state Validation**: Won't attempt PPP connection if your network adapter is down or has no link
- **Credential Management**: Shows whether saved or supplied credentials were used; maps authentication errors
- **Public IP Detection**: Identifies Public/Private/CGNAT/APIPA IP addresses with appropriate warnings
- **Provider-agnostic**: Works with any ISP - no hardcoded provider names
- **Safe Operation**: Automatically restores network adapters and cleanly disconnects after testing
- **ASCII-only Output**: Generates clean, text-only transcripts safe for sharing with support teams

## Prerequisites

Before using this tool, you need to set up a PPPoE connection on your Windows system:

### 1. Create a PPPoE Connection

1. **Open Network & Internet Settings**:
   - Press `Windows + I` to open Settings
   - Go to **Network & Internet** → **Dial-up**

2. **Add a new connection**:
   - Click **"Add a VPN connection"** or **"Set up a new connection"**
   - Choose **"Connect to the Internet"** → **"Broadband (PPPoE)"**

3. **Configure the connection**:
   - **User name**: Your ISP username (usually in format like `user@domain.com` or `user@isp.com`)
   - **Password**: Your ISP password
   - **Connection name**: Give it a name like "My ISP PPPoE" or "Rise PPPoE"
   - **Allow other people to use this connection**: Check this box if you want other users to access it

4. **Save the connection** - it will appear in your network connections list

### 2. Requirements

- **Windows 10/11** with PowerShell 7+ installed
- **Administrator privileges** (required for network adapter operations)
- **Ethernet connection** to your modem/router
- **PPPoE credentials** from your ISP

## Quick Start

### Option 1: Easy Launch (Recommended)
1. **Right-click** `Run-Diagnostics.cmd` → **"Run as administrator"**
2. The script will automatically launch with PowerShell 7+ and run the diagnostics

### Option 2: Manual PowerShell Launch
Open PowerShell 7+ as Administrator and run:
```powershell
.\Invoke-PppoeDiagnostics.ps1 -PppoeName 'YourPPPoEConnectionName' -FullLog
```

### Option 3: With Credentials (if needed)
If the tool can't find your saved credentials or you want to test with different credentials, provide them manually:
```powershell
.\Invoke-PppoeDiagnostics.ps1 -PppoeName 'YourPPPoEConnectionName' -UserName 'your_username@isp.com' -Password 'your_password' -FullLog
```

### Option 4: Using Saved Credentials Only (Recommended)
If you've already saved your credentials in the Windows PPPoE connection, you can simply run:
```powershell
.\Invoke-PppoeDiagnostics.ps1 -PppoeName 'YourPPPoEConnectionName' -FullLog
```
The script will automatically use the saved credentials from your Windows connection.

## Project Structure

```
pppoe-diagnostic/
├── Invoke-PppoeDiagnostics.ps1       # Main diagnostic script
├── Run-Diagnostics.cmd               # Easy launcher (run as admin)
├── README.md                         # This guide
├── TIPS.md                           # Troubleshooting & best practices
├── Modules/
│   ├── PPPoE.Core.psm1               # Core functionality and helpers
│   ├── PPPoE.Net.psm1                # Network adapter operations
│   ├── PPPoE.Logging.psm1            # Logging and output formatting
│   └── PPPoE.Health.psm1             # Health checks and validation
├── tools/
│   └── Normalize-Ascii.ps1           # Text formatting utilities
└── logs/                             # Diagnostic transcripts (excluded from Git)
    └── pppoe_transcript_<timestamp>.txt
```

## Credential Management

The script offers flexible credential handling to suit different scenarios:

### Method 1: Use Saved Credentials (Recommended)
When you create your PPPoE connection in Windows, you can save your username and password. The script will automatically use these saved credentials:

```powershell
.\Invoke-PppoeDiagnostics.ps1 -PppoeName 'MyISP' -FullLog
```

**Advantages:**
- No need to type credentials each time
- Credentials are stored securely by Windows
- Faster execution

### Method 2: Provide Credentials as Parameters
You can pass credentials directly to the script:

```powershell
.\Invoke-PppoeDiagnostics.ps1 -PppoeName 'MyISP' -UserName 'user@isp.com' -Password 'mypassword' -FullLog
```

**Use this when:**
- Testing with different credentials
- Saved credentials are incorrect
- You want to avoid saving credentials in Windows

### Method 3: Hybrid Approach
The script is smart - if you provide some parameters but not others, it will use what you provide and fall back to saved credentials for the rest.

## Script Parameters

The main diagnostic script accepts several parameters:

- **`-PppoeName`** (default: `PPPoE`) – Name of your Windows PPPoE connection
- **`-UserName`** / **`-Password`** – Optional; if not provided, the script tries to use saved credentials
- **`-TargetAdapter`** – Optional network adapter name; auto-selects if omitted
- **`-FullLog`** – Include verbose diagnostic information in the output
- **`-SkipWifiToggle`** – Skip Wi-Fi adapter toggling (useful if you don't have Wi-Fi)
- **`-KeepPPP`** – Keep the PPP connection active after testing (useful for further troubleshooting)

## Understanding the Results

The tool generates a comprehensive health summary showing the status of each diagnostic step. Here's what to look for:

### Example: Failed Connection (Authentication Issue)

```
=== HEALTH SUMMARY (ASCII) ===
[1] PowerShell version .................. OK (7.5.3)
[2] PPPoE connections configured ........ OK (1 found: My ISP PPPoE)
[3] Physical adapter detected ........... OK (Realtek USB 5GbE @ 1 Gbps)
[4] Ethernet link state ................. OK (Up)
[5] Credentials source .................. WARN (Using saved credentials)
[6] PPPoE authentication ................ FAIL (691 bad credentials)
[7] PPP interface present ............... FAIL (not created)
[8] PPP IPv4 assignment ................. FAIL (no non-APIPA IPv4)
[9] Default route via PPP ............... FAIL (still via 192.168.55.1)
[10] Public IP classification ........... N/A
[11] Gateway reachability ............... N/A
[12] Ping (1.1.1.1) via PPP ............ N/A
[13] Ping (8.8.8.8) via PPP ............ N/A
[14] MTU probe (DF) ..................... N/A
OVERALL: FAIL
```

**What this means**: The connection failed at step 6 with error 691, which typically means incorrect username/password. You'll need to update your credentials.

### Example: Successful Connection

```
=== HEALTH SUMMARY (ASCII) ===
[1] PowerShell version .................. OK (7.5.3)
[2] PPPoE connections configured ........ OK (1 found: My ISP PPPoE)
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

**What this means**: Everything is working perfectly! Your PPPoE connection is established and you have full internet connectivity.

### Status Indicators

- **OK**: Step completed successfully
- **FAIL**: Critical issue that prevents connection
- **WARN**: Non-critical issue that may affect performance
- **N/A**: Step not applicable (usually because previous steps failed)

## Important Notes

### IP Address Classifications
- **Public IP**: Normal internet connection with full connectivity
- **CGNAT (100.64.0.0/10)**: Carrier-grade NAT - works for outbound connections but inbound services/port-forwarding may not work
- **Private RFC1918**: Private network IP - may indicate configuration issues
- **APIPA (169.254.x.x)**: Automatic private IP - usually indicates connection failure

### Credential Management
- The tool first tries to use saved credentials from your Windows PPPoE connection
- If saved credentials fail or don't exist, you can provide them manually using the `-UserName` and `-Password` parameters
- Common authentication errors:
  - **691**: Bad username or password
  - **692**: Hardware failure in modem or network adapter
  - **718**: Authentication timeout

### Output Files
- Diagnostic transcripts are saved in the `logs/` folder with timestamps
- All output is ASCII-normalized to avoid Unicode issues when sharing with support teams
- The tool automatically cleans up network connections after testing

## Troubleshooting

For detailed troubleshooting information, common issues, and best practices, see **[TIPS.md](TIPS.md)**.

### Common Issues and Quick Fixes

**"Script file not recognized" or CMD file closes immediately**:
- Make sure you're running as Administrator
- Ensure the script files are in the same directory
- Check that PowerShell 7+ is installed

**"PowerShell parameter errors"**:
- Ensure you're using PowerShell 7+ (not Windows PowerShell 5.1)
- Check that parameter names match exactly (case-sensitive)

**"691 bad credentials" error**:
- Verify your ISP username and password are correct
- Try updating your saved credentials in Windows Network settings
- Test with credentials provided directly: `.\Invoke-PppoeDiagnostics.ps1 -PppoeName 'YourConnection' -UserName 'user@isp.com' -Password 'password' -FullLog`
- Contact your ISP to confirm your account is active

**"No PPPoE connections found"**:
- Make sure you've created a PPPoE connection in Windows Network settings
- Check that the connection name matches what you're specifying with `-PppoeName`

**"Physical adapter not detected"**:
- Ensure your Ethernet cable is connected
- Check that your network adapter is enabled in Device Manager
- Try a different Ethernet cable or port

## Getting Help

If you're still having issues:
1. Check the detailed logs in the `logs/` folder
2. Review the troubleshooting guide in `TIPS.md`
3. Share the diagnostic transcript with your ISP's technical support
4. Open an issue on this GitHub repository with your diagnostic output
