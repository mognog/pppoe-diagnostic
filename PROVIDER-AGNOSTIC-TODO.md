# Rules
- Keep this roadmap current: tick off items as soon as they’re completed.
- Skim `TIPS.md` before changes for style, patterns, and guardrails.
- Use quick smoke tests to validate edits: run `.\Tests\Run-Tests-Fast.ps1`.
- Prefer minimal/noise logging; privacy defaults to ON unless Evidence is required.
- When unsure, add a short note next to the item explaining the decision.

## PPPoE Diagnostic – Provider-Agnostic Roadmap

Status legend: [ ] pending · [~] in progress · [x] completed · [-] cancelled

### Profiles & Privacy
- [~] Add diagnostic profiles Quick/Standard/ISP Evidence and wire flags
- [x] Implement privacy modes (ON/Evidence) and redaction rules in logging

### Optionalization & Noise Trimming
- [ ] Make ONT web UI probing optional; keep LED prompt only
- [ ] Clarify Wi‑Fi disable log message and keep behavior


### Core Signal & Provider-Agnostic Fixes
- [x] Treat 0.0.0.0 gateway as normal; rely on default route presence
- [x] Bind ICMP/traceroute to PPP IfIndex; skip ICMP tests when ICMP is blocked
- [ ] Fail-fast on RasDial authentication errors with friendly messages
- [x] Use neutral labels for DNS; remove provider names from logs
- [x] Detect CGNAT (100.64.0.0/10) and log as INFO (not error)
- [ ] Simplify ladder and introduce clear stop-conditions per tier

### Health Summary & UX
- [x] Health summary: one concise line per tier (PASS/FAIL/INFO)
- [x] If ICMP and TCP disagree, add INFO note preferring TCP checks
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
- [~] Profile and privacy plumbing added (flags + redaction helpers wired)

---

This file tracks the high-level plan and progress. Feel free to edit items or add notes inline.


