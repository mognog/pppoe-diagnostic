
# PPPoE Diagnostic Toolkit

A comprehensive PowerShell 7+ toolkit to test Windows PPPoE connections end-to-end and produce an **ASCII-only transcript** that's safe to send to ISP support.

## What This Tool Does

This diagnostic tool helps you troubleshoot PPPoE (Point-to-Point Protocol over Ethernet) internet connections on Windows. It performs a complete health check of your PPPoE setup and generates a detailed report that you can share with your ISP's technical support.

### Key Features

- **Complete PPPoE Health Check**: Tests every aspect of your PPPoE connection from physical adapter to internet connectivity
- **Stage-by-stage Health Summary**: Each step shows PASS/FAIL/WARN status with detailed explanations
- **Intelligent Credential Fallback**: Automatically tries Windows saved credentials → credentials.ps1 file → script parameters
- **Smart Link-state Validation**: Skips authentication attempts when Ethernet link is down (saves time and provides clear feedback)
- **Robust Connection Validation**: Ensures authenticated PPP interface exists with proper IP assignment and routing
- **Clear Authentication Feedback**: Shows exactly which credential method succeeded and why others failed
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

The script uses an intelligent **fallback credential system** that tries multiple credential sources in order of preference:

### Automatic Fallback Order

1. **🥇 Windows Saved Credentials** (Most Common)
   - Uses credentials saved in your Windows PPPoE connection
   - **Display**: "SUCCESS: Connected using Windows saved credentials"
   - **Advantages**: No need to type credentials, stored securely by Windows

2. **🥈 External credentials.ps1 File** (Development/Testing)
   - Loads credentials from `credentials.ps1` file in the script directory
   - **Display**: "SUCCESS: Connected using credentials from file"
   - **Advantages**: Not committed to Git, easy to update, can be shared securely

3. **🥉 Script Parameters** (Manual Override)
   - Uses `-UserName` and `-Password` parameters passed to the script
   - **Display**: "SUCCESS: Connected using script parameters"
   - **Use when**: Testing different credentials or saved credentials are incorrect

### How It Works

The script **automatically tries each method in order** and **stops on the first successful connection**:

```
[2025-10-04 12:20:49] Starting PPPoE connection attempts with fallback credential sources...
[2025-10-04 12:20:49] Attempt 1: Trying Windows saved credentials for connection 'Rise PPPoE'
[2025-10-04 12:20:49] SUCCESS: Connected using Windows saved credentials
[2025-10-04 12:20:49] Final connection result: Method=Windows Saved, Success=True, ExitCode=0
```

### Setting Up Credentials

#### Option 1: Windows Saved Credentials (Recommended)
When you create your PPPoE connection in Windows, save your credentials there. The script will use them automatically.

#### Option 2: External credentials.ps1 File
Create a `credentials.ps1` file in the same directory as the script:

```powershell
# Copy credentials.ps1.example to credentials.ps1 and edit it
$PPPoE_Username = 'your_username@isp.com'
$PPPoE_Password = 'your_password_here'
$PPPoE_ConnectionName = 'Rise PPPoE'
```

#### Option 3: Script Parameters
Pass credentials directly to the script:

```powershell
.\Invoke-PppoeDiagnostics.ps1 -PppoeName 'MyISP' -UserName 'user@isp.com' -Password 'mypassword' -FullLog
```

## Why Can't We Extract Saved Credentials?

**Short Answer:** Windows security restrictions prevent it.

**Technical Details:**
- Windows stores PPPoE credentials in encrypted form for security
- Modern Windows versions use Windows Credential Manager with strong encryption
- Microsoft doesn't provide public APIs to extract saved PPPoE credentials
- This is intentional security-by-design to protect user credentials

**What This Means:**
- ✅ The script can **use** saved credentials for connections
- ❌ The script **cannot display** the saved username
- ✅ This is **normal and expected** behavior
- ✅ Your credentials are **secure** and protected

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

### Example: No Physical Connection (Ethernet Link Down)

```
=== HEALTH SUMMARY (ASCII) ===
[1] PowerShell version .................. OK (7.5.3)
[2] PPPoE connections configured ........ OK (1 found: Rise PPPoE)
[3] Physical adapter detected ........... OK (Realtek USB 5GbE Family Controller @ 0 bps)
[4] Ethernet link state ................. FAIL (Down)
[5] Credentials source .................. N/A
[6] PPPoE authentication ................ N/A
[7] PPP interface present ............... N/A
[8] PPP IPv4 assignment ................. N/A
[9] Default route via PPP ............... N/A
[10] Public IP classification ........... N/A
[11] Gateway reachability ............... N/A
[12] Ping (1.1.1.1) via PPP ............ N/A
[13] Ping (8.8.8.8) via PPP ............ N/A
[14] MTU probe (DF) ..................... N/A
OVERALL: FAIL
```

