# fix-lu4-disconnect-win

Фикс **disconnect Lu4 на Windows** (cold path, E-Net OFF) — **Ethernet (ПК)** и **WiFi (ноутбук)**.

Win10 = Win11. Корень: **энергосбережение / offload NIC** на пути в игру (кабель или WiFi) — **не** бан IP.

**Править только путь в игру.** Кабель → Ethernet. Только Wi‑Fi → Wi‑Fi. Чужой адаптер не трогайте.

| | |
|--|--|
| ОС | **Windows 10** и **Windows 11** — одни и те же шаги |
| ПК (кабель) | адаптер **Ethernet** (часто Realtek PCIe GbE) |
| Ноутбук (без кабеля) | адаптер **Wi‑Fi** / Wireless |
| Скрипты | `Apply-Lu4EthernetNic.ps1` / `Rollback-…` — то же самое автоматически (ниже) |

---

## Ручная инструкция (Windows 10 / 11)

### 0. Перед правками

1. Закройте Lu4 / лаунчер.
2. Запомните, чем сидите в сети: кабель или Wi‑Fi.
3. (По желанию) Сфотографируйте вкладки **Управление питанием** и **Дополнительно** — проще откатить вручную.

### 1. Открыть свойства адаптера

**Быстрый путь (Win10 и Win11):** `Win+R` → `ncpa.cpl` → Enter.

**Windows 11:** Параметры → Сеть и Интернет → Дополнительные параметры сети → Дополнительные параметры адаптера.  
**Windows 10:** Параметры → Сеть и Интернет → Состояние → Настройка параметров адаптера.

В списке:

| Машина | Что выбрать |
|--------|-------------|
| **ПК с кабелем** | `Ethernet` / Realtek… (иконка RJ‑45) |
| **Ноутбук по Wi‑Fi** | `Wi‑Fi` / Беспроводная сеть / Intel/Realtek Wireless |

ПКМ → **Свойства** → **Настроить…** (окно драйвера NIC).

### 2. Вкладка «Управление питанием» (обязательно)

На **Управление питанием** / **Power Management**:

- Снять галку **Разрешить отключение этого устройства для экономии энергии**  
  (EN: *Allow the computer to turn off this device to save power*).

**OK**. (То же, что `PnPCapabilities=24` в скрипте.)

> Если вкладки нет — всё равно сделайте §3. На части Wi‑Fi галка только в Advanced.

### 3A. ПК — Ethernet → «Дополнительно»

Вкладка **Дополнительно** / **Advanced**. Для каждого пункта — **Отключено** / **Disabled** (если свойство есть; нет в INF — пропустите).

| Свойство (EN) | Часто по-русски | Цель |
|---------------|-----------------|------|
| Energy-Efficient Ethernet / EEE | Энергоэффективный Ethernet | **Отключено** |
| EEE Link Advertisement | Объявление / реклама EEE | **Отключено** |
| Green Ethernet | Зелёный / энергосберегающий Ethernet | **Отключено** |
| Selective Suspend | Выборочная приостановка | **Отключено** |
| Idle Power Down | Отключение питания в простое | **Отключено** |
| Large Send Offload v2 (IPv4) | Большой объём отправки v2 (IPv4) | **Отключено** |
| Large Send Offload v2 (IPv6) | … (IPv6) | **Отключено** |
| Recv / Receive Segment Coalescing (IPv4) | Объединение сегментов (IPv4) | **Отключено** |
| Recv Segment Coalescing (IPv6) | … (IPv6) | **Отключено** |
| TCP Checksum Offload (IPv4) | Проверка контрольной суммы TCP (IPv4) | **Отключено** |
| TCP Checksum Offload (IPv6) | … (IPv6) | **Отключено** |
| UDP Checksum Offload (IPv4/IPv6) | … UDP … | **Отключено** |
| IP Checksum Offload | … IP … | **Отключено** |
| ASPM / PCIe ASPM (если есть) | — | **Off / 0 / Disabled** |

**OK**. Краткий обрыв линка — нормально; подождите 5–10 с.

### 3B. Ноутбук — Wi‑Fi → «Дополнительно»

Тот же путь: `ncpa.cpl` → Wi‑Fi → Свойства → Настроить… → **Дополнительно**.

| Свойство (EN) | Часто по-русски | Цель |
|---------------|-----------------|------|
| Power Saving Mode / Power Save | Режим энергосбережения | **Отключено** или **Maximum Performance** |
| Sleep on Disconnect / Device Sleep On Disconnect | Сон при отключении | **Отключено** |
| uAPSD / U-APSD | — | **Отключено** |
| Selective Suspend | Выборочная приостановка | **Отключено** |
| Idle Power Down | Отключение питания в простое | **Отключено** |
| Roaming Aggressiveness | Агрессивность роуминга | **Низкая** / Low (не Highest) |
| LSO / RSC / Checksum Offload (если есть) | как у Ethernet | **Отключено** |

Плюс §2 (галка питания), если вкладка есть. Идея та же: радио не «засыпает» на входе в мир `:9971`.

### 4. Проверка в Lu4

**E-Net OFF** (без туннеля).

1. Игра → фракция **Black**.
2. Servers → **Black** (или Recommended → Black).
3. Нажать **только OK** (не выбирать Black повторно).
4. Успех: экран **выбора персонажа**, без disconnect через ~2 с.

По желанию:

```powershell
Get-NetTCPConnection -RemotePort 9971 -State Established -ErrorAction SilentlyContinue
```

Держится **≥ 20 с** → мир живой.

### 5. Если не помогло

1. Правили **тот** адаптер, через который реально идёт трафик.
2. Иногда нужна перезагрузка после Advanced.
3. На ПК с кабелем Wi‑Fi выключать не обязательно — важны настройки Ethernet.
4. Либо скрипт Apply (ниже).

Откат вручную — вернуть значения из фото (§0). Скриптовый откат — только если до этого гоняли Apply (есть снимок).

### Шпаргалка

```
ncpa.cpl
  → нужный адаптер (Ethernet ПК / Wi‑Fi ноут)
  → Свойства → Настроить…
  → Управление питанием: снять «разрешить отключение…»
  → Дополнительно: EEE / Green / Power Save / Sleep / LSO / RSC / checksum → Отключено
  → OK → Lu4 (E-Net OFF → Black → OK → персы)
```

---

## Скрипты (альтернатива)

1. **Apply** читает текущие значения → таблица → снимок  
   `%LOCALAPPDATA%\fix-lu4-disconnect-win\snapshot-<GUID>.json`  
   (повторный Apply **не** затирает снимок — там значения *до первого фикса*).
2. Точечно ставит known-good **только** где сейчас ≠ цель.
3. **Rollback** возвращает **только** `previousValue` из снимка. Без снимка — отказ (не угадывает «заводские»).

**Auto:** есть Ethernet → Ethernet; иначе WiFi (ноутбук без кабеля).

### Запуск (Admin)

```powershell
# ПК с кабелем или ноут (Auto)
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1

# Ноутбук явно по WiFi
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -Media WiFi

# Откат к значениям до фикса
powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1
powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1 -Media WiFi
```

### Что правим

**Ethernet:** EEE, Green, LSO, RSC, checksum, Selective Suspend, Idle Power Down, ASPM=0, PnPCapabilities=24.

**WiFi (ноут):** Power Saving, Sleep on disconnect, uAPSD, Selective Suspend / Idle Power Down, offloads если есть в INF, PnPCapabilities=24.
