# fix-lu4-disconnect-win

Фикс **disconnect Lu4 на Windows Ethernet** (cold path, E-Net OFF) при том же белом публичном IP.

Проверен на: **Realtek PCIe GbE Family Controller** (RTL8168), **Windows 10** и совместим с **Windows 11**, линк **100 Mbps**, публичный IP **`<PUBLIC_WAN_IP>`**.

## Проблема (кратко)

После выбора сервера в списке Servers и нажатия **OK** игра на **PC Ethernet** устанавливала TCP к миру `:9971` (~2 с Established) и сразу рвала соединение (disconnect).  
При **том же публичном IP** тот же PC по **USB WiFi** и **ноутбук по WiFi** заходили нормально → это **не бан IP** и не «нужен VPN».

**E-Net ON** тоже давал успех, но это **другой egress** (`<ENET_EGRESS_IP>`), не фикс Ethernet.

## Матрица доказательств

| Путь | Публичный IP | E-Net | Результат |
|------|--------------|-------|-----------|
| PC Ethernet cold OFF (**до** фикса) | `<PUBLIC_WAN_IP>` | OFF | **FAIL** — `:9971` ~2 с, disconnect |
| PC USB WiFi | `<PUBLIC_WAN_IP>` | OFF | **SUCCESS** |
| Notebook WiFi | `<PUBLIC_WAN_IP>` | OFF | **SUCCESS** |
| PC E-Net ON | `<ENET_EGRESS_IP>` | ON | SUCCESS (*workaround*, не фикс NIC) |
| PC Ethernet cold OFF (**после** фикса) | `<PUBLIC_WAN_IP>` | OFF | **SUCCESS** (100 Mbps) |

Вывод: ломался **стек Realtek Ethernet (offload / power)**, а не «белый IP провайдера».

## Что сработало (known-good)

На Ethernet Realtek:

1. **Energy-Efficient Ethernet / Green Ethernet** — OFF  
2. **PnPCapabilities = 24** — запрет «разрешить отключение устройства для экономии энергии»  
3. **LSO v2 IPv4/IPv6** — OFF  
4. **RSC IPv4/IPv6** — OFF  
5. **Checksum offload** (TCP/UDP/IP) — REG = 0 / Disable-NetAdapterChecksumOffload  

Дополнительно в рабочем батче: Selective Suspend, Idle Power Down, ASPM = 0.

Почему: при входе в мир Lu4 короткий чувствительный TCP к `:9971`; энергосбережение и HW-offload на Realtek давали drop на Ethernet, тогда как WiFi с тем же IP работал.

Снимок: [`good-ethernet-settings.example.txt`](good-ethernet-settings.example.txt).

## Скрипты (один канон для Win10 + Win11)

| Файл | Назначение |
|------|------------|
| [`Apply-Lu4EthernetNic.ps1`](Apply-Lu4EthernetNic.ps1) | Применить known-good (идемпотентно) |
| [`Test-Lu4EthernetNic.ps1`](Test-Lu4EthernetNic.ps1) | Read-only проверка: exit **0** = OK, **1** = drift |
| [`Lu4EthernetNic.Shared.ps1`](Lu4EthernetNic.Shared.ps1) | Общие цели + хелперы (RU/EN DisplayName + RegistryKeyword) |

Отдельные обёртки Win10/Win11 **не нужны** — один скрипт печатает семейство ОС и работает на обоих.

- Ищет Realtek Ethernet (или `-Name` / `-InterfaceDescription`)
- Показывает **BEFORE** / **AFTER**
- `-WhatIf` — только план
- **WiFi не трогает**, пока не передан `-DisableWifi`

После обновления драйвера Realtek на **любой** ОС — снова **Apply**, затем **Test**.

### Windows 10 — запуск (PowerShell от администратора)

```powershell
cd C:\path\to\fix-lu4-disconnect-win
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1
powershell -ExecutionPolicy Bypass -File .\Test-Lu4EthernetNic.ps1
```

Только план:

```powershell
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -WhatIf
```

### Windows 11 — запуск (тот же канон)

```powershell
cd C:\path\to\fix-lu4-disconnect-win
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1
powershell -ExecutionPolicy Bypass -File .\Test-Lu4EthernetNic.ps1
```

Если ExecutionPolicy блокирует: тот же `-ExecutionPolicy Bypass` в команде выше (не меняет политику машины).  
Явно указать адаптер: `-Name Ethernet`.

## Ручные правки в UI

| Документ | Когда |
|----------|--------|
| [`docs/MANUAL-UI.md`](docs/MANUAL-UI.md) | Индекс + общий чеклист |
| [`docs/MANUAL-UI-Win10.md`](docs/MANUAL-UI-Win10.md) | Пути UI Windows 10 |
| [`docs/MANUAL-UI-Win11.md`](docs/MANUAL-UI-Win11.md) | Пути UI Windows 11 (Advanced network settings и т.п.) |

Кратко (Диспетчер устройств → Realtek PCIe GbE → Свойства) — одинаково на 10 и 11:

**Дополнительно (Advanced)** — выключить (Disabled / Отключено):

| EN (часто в UI) | RU (типичные подписи) |
|-----------------|------------------------|
| Energy-Efficient Ethernet | Энергоэффективный Ethernet |
| Green Ethernet | Зелёный Ethernet / Энергосберегающий Ethernet |
| Large Send Offload v2 (IPv4) | Большой объем отправки … IPv4 / LSO v2 IPv4 |
| Large Send Offload v2 (IPv6) | … IPv6 / LSO v2 IPv6 |
| Recv Segment Coalescing (IPv4/IPv6) | Объединение сегментов приёма / RSC |
| TCP/UDP/IP Checksum Offload | Проверка контрольной суммы … |

**Управление электропитанием (Power Management):**

- Снять галку **«Разрешить отключение этого устройства для экономии энергии»**  
  (EN: *Allow the computer to turn off this device to save power*)  
  → в реестре это соответствует **`PnPCapabilities = 24`**.

## Проверка успеха

1. E-Net / E-Global Network — **OFF** (адаптер Down / отсутствует).  
2. Игра только через **Ethernet** (желательно WiFi Disabled для чистого теста).  
3. Публичный IP — ваш белый WAN (`<PUBLIC_WAN_IP>`), **без** hotspot/VPN.  
4. Lu4: фракция **Black** → **Recommended** → выбрать **Black** в списке **Servers** → **OK** → экран **выбора персонажа**.  
   После выбора Black в Servers следующее действие — **только OK** (не выбирать Black ещё раз).  
5. TCP: соединение к миру **`:9971` Established ≥ 20 с**.

## Чего НЕ делать

- Не считать «решением» смену IP: hotspot / LTE / VPN / второй провайдер.  
- E-Net — **обходной путь**, не замена фикса Ethernet.  
- Не откатывать LSO/RSC/EEE/Green/PnP после успеха «для скорости» — снова сломаете cold OFF.  
- Не резать bitrate стрима «из‑за disconnect» — к проблеме Lu4 TCP это не относится.

## Лицензия / scope

Документация и скрипт для личного стека Lu4 на Windows. Меняйте только Ethernet NIC settings; скрипт не трогает OBS/стрим.  
В репозитории нет реальных WAN/LAN IP, SSID, MAC и имён пользователей — только плейсхолдеры.