**What this means**: The Ethernet cable is not connected or the network adapter is down. Connect your Ethernet cable and ensure your network adapter is working.

### Example: Failed Connection (Authentication Issue)

```
=== HEALTH SUMMARY (ASCII) ===
[1] PowerShell version .................. OK (7.5.3)
[2] PPPoE connections configured ........ OK (1 found: My ISP PPPoE)
[3] Physical adapter detected ........... OK (Realtek USB 5GbE @ 1 Gbps)
[4] Ethernet link state ................. OK (Up)
[5] Credentials source .................. OK (Using Windows saved credentials)
[6] PPPoE authentication ................ FAIL (691 bad credentials)
[7] PPP interface present ............... N/A
[8] PPP IPv4 assignment ................. N/A
[9] Default route via PPP ............... N/A
[10] Public IP classification ........... N/A
[11] Gateway reachability ............... N/A
[12] Ping (1.1.1.1) via PPP ............ N/A
[13] Ping (8.8.8.8) via PPP ............ N/A
[14] MTU probe (DF) ..................... N/A
OVERALL: FAIL
```

**What this means**: The connection failed at step 6 with error 691, which typically means incorrect username/password. The script tried Windows saved credentials first but they were incorrect.

### Example: Successful Connection

```
=== HEALTH SUMMARY (ASCII) ===
[1] PowerShell version .................. OK (7.5.3)
[2] PPPoE connections configured ........ OK (1 found: My ISP PPPoE)
[3] Physical adapter detected ........... OK (Realtek USB 5GbE @ 1 Gbps)
[4] Ethernet link state ................. OK (Up)
[5] Credentials source .................. OK (Using Windows saved credentials)
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

**What this means**: Everything is working perfectly! The script successfully connected using Windows saved credentials and you have full internet connectivity.

### Status Indicators

- **OK**: Step completed successfully
- **FAIL**: Critical issue that prevents connection
- **WARN**: Non-critical issue that may affect performance
- **N/A**: Step not applicable (usually because previous steps failed)

## Important Notes

### ONT/ISP Session Management
Many ISPs implement **session timeout periods** on their ONT (Optical Network Terminal) or BRAS (Broadband Remote Access Server) equipment. This means:

- **After disconnecting a PPPoE session**, there's typically a 30-60 second wait period before a new session can be established
- **If the first connection attempt fails**, wait 30-60 seconds before trying again
- **This is normal behavior** and not a fault with your connection or the diagnostic tool
- **The tool automatically disconnects** any existing connections at startup to ensure clean testing

**Common Scenario:**
```
[15:46:28] FAILED: Windows saved credentials failed (exit code: 691)
[15:46:29] SUCCESS: Connected using credentials from file
```
This shows the first attempt failed (possibly due to session timeout), but the second attempt succeeded.

### IP Address Classifications
- **Public IP**: Normal internet connection with full connectivity
- **CGNAT (100.64.0.0/10)**: Carrier-grade NAT - works for outbound connections but inbound services/port-forwarding may not work
- **Private RFC1918**: Private network IP - may indicate configuration issues
- **APIPA (169.254.x.x)**: Automatic private IP - usually indicates connection failure

### Credential Management
- The tool uses an intelligent fallback system that tries credentials in this order:
  1. **Windows saved credentials** (most common)
  2. **credentials.ps1 file** (if present and has values)
  3. **Script parameters** (`-UserName` and `-Password`)
- The health summary will show which credential method succeeded:
  - `"OK (Using Windows saved credentials)"` - Connected using saved Windows credentials
  - `"OK (Using credentials from file for: user@isp.com)"` - Connected using credentials.ps1 file
  - `"OK (Using script parameters for: user@isp.com)"` - Connected using parameters
  - `"FAIL (All credential methods failed)"` - All attempts failed
- Common authentication errors:
  - **691**: Bad username or password
  - **692**: Hardware failure in modem or network adapter
  - **623**: Phone book entry not found (connection doesn't exist)
  - **678**: No answer (no PADO response from ISP)

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
