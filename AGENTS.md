# AGENTS.md — entry for AI agents

Repo: **fix-lu4-disconnect-win** — fix Lu4 cold-login **disconnect on Windows Ethernet** caused by Realtek NIC power-save / offloads (not an ISP/IP ban).

## Goal

Apply known-good Realtek Ethernet NIC settings so Lu4 world TCP `:9971` stays Established ≥ 20s / character select works on Ethernet cold path (E-Net OFF).

## Root cause (canon)

- **Cause:** Realtek Ethernet power-saving and HW offloads (EEE, Green, LSO, RSC, checksum, PnP power, Selective Suspend, Idle Power Down, ASPM) breaking world entry on the wired path.
- **Evidence:** same PC/network worked on **USB WiFi**, failed on **Ethernet** before the NIC fix; after Apply, Ethernet works.
- **Not the diagnosis:** white/static WAN IP, ISP ban, Kyivstar IP, “need VPN/hotspot”.

## Source of truth

| Role | File |
|------|------|
| Human instruction | `README.md` only |
| Apply + Test (one script) | `Apply-Lu4EthernetNic.ps1` (`-Test` = read-only check) |
| Machine-readable targets | `settings.known-good.json` (agent aid; same values as script) |
| Ignore noise | `.gitignore` |

Do **not** recreate `docs/`, Shared/Test `.ps1`, example dumps, or LICENSE clutter.

## How to run

```powershell
# Apply (Administrator)
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1

# Test / verify (exit 0 = OK, 1 = drift)
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -Test

# Plan only
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -WhatIf
```

Win10 and Win11: **same** script. After Realtek driver update → re-run Apply, then `-Test`.

## Do

- Frame the bug as **Ethernet NIC power/offload**, never as IP ban.
- Verify Lu4: **Black → Recommended → Black in Servers → OK only**.
- Use `settings.known-good.json` for keyword/value checks without scraping README prose.
- No PII in commits (no real IPs, MAC, SSID, usernames).

## Don't

- Do **not** present white/static WAN IP or ISP as the problem.
- Do **not** suggest hotspot / LTE / VPN / second ISP as “the fix”.
- E-Net ON = **workaround** (different path), **not** the Ethernet NIC fix.
- Do **not** re-enable LSO/RSC/EEE/Green/PnP “for speed” after success.
- Do **not** cut OBS/stream bitrate for this Lu4 TCP issue.

## Exit codes (`Apply-Lu4EthernetNic.ps1`)

- `0` — apply done / test OK
- `1` — not admin (apply), adapter missing, or **drift** on `-Test`
