# Ручные правки NIC (UI) — индекс

Если скрипт `Apply-Lu4EthernetNic.ps1` недоступен, те же настройки можно выставить вручную.  
Цель: Realtek **Ethernet** (не WiFi). После смены драйвера — снова Apply + `Test-Lu4EthernetNic.ps1`.

## По ОС

| ОС | Документ |
|----|----------|
| **Windows 10** | [`MANUAL-UI-Win10.md`](MANUAL-UI-Win10.md) |
| **Windows 11** | [`MANUAL-UI-Win11.md`](MANUAL-UI-Win11.md) |

Вкладки **Дополнительно** / **Управление электропитанием** в **Диспетчере устройств** одинаковы на Win10 и Win11.  
Отличается в основном путь через **Параметры → Сеть** (Win11: «Дополнительные параметры сети»).

Пояснения «что это / зачем»: [`SETTINGS-EXPLAINED.ru.md`](SETTINGS-EXPLAINED.ru.md).

## Общий чеклист (known-good)

### Advanced — Disabled / Отключено

| # | EN | RU (типично) |
|---|----|--------------|
| 1 | Energy-Efficient Ethernet | Энергоэффективный Ethernet |
| 2 | Green Ethernet | Зелёный / Энергосберегающий Ethernet |
| 3 | Large Send Offload v2 (IPv4/IPv6) | Большой объем отправки … / LSO v2 |
| 4 | Recv Segment Coalescing (IPv4/IPv6) | Объединение сегментов приёма / RSC |
| 5 | TCP/UDP/IP Checksum Offload | Проверка контрольной суммы … |
| 6 | Selective Suspend / Idle Power Down / EEE Link Advertisement (если есть) | Disabled |

### Power Management

Снять: **«Разрешить отключение этого устройства для экономии энергии»** → `PnPCapabilities = 24`.

### После драйвера Realtek

На **Win10 и Win11**: снова `Apply-Lu4EthernetNic.ps1`, затем `Test-Lu4EthernetNic.ps1`.

### Проверка Lu4

E-Net OFF → Ethernet up → фракция **Black** → **Recommended** → выбрать **Black** в **Servers** → **OK** → выбор персонажа.  
После выбора Black в Servers — **только OK** (без повторного «Black»).  
Публичный IP = ваш белый WAN (`<PUBLIC_WAN_IP>`), не hotspot/VPN. TCP `:9971` ≥ 20 с.

## Чего не делать

- Не VPN / hotspot «чтобы зайти» — смена пути, не фикс NIC.  
- Не полагаться только на E-Net (`<ENET_EGRESS_IP>`) — другой egress.  
- Не выключать Ethernet «для проверки» без необходимости — нужен cold OFF **на Ethernet**.
