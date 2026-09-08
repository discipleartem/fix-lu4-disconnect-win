# Что это за настройки и зачем их выключаем

Кратко по-русски: зачем known-good профиль Realtek Ethernet выключает энергосбережение и HW-offload.

**Контекст Lu4.** После выбора сервера и **OK** игра открывает короткий TCP к миру **`:9971`**. На PC Ethernet соединение часто жило ~2 с и рвалось (disconnect). С **тем же публичным IP** тот же PC по USB WiFi и ноутбук по WiFi заходили нормально → это не «бан IP», а стек **Realtek Ethernet** (power save / offload). E-Net ON — другой egress, обходной путь, не этот фикс.

Цель: cold OFF на Ethernet, белый WAN без hotspot/VPN, `:9971` Established ≥ 20 с / экран выбора персонажа.

Снимок значений: [`../good-ethernet-settings.example.txt`](../good-ethernet-settings.example.txt).  
Применить: `Apply-Lu4EthernetNic.ps1`. Проверить: `Test-Lu4EthernetNic.ps1`.

---

## 1. Energy-Efficient Ethernet (EEE) / Green Ethernet — OFF

**Что это.** Режимы экономии питания на самом линке Ethernet. EEE снижает потребление, когда «мало трафика»; Green Ethernet — родственная фича Realtek (в т.ч. под длину кабеля / «зелёный» режим). В UI часто: *Energy-Efficient Ethernet*, *Green Ethernet*, *Энергоэффективный Ethernet*, *Зелёный / Энергосберегающий Ethernet*.

**Зачем выключаем.** Между логином и входом в мир NIC может «подремать» или переключить состояние линка. Для обычного браузера это незаметно; для короткого чувствительного TCP `:9971` — обрыв сразу после Established. WiFi с тем же IP работал, Ethernet — нет: типичный след power-save на Realtek, не маршрута провайдера.

**Цель:** `*EEE=0`, `*GreenEthernet=0` (и связанные ключи вроде EEE Link Advertisement).

---

## 2. PnPCapabilities = 24 — запрет «разрешить отключение устройства…»

**Что это.** Флаг в реестре NIC + галка в **Управление электропитанием**:  
*«Разрешить отключение этого устройства для экономии энергии»*  
(EN: *Allow the computer to turn off this device to save power*).

Значение **24** (0x18) — канон known-good: компьютер **не** имеет права гасить адаптер ради экономии (и связанные биты wake в этом профиле).

**Зачем выключаем (снимаем галку).** Windows может считать Ethernet «простаивающим» в паузе login → world и отключить устройство. Тогда TCP к `:9971` рвётся так же, как при «плохом» power-save. Скрипт пишет `PnPCapabilities=24` и `Set-NetAdapterPowerManagement -AllowComputerToTurnOffDevice Disabled`.

---

## 3. LSO v2 IPv4 / IPv6 — OFF

**Что это.** Large Send Offload v2: ОС отдаёт большой кусок TCP-данных, а чип «режет» его на сегменты сам. В UI: *Large Send Offload v2 (IPv4/IPv6)*, *Большой объем/объём отправки…*.

**Зачем выключаем.** На части Realtek-драйверов HW-сегментация даёт сбои или странные задержки именно на игровом TCP. Lu4 на входе в мир чувствителен к короткому сеансу `:9971`; LSO — частый кандидат на «Ethernet падает, WiFi нет». Плюс cmdlet `Disable-NetAdapterLso`.

**Цель:** `*LsoV2IPv4=0`, `*LsoV2IPv6=0`.

---

## 4. RSC IPv4 / IPv6 — OFF

**Что это.** Receive Segment Coalescing: чип склеивает несколько входящих TCP-сегментов в один «пакет» для ОС, чтобы снизить нагрузку на CPU. В UI: *Recv/Receive Segment Coalescing*, *Объединение сегментов приёма*, *RSC*.

**Зачем выключаем.** Склейка меняет тайминг и вид входящего потока. Для веб это ок; для короткого world-handshake Lu4 может ломать ожидания стека/клиента. Симптом снова: drop на Ethernet при живом WiFi на том же IP. Плюс `Disable-NetAdapterRsc`.

**Цель:** `*RscIPv4=0`, `*RscIPv6=0`.

---

## 5. Checksum offload (TCP / UDP / IP) — REG = 0

**Что это.** Подсчёт контрольных сумм пакетов делает NIC, а не Windows. В UI: *TCP/UDP/IP Checksum Offload*, *Проверка контрольной суммы…*. Скрипт ставит реестр в `0` и вызывает `Disable-NetAdapterChecksumOffload`.

**Зачем выключаем.** На некоторых драйверах Realtek HW-checksum даёт редкие, но жёсткие сбои (пакет «битый» с точки зрения стека / пира). В рабочем батче выключили весь набор TCP/UDP/IP IPv4/IPv6 — не «ради скорости», а чтобы убрать класс багов offload на cold path.

**Цель:** `*TCPChecksumOffloadIPv4/IPv6=0`, `*UDPChecksumOffload…=0`, `*IPChecksumOffloadIPv4=0` + cmdlet.

---

## Дополнительно в рабочем батче

### Selective Suspend — OFF

**Что это.** Выборочная приостановка устройства (USB/PCIe-стиль sleep), когда драйвер считает, что NIC «не нужен».

**Зачем.** Та же логика power-save: сон между login и world → риск сброса линка/устройства в момент `:9971`.

### Idle Power Down — OFF

**Что это.** Уход NIC в низкое потребление при простое между пакетами.

**Зачем.** Вход в мир — не ровный поток трафика; idle-down между короткими пакетами может «промахнуться» по таймингу и дать disconnect на Ethernet.

### ASPM = 0

**Что это.** Active State Power Management на PCIe-линке адаптера (экономия на шине, не «галка в свойствах» в привычном виде).

**Зачем.** ASPM тоже может вносить latency/wake на шине в неудачный момент handshake. В known-good: **ASPM=0** (выкл.).

---

## Чего не делать после успеха

- Не включать обратно LSO / RSC / EEE / Green / «разрешить отключение…» «для скорости» — cold OFF снова сломается.  
- Не считать фиксом hotspot / VPN / смену публичного IP.  
- После обновления драйвера Realtek (Win10 и Win11): снова **Apply**, затем **Test**.
