# fix-lu4-disconnect-win

Фикс **disconnect Lu4 на Windows** (cold path, E-Net OFF) — **Ethernet (ПК)** и **WiFi (ноутбук)**.

Два скрипта. Win10 = Win11. Корень: **энергосбережение / offload NIC** на пути в игру (кабель или WiFi).

**Руками (без PowerShell):** [MANUAL.md](MANUAL.md) — пошагово Windows 10/11, ПК (Ethernet) и ноутбук (Wi‑Fi).

## Как работает

1. **Apply** сначала **читает** текущие значения → печатает таблицу → сохраняет **снимок**  
   `%LOCALAPPDATA%\fix-lu4-disconnect-win\snapshot-<GUID>.json`  
   (повторный Apply **не** затирает снимок — там значения *до первого фикса*).
2. Потом **точечно** ставит known-good **только** там, где сейчас ≠ цель.
3. **Rollback** возвращает **только** `previousValue` из снимка — чужие настройки NIC не трогает.  
   Без снимка откат **отказывается** (не угадывает «заводские»).

**Auto:** есть Ethernet → Ethernet; иначе WiFi (ноутбук без кабеля).

## Запуск (Admin)

```powershell
# ПК с кабелем или ноут (Auto)
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1

# Ноутбук явно по WiFi
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -Media WiFi

# Откат к значениям до фикса
powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1
powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1 -Media WiFi
```

## Что правим

**Ethernet:** EEE, Green, LSO, RSC, checksum, Selective Suspend, Idle Power Down, ASPM=0, PnPCapabilities=24.

**WiFi (ноут):** Power Saving, Sleep on disconnect, uAPSD, Selective Suspend / Idle Power Down, offloads если есть в INF, PnPCapabilities=24.  
Та же идея — радио/NIC не «засыпает» на входе в мир `:9971`.

## Проверка Lu4

E-Net OFF → Black → Recommended → Black в Servers → **только OK** → персы.
