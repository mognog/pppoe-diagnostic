# Rules
- Keep this roadmap current: tick off items as soon as they’re completed.
- Skim `TIPS.md` before changes for style, patterns, and guardrails.
- Use quick smoke tests to validate edits: run `.\Tests\Run-Tests-Fast.ps1`.
- Prefer minimal/noise logging; privacy defaults to ON unless Evidence is required.
- When unsure, add a short note next to the item explaining the decision.

## PPPoE Diagnostic – Provider-Agnostic Roadmap

Status legend: [ ] pending · [~] in progress · [x] completed · [-] cancelled

### Profiles & Privacy
- [x] Add diagnostic profiles Quick/Standard/ISP Evidence and wire flags (workflow gated)
- [x] Implement privacy modes (ON/Evidence) and redaction rules in logging

### Optionalization & Noise Trimming
- [x] Make ONT web UI probing optional; keep LED prompt only (env `PPPOE_SKIP_ONT_WEBUI=1`)
- [x] Clarify Wi‑Fi disable log message and keep behavior (clear, low-noise phrasing)


### Core Signal & Provider-Agnostic Fixes
- [x] Treat 0.0.0.0 gateway as normal; rely on default route presence
- [x] Bind ICMP/traceroute to PPP IfIndex; skip ICMP tests when ICMP is blocked
- [x] Fail-fast on RasDial authentication errors with friendly messages (691)
- [x] Use neutral labels for DNS; remove provider names from logs
- [x] Detect CGNAT (100.64.0.0/10) and log as INFO (not error)
- [x] Simplify ladder and introduce clear stop-conditions per tier (short-circuits on link/auth)

### Health Summary & UX
- [x] Health summary: one concise line per tier (PASS/FAIL/INFO)
- [x] If ICMP and TCP disagree, add INFO note preferring TCP checks
- [x] Ensure always-on logging with safe fields only (privacy ON + redaction)

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
- [x] Profile and privacy plumbing added (flags + redaction helpers wired)

---

This file tracks the high-level plan and progress. Feel free to edit items or add notes inline.


