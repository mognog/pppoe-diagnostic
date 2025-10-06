## PPPoE Diagnostic – Provider-Agnostic Roadmap

Status legend: [ ] pending · [~] in progress · [x] completed · [-] cancelled

### Profiles & Privacy
- [~] Add diagnostic profiles Quick/Standard/ISP Evidence and wire flags
- [ ] Implement privacy modes (ON/Evidence) and redaction rules in logging

### Optionalization & Noise Trimming
- [ ] Make ONT web UI probing optional; keep LED prompt only
- [ ] Clarify Wi‑Fi disable log message and keep behavior
 - [ ] Move deep IPv6/streaming tests to optional ISP Evidence pack

### Core Signal & Provider-Agnostic Fixes
- [ ] Treat 0.0.0.0 gateway as normal; rely on default route presence
- [x] Bind ICMP/traceroute to PPP IfIndex; skip ICMP tests when ICMP is blocked
- [ ] Fail-fast on RasDial authentication errors with friendly messages
- [ ] Use neutral labels for DNS; remove provider names from logs
- [ ] Detect CGNAT (100.64.0.0/10) and log as INFO (not error)
- [ ] Simplify ladder and introduce clear stop-conditions per tier

### Health Summary & UX
- [ ] Health summary: one concise line per tier (PASS/FAIL/INFO)
- [ ] If ICMP and TCP disagree, add INFO note preferring TCP checks
- [ ] Ensure always-on logging with safe fields only (see table below)

### Logging Privacy Policy (target)
Keep only safe fields in logs by default (Privacy: ON):
- Timestamps (ISO), script/PS versions, profile, relative log path
- NIC friendly name (no SSID), MAC truncated/hashed
- PPP IP redacted classification (e.g., CGNAT 100.66.x.x)
- Public DNS IPs and public domains only
- Credentials: source only (file/prompt/saved)
- Traceroute: hop IPs/hostnames allowed
- Adapter driver: version only

Privacy: Evidence mode may expose full PPP IP (optional last-octet mask) and full traceroute; still omits SSID, usernames, ONT IDs, and credential values.

### Recent progress
- [x] Early ICMP detection added; ICMP-based tests skipped when TCP works (provider‑agnostic gating)
- [x] Added Quick Stability Suite with summarized evidence; integrated into workflow without noisy logs
- [x] Hardened Count/Error handling in diagnostics; fixed a Task.Run closure misuse

---

This file tracks the high-level plan and progress. Feel free to edit items or add notes inline.


