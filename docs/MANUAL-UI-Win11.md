# Ручные правки NIC — Windows 11

Цель: Realtek **Ethernet**. Скрипт предпочтительнее: `Apply-Lu4EthernetNic.ps1` + проверка `Test-Lu4EthernetNic.ps1` (тот же, что на Win10).

## 0. Подготовка

1. Закройте Lu4 / лаунчер (по возможности).  
2. **Диспетчер устройств** — основной путь (как на Win10): `Win+X` → **Диспетчер устройств**, или `devmgmt.msc`.  
3. **Сетевые адаптеры** → **Realtek PCIe GbE Family Controller**.

### Отличия UI Win11 (Параметры)

- **Параметры** → **Сеть и Интернет** → **Ethernet** — статус линка / IP.  
- Далее **Дополнительные параметры сети** (*Advanced network settings*) → **Дополнительные параметры адаптера** / **Изменить параметры адаптера** → список подключений (как классическая Панель управления).  
- ПКМ по Ethernet → **Свойства** → **Настроить…** → вкладки **Дополнительно** и **Управление электропитанием**.

Вкладки Device Manager на Win11 **те же**, что на Win10; меняется только оболочка «Параметры».

## 1. Вкладка «Дополнительно» (Advanced)

ПКМ по адаптеру в Device Manager → **Свойства** → **Дополнительно**.

**Отключено** / **Disabled** для:

| # | EN | RU (типично) | Зачем |
|---|----|--------------|--------|
| 1 | Energy-Efficient Ethernet | Энергоэффективный Ethernet | power-save vs `:9971` |
| 2 | Green Ethernet | Зелёный / Энергосберегающий Ethernet | то же |
| 3 | Large Send Offload v2 (IPv4/IPv6) | Большой объем отправки / LSO v2 | HW segmentation |
| 4 | Recv Segment Coalescing (IPv4/IPv6) | Объединение сегментов приёма / RSC | coalesce RX |
| 5 | TCP/UDP/IP Checksum Offload | Проверка контрольной суммы … | checksum offload |

Также **Disabled**, если есть: Selective Suspend, Idle Power Down, EEE Link Advertisement.

**OK**.

## 2. «Управление электропитанием»

Снять **«Разрешить отключение этого устройства для экономии энергии»**  
EN: *Allow the computer to turn off this device to save power*  
→ **`PnPCapabilities = 24`**.

## 3. Проверка

1. Ethernet **Up**.  
2. E-Net OFF.  
3. Публичный IP = `<PUBLIC_WAN_IP>` (без hotspot/VPN).  
4. Lu4: фракция **Black** → **Recommended** → выбрать **Black** в **Servers** → **OK** → выбор персонажа.  
   После выбора Black в Servers — **только OK**.  
5. TCP `:9971` ≥ 20 с.

## 4. После обновления драйвера (Win11)

Тот же риск отката EEE/LSO/RSC (Windows Update / OEM).

```powershell
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1
powershell -ExecutionPolicy Bypass -File .\Test-Lu4EthernetNic.ps1
```

## Чего не делать

- Не VPN / hotspot как «фикс».  
- Не полагаться только на E-Net (`<ENET_EGRESS_IP>`).  
- Не отключать Ethernet без нужды.
