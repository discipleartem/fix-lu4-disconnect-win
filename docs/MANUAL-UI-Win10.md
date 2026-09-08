# Ручные правки NIC — Windows 10

Цель: Realtek **Ethernet**. Скрипт предпочтительнее: `Apply-Lu4EthernetNic.ps1` + проверка `Test-Lu4EthernetNic.ps1`.

## 0. Подготовка

1. Закройте Lu4 / лаунчер (не обязательно, но проще).  
2. Откройте **Диспетчер устройств**: `Win+X` → **Диспетчер устройств**, или `devmgmt.msc`, или Панель управления → Система → Диспетчер устройств.  
3. Раскройте **Сетевые адаптеры** → **Realtek PCIe GbE Family Controller** (или ваш проводной Realtek).

Альтернативный путь к свойствам адаптера (классика Win10):

- **Параметры** → **Сеть и Интернет** → **Ethernet** → имя подключения → **Изменить параметры адаптера** (Панель управления `\Network Connections`) → ПКМ по Ethernet → **Свойства** → **Настроить…**  
  (дальше те же вкладки, что в Device Manager).

## 1. Вкладка «Дополнительно» (Advanced)

ПКМ по адаптеру → **Свойства** → **Дополнительно**.

Выставьте **Отключено** / **Disabled** (если пункт есть — набор зависит от INF):

| # | EN | RU (типично) | Зачем |
|---|----|--------------|--------|
| 1 | Energy-Efficient Ethernet | Энергоэффективный Ethernet | power-save линка vs `:9971` |
| 2 | Green Ethernet | Зелёный / Энергосберегающий Ethernet | то же семейство |
| 3 | Large Send Offload v2 (IPv4) | Большой объем отправки (IPv4) / LSO v2 | HW segmentation |
| 4 | Large Send Offload v2 (IPv6) | … IPv6 | то же |
| 5 | Recv Segment Coalescing (IPv4/IPv6) | Объединение сегментов приёма / RSC | coalesce RX |
| 6 | TCP/UDP/IP Checksum Offload | Проверка контрольной суммы … | offload checksum |

Также **Disabled**, если видно: Selective Suspend, Idle Power Down, EEE Link Advertisement.

Не обязательно: Speed & Duplex (Auto), буферы RX/TX.

**OK**.

## 2. «Управление электропитанием»

Свойства того же Realtek → **Управление электропитанием**:

1. Снять **«Разрешить отключение этого устройства для экономии энергии»**  
   EN: *Allow the computer to turn off this device to save power*  
2. (Опционально) wake-галочки выкл.  
3. **OK**.

Реестр: **`PnPCapabilities = 24`**.

## 3. Проверка

1. Ethernet **Up** (линк 100 Mbps достаточный).  
2. E-Net / E-Global — **выключен**.  
3. Публичный IP = ваш белый WAN (`<PUBLIC_WAN_IP>`), не hotspot.  
4. Lu4: фракция **Black** → **Recommended** → выбрать **Black** в **Servers** → **OK** → выбор персонажа.  
   После выбора Black в Servers — **только OK** (не выбирать Black повторно).  
5. TCP `:9971` Established ≥ 20 с.

## 4. После обновления драйвера (Win10)

Windows Update / OEM / Realtek часто **возвращает** EEE/LSO/RSC.

```powershell
powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1
powershell -ExecutionPolicy Bypass -File .\Test-Lu4EthernetNic.ps1
```

## Чего не делать

- Не VPN / hotspot как «фикс».  
- Не полагаться только на E-Net (`<ENET_EGRESS_IP>`).  
- Не отключать сам Ethernet без нужды — нужен cold OFF **на Ethernet**.
