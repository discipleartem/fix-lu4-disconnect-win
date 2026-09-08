# fix-lu4-disconnect-win

Фикс **disconnect Lu4 на Windows Ethernet** (cold path, E-Net OFF).

Два скрипта + эта инструкция. Один канон для **Windows 10** и **Windows 11**.

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
powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1
```

| Команда | Что делает |
|---------|------------|
| `.\Apply-Lu4EthernetNic.ps1` | Применить known-good (идемпотентно) |
| `.\Rollback-Lu4EthernetNic.ps1` | Вернуть типичные defaults (может вернуть disconnect) |
| `-Name Ethernet` | Явно указать адаптер |
| `-DisableWifi` | Только у Apply: опционально выключить WiFi (**не** часть фикса) |

После обновления драйвера Realtek — снова Apply.

Машинные цели: [`settings.known-good.json`](settings.known-good.json), [`settings.rollback-defaults.json`](settings.rollback-defaults.json). Агенты: [`AGENTS.md`](AGENTS.md), [`llms.txt`](llms.txt).

## Что выключаем (known-good / Apply)

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
Режимы экономии на линке Ethernet. NIC может «подремать» в паузе login→world. Для браузера незаметно; для короткого TCP `:9971` — обрыв ~2 с. USB WiFi на том же PC работал — типичный след power-save на Realtek Ethernet.

**PnPCapabilities = 24**  
Галка *«Разрешить отключение этого устройства для экономии энергии»*. Значение **24** запрещает Windows гасить адаптер. Скрипт также ставит `AllowComputerToTurnOffDevice=Disabled`.

**LSO v2 (IPv4/IPv6)**  
Large Send Offload: чип сам нарезает TCP. На части Realtek HW-сегментация ломает игровой TCP.

**RSC (IPv4/IPv6)**  
Receive Segment Coalescing: склейка RX меняет тайминг; короткий world-handshake Lu4 чувствителен.

**Checksum offload (TCP/UDP/IP)**  
Контрольные суммы считает NIC. В рабочем батче выключен весь набор.

**Selective Suspend / Idle Power Down**  
Сон NIC между пакетами / когда драйвер считает устройство «ненужным» — риск сброса в момент `:9971`.

**ASPM = 0**  
Active State Power Management на PCIe — выкл., чтобы не ловить wake/latency на handshake.

**Не откатывать** эти OFF «для скорости» после успеха — cold OFF снова сломается. Rollback — только если сознательно откатываете фикс.

## Rollback (типичные defaults)

`Rollback-Lu4EthernetNic.ps1` включает обратно: EEE/Green, LSO, RSC, checksum (Rx&Tx=`3`), Selective Suspend, Idle Power Down, ASPM=`1`, PnPCapabilities=`0`, `AllowComputerToTurnOffDevice=Enabled`.

## Ручной UI (если без скрипта)

**Диспетчер устройств** → **Realtek PCIe GbE** → **Свойства**.

**Дополнительно (Advanced)** — Disabled: EEE, Green Ethernet, LSO v2, RSC, Checksum Offload, Selective Suspend, Idle Power Down.

**Управление электропитанием:** снять *«Разрешить отключение…»* → `PnPCapabilities = 24`.

## Проверка успеха в Lu4

1. E-Net / E-Global Network — **OFF**.  
2. Игра через **Ethernet**.  
3. Фракция **Black** → **Recommended** → выбрать **Black** в **Servers** → **только OK** → экран **выбора персонажа**.  
4. TCP к миру **`:9971` Established ≥ 20 с**.

## Do / Don't

**Do**

- Применять `Apply-Lu4EthernetNic.ps1`.  
- После обновления драйвера Realtek — снова Apply.  
- Проверять вход: Black → Recommended → Black in Servers → OK only.

**Don't**

- Не предлагать hotspot / LTE / VPN / смену сети как «фикс» — корень в NIC, не в IP.  
- E-Net — только workaround, не замена фикса Ethernet.  
- Не включать обратно LSO/RSC/EEE/Green/PnP «для скорости» после успеха.

## Файлы репо

| Файл | Назначение |
|------|------------|
| [`Apply-Lu4EthernetNic.ps1`](Apply-Lu4EthernetNic.ps1) | Применить known-good |
| [`Rollback-Lu4EthernetNic.ps1`](Rollback-Lu4EthernetNic.ps1) | Откат к типичным defaults |
| [`README.md`](README.md) | Инструкция для людей |
| [`AGENTS.md`](AGENTS.md) | Канон для ИИ-агентов |
| [`llms.txt`](llms.txt) | Краткая выжимка для агентов |
| [`settings.known-good.json`](settings.known-good.json) | Цели Apply |
| [`settings.rollback-defaults.json`](settings.rollback-defaults.json) | Цели Rollback |
