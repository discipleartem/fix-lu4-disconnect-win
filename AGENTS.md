# AGENTS.md — entry for AI agents

Repo: **fix-lu4-disconnect-win** — fix Lu4 cold-login **disconnect on Windows Ethernet** caused by Realtek NIC power-save / offloads (not an ISP/IP ban).

## Goal

Apply known-good Realtek Ethernet NIC settings so Lu4 world TCP `:9971` stays Established ≥ 20s / character select works on Ethernet cold path (E-Net OFF).

## Root cause (canon)

- **Cause:** Realtek Ethernet power-saving and HW offloads (EEE, Green, LSO, RSC, checksum, PnP power, Selective Suspend, Idle Power Down, ASPM) breaking world entry on the wired path.
- **Evidence:** same PC/network worked on **USB WiFi**, failed on **Ethernet** before the NIC fix; after Apply, Ethernet works.
- **Not the diagnosis:** white/static WAN IP, ISP ban, “need VPN/hotspot”.

## Source of truth

| Role | File |
|------|------|
| Human instruction | `README.md` |
| Apply known-good | `Apply-Lu4EthernetNic.ps1` |
| Rollback defaults | `Rollback-Lu4EthernetNic.ps1` |
| Machine-readable Apply targets | `settings.known-good.json` |
| Machine-readable Rollback targets | `settings.rollback-defaults.json` |
| Agent short index | `llms.txt` |
| Ignore noise | `.gitignore` |

Exactly **two** `.ps1` files. Do **not** add `-Test` / `-WhatIf`, Shared/Test scripts, or `docs/` clutter.

## How to run

```powershell
# Apply (Administrator)
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1

# Rollback (Administrator) — may restore disconnect
powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1
```

Win10 and Win11: **same** scripts. After Realtek driver update → re-run Apply.

## Do

- Frame the bug as **Ethernet NIC power/offload**, never as IP ban.
- Verify Lu4: **Black → Recommended → Black in Servers → OK only**.
- Use JSON settings for keyword/value checks without scraping README prose.

## Don't

- Do **not** present white/static WAN IP or ISP as the problem.
- Do **not** suggest hotspot / LTE / VPN / second ISP as “the fix”.
- E-Net ON = **workaround** (different path), **not** the Ethernet NIC fix.
- Do **not** re-enable LSO/RSC/EEE/Green/PnP “for speed” after success (unless user asks Rollback).

## Exit codes

- `0` — apply/rollback done
- `1` — not admin, or adapter missing
