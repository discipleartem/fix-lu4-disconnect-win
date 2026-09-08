# fix-lu4-disconnect-win

Фикс **disconnect Lu4 на Windows Ethernet** (cold path, E-Net OFF).

**Один скрипт + эта инструкция.** Один канон для **Windows 10** и **Windows 11**.

Проверен на: **Realtek PCIe GbE Family Controller** (RTL8168), линк **100 Mbps**.

## Проблема

После выбора сервера в **Servers** и нажатия **OK** игра на **PC Ethernet** устанавливала TCP к миру `:9971` (~2 с Established) и сразу рвала соединение (disconnect).

**Корень:** энергосбережение и HW-offload на **Realtek Ethernet** (EEE, Green, LSO, RSC, checksum, PnP power, Selective Suspend, Idle Power Down, ASPM) — не провайдер и не «бан по IP».

**Доказательство:** на той же машине / той же сети **USB WiFi** заходил нормально, а **Ethernet** падал; после Apply known-good настроек NIC **Ethernet** тоже заходит.

E-Net ON — отдельный обходной путь (другой сетевой путь), **не** этот фикс Ethernet.

| Путь | Результат |
|------|-----------|
| PC Ethernet (**до** фикса NIC) | **FAIL** — `:9971` ~2 с, disconnect |
| PC USB WiFi (тот же PC / сеть) | **SUCCESS** |
| PC Ethernet (**после** Apply) | **SUCCESS** |
| E-Net ON | SUCCESS (*workaround*, не фикс NIC) |

## Запуск (Win10 = Win11)

PowerShell **от администратора**:

```powershell
cd C:\path\to\fix-lu4-disconnect-win
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -Test
```

| Команда | Что делает |
|---------|------------|
| `.\Apply-Lu4EthernetNic.ps1` | Применить known-good (идемпотентно) |
| `.\Apply-Lu4EthernetNic.ps1 -Test` | Только проверка (alias `-Check`): exit **0** = OK, **1** = drift |
| `.\Apply-Lu4EthernetNic.ps1 -WhatIf` | План без записи |
| `-Name Ethernet` | Явно указать адаптер |
| `-DisableWifi` | Опционально выключить WiFi (для чистого Ethernet-теста; **не** часть фикса) |

После обновления драйвера Realtek — снова Apply, затем `-Test`.

Машинные цели для агентов: [`settings.known-good.json`](settings.known-good.json). Точка входа агента: [`AGENTS.md`](AGENTS.md).

## Что выключаем (known-good)

| Настройка | Цель |
|-----------|------|
| Energy-Efficient Ethernet / Green Ethernet (+ EEE Link Advertisement) | OFF (`0`) |
| PnPCapabilities | **24** (галка «разрешить отключение…» снята) |
| LSO v2 IPv4 / IPv6 | OFF + `Disable-NetAdapterLso` |
| RSC IPv4 / IPv6 | OFF + `Disable-NetAdapterRsc` |
| TCP/UDP/IP Checksum Offload | OFF + `Disable-NetAdapterChecksumOffload` |
| Selective Suspend, Idle Power Down | OFF (`0`) |
| ASPM | **0** |

### Что это / зачем OFF (по-русски)

**Energy-Efficient Ethernet (EEE) / Green Ethernet**  
Режимы экономии на линке Ethernet (в UI: *Энергоэффективный / Зелёный / Энергосберегающий Ethernet*). NIC может «подремать» или переключить линк в паузе login→world. Для браузера незаметно; для короткого TCP `:9971` — обрыв ~2 с после Established. USB WiFi на том же PC работал — типичный след power-save на Realtek Ethernet.

**PnPCapabilities = 24**  
Галка *«Разрешить отключение этого устройства для экономии энергии»* (Power Management). Значение **24** запрещает Windows гасить адаптер. Иначе Ethernet «простаивает» между login и world → drop `:9971`. Скрипт также ставит `AllowComputerToTurnOffDevice=Disabled`.

**LSO v2 (IPv4/IPv6)**  
Large Send Offload: чип сам нарезает большие TCP-куски. На части Realtek HW-сегментация портит/задерживает игровой TCP — частый кандидат на «Ethernet падает, WiFi нет».

**RSC (IPv4/IPv6)**  
Receive Segment Coalescing: склейка входящих сегментов. Меняет тайминг RX; короткий world-handshake Lu4 чувствителен → снова disconnect на Ethernet.

**Checksum offload (TCP/UDP/IP)**  
Контрольные суммы считает NIC. На некоторых драйверах Realtek — редкие, но жёсткие сбои. В рабочем батче выключен весь набор (не «ради скорости»).

**Selective Suspend**  
Сон устройства, когда драйвер считает NIC «не нужным». В паузе login→world — риск сброса линка в момент `:9971`.

**Idle Power Down**  
Низкое потребление между пакетами. Вход в мир — неровный короткий поток; idle-down даёт промах по таймингу.

**ASPM = 0**  
Active State Power Management на PCIe-шине адаптера. Выкл., чтобы не ловить latency/wake в момент handshake.

**Не откатывать** эти OFF «для скорости» после успеха — cold OFF снова сломается.

## Ручной UI (если без скрипта)

Одинаково на Win10 и Win11: **Диспетчер устройств** → **Realtek PCIe GbE** → **Свойства**.

**Дополнительно (Advanced)** — Disabled / Отключено: EEE, Green Ethernet, LSO v2 IPv4/IPv6, RSC IPv4/IPv6, Checksum Offload, Selective Suspend, Idle Power Down (если есть).

**Управление электропитанием:** снять *«Разрешить отключение этого устройства для экономии энергии»* → `PnPCapabilities = 24`.

## Проверка успеха в Lu4

1. E-Net / E-Global Network — **OFF**.  
2. Игра через **Ethernet**.  
3. Фракция **Black** → **Recommended** → выбрать **Black** в **Servers** → **только OK** (не выбирать Black ещё раз) → экран **выбора персонажа**.  
4. TCP к миру **`:9971` Established ≥ 20 с**.

## Do / Don't

**Do**

- Применять `Apply-Lu4EthernetNic.ps1`, затем `-Test`.  
- После обновления драйвера Realtek — снова Apply + `-Test`.  
- Проверять вход: Black → Recommended → Black in Servers → OK only.

**Don't**

- Не предлагать hotspot / LTE / VPN / смену сети как «фикс» — корень в NIC, не в «IP».  
- E-Net — только workaround, не замена фикса Ethernet.  
- Не включать обратно LSO/RSC/EEE/Green/PnP «для скорости».  
- Не резать bitrate стрима «из‑за disconnect» — к Lu4 TCP на Ethernet это не относится.

## Файлы репо

| Файл | Назначение |
|------|------------|
| [`Apply-Lu4EthernetNic.ps1`](Apply-Lu4EthernetNic.ps1) | Apply + `-Test` (единственный пользовательский скрипт) |
| [`README.md`](README.md) | Эта инструкция (единственная для людей) |
| [`AGENTS.md`](AGENTS.md) | Канон для ИИ-агентов |
| [`settings.known-good.json`](settings.known-good.json) | Машинные цели NIC (для агентов) |
| [`.gitignore`](.gitignore) | Локальный шум |

Без PII: не коммитить реальные IP, SSID, MAC, имена пользователей. Скрипт не трогает OBS/стрим.
