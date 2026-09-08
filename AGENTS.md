# AGENTS.md — entry for AI agents

**fix-lu4-disconnect-win** — Lu4 cold disconnect on Windows NIC power-save/offload (Ethernet desktop **or** WiFi notebook).

## Canon

- Cause: NIC energy-saving / HW offload on the path used for Lu4 (wired **or** wireless).
- Not: ISP / “white IP” ban.
- Exactly **2** scripts: `Apply-Lu4EthernetNic.ps1`, `Rollback-Lu4EthernetNic.ps1`.
- `-Media Auto|Ethernet|WiFi` (default Auto: Ethernet if present, else WiFi).

## Surgical snapshot

1. Apply **reads** current props → saves `%LOCALAPPDATA%\fix-lu4-disconnect-win\snapshot-<AdapterGuid>.json` once (never overwrite existing).
2. Apply **sets only** values ≠ known-good target.
3. Rollback **restores only** snapshot `previousValue`s. No snapshot → exit 1 (no blind factory wipe).

## Run

```powershell
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -Media WiFi
powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1
```

## Verify Lu4

Black → Recommended → Black in Servers → **OK only** → character select; `:9971` ≥ 20s.

## Files

README.md · **MANUAL.md** (GUI steps Win10/11 + PC Ethernet / notebook WiFi) · Apply / Rollback ps1 · settings.known-good.json · settings.rollback-defaults.json · llms.txt
