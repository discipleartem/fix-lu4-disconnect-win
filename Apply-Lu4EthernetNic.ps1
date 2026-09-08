#requires -Version 5.1
<#
.SYNOPSIS
  Apply known-good NIC power/offload settings for Lu4 disconnect (Ethernet PC or WiFi notebook).

.DESCRIPTION
  PROBLEM: Lu4 cold login disconnect after Servers OK (~2s TCP :9971 then drop) on a bad NIC path.
  FIX: Disable NIC power-save/offload on the path you actually use:
       Desktop cable → Ethernet (Realtek GbE: EEE/Green/LSO/RSC/checksum/…).
       Notebook WiFi → wireless adapter (Power Saving / sleep / uAPSD / PnP / offloads if present).
  Root cause: NIC power-save/offload — not ISP/IP.
  Companion: Rollback-Lu4EthernetNic.ps1 | Targets: settings.known-good.json
  Exit: 0 = applied; 1 = missing adapter or needs admin.

.PARAMETER Media
  Auto (default): Ethernet if Realtek/wired found, else WiFi (typical notebook).
  Ethernet | WiFi: force that media.

.PARAMETER Name
  NetAdapter Name (skip auto-detect).

.PARAMETER InterfaceDescription
  Match InterfaceDescription (e.g. "Realtek PCIe GbE" or "Wi-Fi").

.PARAMETER DisableWifi
  Only with Ethernet path: optionally disable wireless adapters after apply.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -Media WiFi
#>
[CmdletBinding()]
param(
    [ValidateSet("Auto", "Ethernet", "WiFi")]
    [string]$Media = "Auto",
    [string]$Name,
    [string]$InterfaceDescription,
    [switch]$DisableWifi
)

# Продолжать при некритичных ошибках отдельных свойств (драйвер может не экспонировать всё)
$ErrorActionPreference = "Continue"

# Путь класса сетевых адаптеров в реестре Windows
$script:NicClassPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
# PnPCapabilities=24 (0x18): запрет «разрешить отключение устройства для экономии энергии»
$script:TargetPnPCapabilities = 24

# Список advanced-свойств NIC: keyword → значение 0 (выкл.) + алиасы для разных INF
$script:AdvTargets = @(
    @{
        RegistryKeyword = "*EEE"
        AltKeywords     = @("EEE", "*EnergyEfficientEthernet")
        DisplayNames    = @("*Energy-Efficient Ethernet*", "*Energy Efficient Ethernet*", "*Энергоэффективный Ethernet*", "*EEE*")
        Value           = "0"
        Why             = "EEE OFF — энергосбережение линка; NIC «дремлет» → drop TCP :9971"
    }
    @{
        RegistryKeyword = "*EEELinkAdvertisement"
        AltKeywords     = @("EEELinkAdvertisement")
        DisplayNames    = @("*EEE Link Advertisement*", "*EEE*Advert*", "*Реклам*EEE*", "*Объявлен*EEE*")
        Value           = "0"
        Why             = "EEE Link Advertisement OFF — дополнение к полному отключению EEE"
    }
    @{
        RegistryKeyword = "*GreenEthernet"
        AltKeywords     = @("GreenEthernet", "*Green*")
        DisplayNames    = @("*Green Ethernet*", "*Зелёный Ethernet*", "*Зеленый Ethernet*", "*Энергосберегающий Ethernet*")
        Value           = "0"
        Why             = "Green Ethernet OFF — Realtek cable/power gating vs :9971"
    }
    @{
        RegistryKeyword = "GreenEthernet"
        AltKeywords     = @()
        DisplayNames    = @()
        Value           = "0"
        Why             = "Legacy GreenEthernet=0 (некоторые INF без звёздочки)"
    }
    @{
        RegistryKeyword = "*SelectiveSuspend"
        AltKeywords     = @("SelectiveSuspend", "*SS*")
        DisplayNames    = @("*Selective Suspend*", "*Выборочная приостановка*", "*Селективн*")
        Value           = "0"
        Why             = "Selective Suspend OFF — сон NIC в паузе login→world"
    }
    @{
        RegistryKeyword = "*IdlePowerDown"
        AltKeywords     = @("IdlePowerDown")
        DisplayNames    = @("*Idle Power*", "*Простой*питан*", "*Idle*Down*")
        Value           = "0"
        Why             = "Idle Power Down OFF — sleep между пакетами ломает world handshake"
    }
    @{
        RegistryKeyword = "*LsoV2IPv4"
        AltKeywords     = @("*LSO*IPv4*", "*LsoV2*IPv4*")
        DisplayNames    = @("*Large Send Offload*v2*IPv4*", "*LSO*v2*IPv4*", "*Большой объем отправки*IPv4*", "*Большой объём отправки*IPv4*")
        Value           = "0"
        Why             = "LSO v2 IPv4 OFF — HW-нарезка TCP на Realtek ломает игровой сеанс"
    }
    @{
        RegistryKeyword = "*LsoV2IPv6"
        AltKeywords     = @("*LSO*IPv6*", "*LsoV2*IPv6*")
        DisplayNames    = @("*Large Send Offload*v2*IPv6*", "*LSO*v2*IPv6*", "*Большой объем отправки*IPv6*", "*Большой объём отправки*IPv6*")
        Value           = "0"
        Why             = "LSO v2 IPv6 OFF — тот же риск HW-сегментации"
    }
    @{
        RegistryKeyword = "*RscIPv4"
        AltKeywords     = @("*RSC*IPv4*", "*RecvSegmentCoalescing*IPv4*")
        DisplayNames    = @("*Recv Segment Coalescing*IPv4*", "*Receive Segment Coalescing*IPv4*", "*RSC*IPv4*", "*Объединение сегментов*IPv4*")
        Value           = "0"
        Why             = "RSC IPv4 OFF — склейка RX портит тайминг :9971"
    }
    @{
        RegistryKeyword = "*RscIPv6"
        AltKeywords     = @("*RSC*IPv6*", "*RecvSegmentCoalescing*IPv6*")
        DisplayNames    = @("*Recv Segment Coalescing*IPv6*", "*Receive Segment Coalescing*IPv6*", "*RSC*IPv6*", "*Объединение сегментов*IPv6*")
        Value           = "0"
        Why             = "RSC IPv6 OFF — тот же риск RX-coalesce"
    }
    @{
        RegistryKeyword = "*TCPChecksumOffloadIPv4"
        AltKeywords     = @("*TCPChecksum*IPv4*")
        DisplayNames    = @("*TCP Checksum Offload*IPv4*", "*TCP*контрольной суммы*IPv4*", "*Проверка контрольной суммы TCP*IPv4*")
        Value           = "0"
        Why             = "TCP checksum OFF IPv4 — баги HW checksum на Realtek"
    }
    @{
        RegistryKeyword = "*TCPChecksumOffloadIPv6"
        AltKeywords     = @("*TCPChecksum*IPv6*")
        DisplayNames    = @("*TCP Checksum Offload*IPv6*", "*TCP*контрольной суммы*IPv6*", "*Проверка контрольной суммы TCP*IPv6*")
        Value           = "0"
        Why             = "TCP checksum OFF IPv6 — в том же known-good батче"
    }
    @{
        RegistryKeyword = "*UDPChecksumOffloadIPv4"
        AltKeywords     = @("*UDPChecksum*IPv4*")
        DisplayNames    = @("*UDP Checksum Offload*IPv4*", "*UDP*контрольной суммы*IPv4*", "*Проверка контрольной суммы UDP*IPv4*")
        Value           = "0"
        Why             = "UDP checksum OFF IPv4 — часть known-good offload batch"
    }
    @{
        RegistryKeyword = "*UDPChecksumOffloadIPv6"
        AltKeywords     = @("*UDPChecksum*IPv6*")
        DisplayNames    = @("*UDP Checksum Offload*IPv6*", "*UDP*контрольной суммы*IPv6*", "*Проверка контрольной суммы UDP*IPv6*")
        Value           = "0"
        Why             = "UDP checksum OFF IPv6 — часть known-good offload batch"
    }
    @{
        RegistryKeyword = "*IPChecksumOffloadIPv4"
        AltKeywords     = @("*IPChecksumOffload*", "*IPChecksum*")
        DisplayNames    = @("*IP Checksum Offload*", "*IP*контрольной суммы*", "*Проверка контрольной суммы IP*")
        Value           = "0"
        Why             = "IP checksum OFF IPv4 — часть known-good offload batch"
    }
)

# WiFi (ноутбук): типичные power-save ключи INF — best-effort, отсутствующие пропускаем
$script:WifiAdvTargets = @(
    @{
        RegistryKeyword = "*PowerSaveMode"
        AltKeywords     = @("PowerSaveMode", "*PMWiFi", "*WiFiPower*", "*WirelessPower*")
        DisplayNames    = @("*Power Saving*", "*Режим энергосбережения*", "*Энергосбережение*", "*Power Save*")
        Value           = "0"
        Why             = "WiFi Power Saving OFF — max performance, без sleep радио"
    }
    @{
        RegistryKeyword = "*DeviceSleepOnDisconnect"
        AltKeywords     = @("DeviceSleepOnDisconnect")
        DisplayNames    = @("*Sleep*Disconnect*", "*Сон*отключ*", "*Device Sleep*")
        Value           = "0"
        Why             = "Device Sleep On Disconnect OFF"
    }
    @{
        RegistryKeyword = "*uAPSDSupport"
        AltKeywords     = @("*uAPSD*", "uAPSD")
        DisplayNames    = @("*uAPSD*", "*U-APSD*")
        Value           = "0"
        Why             = "uAPSD OFF — WiFi power-save delivery"
    }
    @{
        RegistryKeyword = "*RoamingAggressiveness"
        AltKeywords     = @("RoamingAggressiveness", "*Roaming*")
        DisplayNames    = @("*Roaming Aggressiveness*", "*Агрессивность роуминга*")
        Value           = "1"
        Why             = "Roaming низкий/средний — меньше скачков AP во время login"
    }
    @{
        RegistryKeyword = "*SelectiveSuspend"
        AltKeywords     = @("SelectiveSuspend")
        DisplayNames    = @("*Selective Suspend*", "*Выборочная приостановка*")
        Value           = "0"
        Why             = "Selective Suspend OFF на WiFi"
    }
    @{
        RegistryKeyword = "*IdlePowerDown"
        AltKeywords     = @("IdlePowerDown")
        DisplayNames    = @("*Idle Power*", "*Простой*питан*")
        Value           = "0"
        Why             = "Idle Power Down OFF на WiFi"
    }
    @{
        RegistryKeyword = "*LsoV2IPv4"
        AltKeywords     = @("*LSO*IPv4*")
        DisplayNames    = @("*Large Send Offload*IPv4*", "*LSO*IPv4*")
        Value           = "0"
        Why             = "LSO OFF на WiFi если драйвер экспонирует"
    }
    @{
        RegistryKeyword = "*LsoV2IPv6"
        AltKeywords     = @("*LSO*IPv6*")
        DisplayNames    = @("*Large Send Offload*IPv6*", "*LSO*IPv6*")
        Value           = "0"
        Why             = "LSO v2 IPv6 OFF на WiFi если есть"
    }
    @{
        RegistryKeyword = "*RscIPv4"
        AltKeywords     = @("*RSC*IPv4*")
        DisplayNames    = @("*Recv Segment Coalescing*IPv4*", "*RSC*IPv4*")
        Value           = "0"
        Why             = "RSC OFF на WiFi если есть"
    }
    @{
        RegistryKeyword = "*RscIPv6"
        AltKeywords     = @("*RSC*IPv6*")
        DisplayNames    = @("*Recv Segment Coalescing*IPv6*", "*RSC*IPv6*")
        Value           = "0"
        Why             = "RSC IPv6 OFF на WiFi если есть"
    }
    @{
        RegistryKeyword = "*TCPChecksumOffloadIPv4"
        AltKeywords     = @("*TCPChecksum*IPv4*")
        DisplayNames    = @("*TCP Checksum Offload*IPv4*")
        Value           = "0"
        Why             = "TCP checksum OFF на WiFi если есть"
    }
    @{
        RegistryKeyword = "*TCPChecksumOffloadIPv6"
        AltKeywords     = @("*TCPChecksum*IPv6*")
        DisplayNames    = @("*TCP Checksum Offload*IPv6*")
        Value           = "0"
        Why             = "TCP checksum IPv6 OFF на WiFi если есть"
    }
    @{
        RegistryKeyword = "*UDPChecksumOffloadIPv4"
        AltKeywords     = @("*UDPChecksum*IPv4*")
        DisplayNames    = @("*UDP Checksum Offload*IPv4*")
        Value           = "0"
        Why             = "UDP checksum OFF на WiFi если есть"
    }
    @{
        RegistryKeyword = "*UDPChecksumOffloadIPv6"
        AltKeywords     = @("*UDPChecksum*IPv6*")
        DisplayNames    = @("*UDP Checksum Offload*IPv6*")
        Value           = "0"
        Why             = "UDP checksum IPv6 OFF на WiFi если есть"
    }
    @{
        RegistryKeyword = "*IPChecksumOffloadIPv4"
        AltKeywords     = @("*IPChecksum*")
        DisplayNames    = @("*IP Checksum Offload*")
        Value           = "0"
        Why             = "IP checksum OFF на WiFi если есть"
    }
)

function Get-Lu4OsInfo {
    # Считать версию ОС (Win10 vs Win11 по build)
    $envVer = [Environment]::OSVersion.Version
    $cim = $null
    try { $cim = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch {}
    $caption = if ($cim -and $cim.Caption) { [string]$cim.Caption.Trim() } else { "Windows" }
    $build = if ($cim -and $cim.BuildNumber) { [int]$cim.BuildNumber } else { [int]$envVer.Build }
    $family = if ($build -ge 22000) { "Windows 11" } elseif ($build -ge 10240) { "Windows 10" } else { "Windows (pre-10)" }
    $arch = if ($cim -and $cim.OSArchitecture) { [string]$cim.OSArchitecture } else { $env:PROCESSOR_ARCHITECTURE }
    [pscustomobject]@{
        Caption      = $caption
        Family       = $family
        Version      = $envVer.ToString()
        Build        = $build
        Architecture = $arch
    }
}

function Write-Lu4OsBanner {
    # Показать баннер ОС — один канон для Win10 и Win11
    $os = Get-Lu4OsInfo
    Write-Host ("OS: {0} | Family={1} | Version={2} | Build={3} | Arch={4}" -f `
        $os.Caption, $os.Family, $os.Version, $os.Build, $os.Architecture)
    Write-Host "Supported: Windows 10 and Windows 11 (same script / same known-good NIC settings)."
    return $os
}

function Test-IsAdmin {
    # Проверка прав администратора (нужны для реестра и Disable-NetAdapter*)
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Step([string]$Message) {
    # Строка лога с меткой времени
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Test-IsWifiAdapter {
    param($Adapter)
    # Heuristic: WiFi / Wireless / 802.11 в имени или описании
    return (
        $Adapter.InterfaceDescription -match "Wireless|Wi-?Fi|802\.11|WLAN" -or
        $Adapter.Name -match "Wi-?Fi|WLAN|Беспровод" -or
        $Adapter.MediaType -match "Native 802.11|Wireless"
    )
}

function Test-IsEthernetAdapter {
    param($Adapter)
    # Heuristic: проводной Ethernet / GbE, не WiFi
    if (Test-IsWifiAdapter $Adapter) { return $false }
    return (
        $Adapter.MediaType -eq "802.3" -or
        $Adapter.InterfaceDescription -match "Ethernet|GbE|LAN|Realtek.*PCIe"
    )
}

function Resolve-Lu4Adapter {
    param(
        [string]$Media,
        [string]$Name,
        [string]$InterfaceDescription
    )

    # Список присутствующих адаптеров
    $all = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -ne "Not Present" })

    # Явный выбор по -Name
    if ($Name) {
        $hit = $all | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if (-not $hit) { throw "Adapter Name='$Name' not found." }
        return [pscustomobject]@{ Adapter = $hit; MediaKind = $(if (Test-IsWifiAdapter $hit) { "WiFi" } else { "Ethernet" }) }
    }

    # Явный выбор по описанию интерфейса
    if ($InterfaceDescription) {
        $hit = $all | Where-Object { $_.InterfaceDescription -like "*$InterfaceDescription*" } | Select-Object -First 1
        if (-not $hit) { throw "Adapter InterfaceDescription matching '$InterfaceDescription' not found." }
        return [pscustomobject]@{ Adapter = $hit; MediaKind = $(if (Test-IsWifiAdapter $hit) { "WiFi" } else { "Ethernet" }) }
    }

    # Кандидаты Ethernet (Realtek GbE предпочтительно)
    $ethPreferred = @(
        $all | Where-Object {
            $_.InterfaceDescription -match "Realtek.*GbE|Realtek.*Ethernet|PCIe GbE" -and
            -not (Test-IsWifiAdapter $_)
        }
    )
    $ethAny = @($all | Where-Object { Test-IsEthernetAdapter $_ })
    $wifiAny = @(
        $all | Where-Object { Test-IsWifiAdapter $_ } |
            Sort-Object { if ($_.Status -eq "Up") { 0 } else { 1 } }, Name
    )

    $kind = $Media
    if ($kind -eq "Auto") {
        # Auto: есть проводной Realtek/Ethernet → Ethernet; иначе WiFi (ноутбук без кабеля)
        if ($ethPreferred.Count -ge 1 -or $ethAny.Count -ge 1) {
            $kind = "Ethernet"
        } elseif ($wifiAny.Count -ge 1) {
            $kind = "WiFi"
            Write-Host "Auto: Ethernet not found → using WiFi (notebook path)."
        } else {
            throw "Auto: no Ethernet and no WiFi adapter found."
        }
    }

    if ($kind -eq "Ethernet") {
        if ($ethPreferred.Count -eq 1) {
            return [pscustomobject]@{ Adapter = $ethPreferred[0]; MediaKind = "Ethernet" }
        }
        if ($ethPreferred.Count -gt 1) {
            Write-Host "Multiple Realtek Ethernet adapters:"
            $ethPreferred | ForEach-Object { Write-Host ("  - Name={0} Desc={1} Status={2}" -f $_.Name, $_.InterfaceDescription, $_.Status) }
            throw "Pass -Name or -InterfaceDescription to select one."
        }
        if ($ethAny.Count -eq 1) {
            Write-Host "WARN: Realtek not matched; using single wired adapter: $($ethAny[0].Name)"
            return [pscustomobject]@{ Adapter = $ethAny[0]; MediaKind = "Ethernet" }
        }
        if ($ethAny.Count -gt 1) {
            Write-Host "Multiple Ethernet adapters:"
            $ethAny | ForEach-Object { Write-Host ("  - Name={0} Desc={1}" -f $_.Name, $_.InterfaceDescription) }
            throw "Pass -Name or -InterfaceDescription."
        }
        throw "Ethernet requested but no wired adapter found. Use -Media WiFi on notebooks."
    }

    if ($kind -eq "WiFi") {
        if ($wifiAny.Count -eq 0) { throw "WiFi requested but no wireless adapter found." }
        # Предпочесть уже Up (подключённый) адаптер
        $up = @($wifiAny | Where-Object { $_.Status -eq "Up" })
        $pick = if ($up.Count -ge 1) { $up[0] } else { $wifiAny[0] }
        if ($wifiAny.Count -gt 1) {
            Write-Host ("WiFi: using '{0}' (Status={1}). Pass -Name to override." -f $pick.Name, $pick.Status)
        }
        return [pscustomobject]@{ Adapter = $pick; MediaKind = "WiFi" }
    }

    throw "Unknown Media='$Media'"
}

function Get-NicRegPath {
    param([string]$InterfaceGuid)
    # Найти ветку Class\{4d36e972…}\NNNN по NetCfgInstanceId = GUID адаптера
    $guidNorm = $InterfaceGuid.Trim("{}")
    Get-ChildItem $script:NicClassPath -ErrorAction Stop | ForEach-Object {
        try {
            $p = Get-ItemProperty $_.PSPath -ErrorAction Stop
            $id = [string]$p.NetCfgInstanceId
            if ($id -and ($id.Trim("{}") -eq $guidNorm)) { return $_.PSPath }
        } catch {}
    }
    return $null
}

function Get-RegValueSafe {
    param([string]$Path, [string]$Name)
    # Безопасное чтение значения реестра (null если нет)
    try {
        $v = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        if ($v -is [array]) { return ($v -join ",") }
        return [string]$v
    } catch {
        return $null
    }
}

function Find-AdvProperty {
    param(
        [string]$AdapterName,
        [hashtable]$Target
    )
    # Сначала точный RegistryKeyword
    $kw = $Target.RegistryKeyword
    $hit = Get-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $kw -ErrorAction SilentlyContinue
    if ($hit) { return $hit }

    # Все advanced-свойства адаптера для поиска по алиасам
    $all = $null
    try { $all = @(Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction Stop) } catch { return $null }
    if (-not $all -or $all.Count -eq 0) { return $null }

    # Поиск по AltKeywords
    foreach ($alt in @($Target.AltKeywords)) {
        if (-not $alt) { continue }
        $hit = $all | Where-Object { $_.RegistryKeyword -like $alt } | Select-Object -First 1
        if ($hit) { return $hit }
    }

    # Поиск по DisplayName (EN/RU)
    foreach ($pat in @($Target.DisplayNames)) {
        if (-not $pat) { continue }
        $hit = $all | Where-Object { $_.DisplayName -like $pat } | Select-Object -First 1
        if ($hit) { return $hit }
    }

    # Мягкий поиск по stem без ведущей *
    $stem = $kw.TrimStart("*")
    if ($stem.Length -ge 3) {
        $hit = $all | Where-Object { $_.RegistryKeyword -like "*$stem*" } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

function Test-ValueMatches {
    param($Raw, [string]$Want)
    # Сравнить текущее значение с целевым (учитывая "0,0,…" и одиночное)
    if ($null -eq $Raw) { return $false }
    $s = ([string]$Raw).Trim()
    if ($s -eq $Want) { return $true }
    if ($Want -eq "0" -and $s -match "^(0)(,\s*0)*$") { return $true }
    return $false
}

function Get-SnapshotDirectory {
    # Каталог снимков до-фикса (per-user, без секретов сети)
    $dir = Join-Path $env:LOCALAPPDATA "fix-lu4-disconnect-win"
    # Создать каталог, если его ещё нет
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-SnapshotPath {
    param([string]$AdapterGuid)
    # Имя файла по GUID адаптера
    $safe = ($AdapterGuid.Trim("{}") -replace "[^A-Fa-f0-9\-]", "")
    return (Join-Path (Get-SnapshotDirectory) ("snapshot-{0}.json" -f $safe))
}

function Read-PropertyCurrent {
    param(
        [string]$AdapterName,
        [string]$RegPath,
        [hashtable]$Target
    )
    # Считать текущее значение одного advanced/reg свойства
    $adv = Find-AdvProperty -AdapterName $AdapterName -Target $Target
    if ($adv) {
        return [pscustomobject]@{
            Source          = "adv"
            RegistryKeyword = [string]$adv.RegistryKeyword
            DisplayName     = [string]$adv.DisplayName
            CurrentValue    = ($adv.RegistryValue -join ",")
            Present         = $true
        }
    }
    $kw = $Target.RegistryKeyword
    $had = Get-RegValueSafe -Path $RegPath -Name $kw
    if ($null -ne $had) {
        return [pscustomobject]@{
            Source          = "reg"
            RegistryKeyword = $kw
            DisplayName     = $null
            CurrentValue    = [string]$had
            Present         = $true
        }
    }
    return [pscustomobject]@{
        Source          = "missing"
        RegistryKeyword = $kw
        DisplayName     = $null
        CurrentValue    = $null
        Present         = $false
    }
}

function New-Lu4NicSnapshot {
    param(
        $Adapter,
        [string]$MediaKind,
        [string]$RegPath,
        [array]$Targets
    )
    # Собрать снимок ВСЕХ релевантных значений ДО любых изменений
    $props = @()
    Write-Host ""
    Write-Host "======== READ current (snapshot) ========"
    foreach ($t in $Targets) {
        $cur = Read-PropertyCurrent -AdapterName $Adapter.Name -RegPath $RegPath -Target $t
        $willChange = $false
        if ($cur.Present) {
            $willChange = -not (Test-ValueMatches $cur.CurrentValue $t.Value)
            Write-Host ("  {0} = {1}  → target {2}  {3}" -f `
                $cur.RegistryKeyword, $cur.CurrentValue, $t.Value, $(if ($willChange) { "[CHANGE]" } else { "[keep]" }))
        } else {
            Write-Host ("  {0} = <absent>  → skip" -f $t.RegistryKeyword)
        }
        $props += [pscustomobject]@{
            kind            = $cur.Source
            registryKeyword = $cur.RegistryKeyword
            displayName     = $cur.DisplayName
            previousValue   = $cur.CurrentValue
            targetValue     = $t.Value
            present         = $cur.Present
            willChange      = $willChange
        }
    }

    # PnPCapabilities
    $pnp = Get-RegValueSafe -Path $RegPath -Name "PnPCapabilities"
    $pnpChange = -not (Test-ValueMatches $pnp ([string]$script:TargetPnPCapabilities))
    Write-Host ("  PnPCapabilities = {0} → target {1}  {2}" -f `
        $(if ($null -eq $pnp -or $pnp -eq "") { "<empty>" } else { $pnp }),
        $script:TargetPnPCapabilities,
        $(if ($pnpChange) { "[CHANGE]" } else { "[keep]" }))

    # ASPM
    $aspm = Get-RegValueSafe -Path $RegPath -Name "ASPM"
    $aspmChange = ($null -ne $aspm) -and ($aspm -ne "0")
    Write-Host ("  ASPM = {0} → target 0  {1}" -f `
        $(if ($null -eq $aspm) { "<absent>" } else { $aspm }),
        $(if ($null -eq $aspm) { "[skip]" } elseif ($aspmChange) { "[CHANGE]" } else { "[keep]" }))

    # Cmdlet-слой: запомнить enabled/disabled
    $lso4 = $null; $lso6 = $null
    try {
        $lso = Get-NetAdapterLso -Name $Adapter.Name -ErrorAction Stop
        $lso4 = [bool]$lso.IPv4Enabled; $lso6 = [bool]$lso.IPv6Enabled
        Write-Host ("  LSO IPv4={0} IPv6={1}" -f $lso4, $lso6)
    } catch { Write-Host "  LSO = <unavailable>" }
    $rsc4 = $null; $rsc6 = $null
    try {
        $rsc = Get-NetAdapterRsc -Name $Adapter.Name -ErrorAction Stop
        $rsc4 = [bool]$rsc.IPv4Enabled; $rsc6 = [bool]$rsc.IPv6Enabled
        Write-Host ("  RSC IPv4={0} IPv6={1}" -f $rsc4, $rsc6)
    } catch { Write-Host "  RSC = <unavailable>" }
    $csumOn = $null
    try {
        $csum = Get-NetAdapterChecksumOffload -Name $Adapter.Name -ErrorAction SilentlyContinue
        $csumOn = [bool]$csum
        Write-Host ("  ChecksumOffload present={0}" -f $csumOn)
    } catch { Write-Host "  ChecksumOffload = <unavailable>" }

    return [pscustomobject]@{
        schema       = "lu4-nic-snapshot/v1"
        savedAt      = (Get-Date).ToString("o")
        adapterName  = [string]$Adapter.Name
        adapterGuid  = [string]$Adapter.InterfaceGuid
        mediaKind    = $MediaKind
        description  = [string]$Adapter.InterfaceDescription
        properties   = $props
        registry     = @{
            PnPCapabilities = @{
                previous  = $pnp
                target    = $script:TargetPnPCapabilities
                willChange = $pnpChange
            }
            ASPM = @{
                previous   = $aspm
                target     = "0"
                willChange = $aspmChange
                present    = ($null -ne $aspm)
            }
        }
        cmdlets = @{
            Lso = @{ ipv4 = $lso4; ipv6 = $lso6 }
            Rsc = @{ ipv4 = $rsc4; ipv6 = $rsc6 }
            ChecksumPresent = $csumOn
        }
    }
}

function Save-Lu4NicSnapshot {
    param($Snapshot, [string]$Path)
    # Записать JSON снимка (только если файла ещё нет — не затирать до-фикс значения)
    if (Test-Path -LiteralPath $Path) {
        Write-Step ("Snapshot KEEP (уже есть, не перезаписываем): {0}" -f $Path)
        return $false
    }
    # Сериализация в JSON
    $json = $Snapshot | ConvertTo-Json -Depth 8
    # Запись файла снимка
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
    Write-Step ("Snapshot SAVED: {0}" -f $Path)
    return $true
}

function Show-AdapterState {
    param($Adapter, [string]$RegPath, [string]$Label)

    # Дамп текущего состояния адаптера (до/после Apply)
    Write-Host ""
    Write-Host "======== $Label ========"
    Write-Host ("Name={0}" -f $Adapter.Name)
    Write-Host ("Desc={0}" -f $Adapter.InterfaceDescription)
    Write-Host ("Status={0} Link={1} IfIndex={2}" -f $Adapter.Status, $Adapter.LinkSpeed, $Adapter.ifIndex)
    Write-Host ("Guid={0}" -f $Adapter.InterfaceGuid)

    if ($RegPath) {
        # PnPCapabilities и ASPM из реестра
        $pnp = Get-RegValueSafe -Path $RegPath -Name "PnPCapabilities"
        $aspm = Get-RegValueSafe -Path $RegPath -Name "ASPM"
        Write-Host ("PnPCapabilities={0} (target={1})" -f $(if ($null -eq $pnp -or $pnp -eq "") { "<empty>" } else { $pnp }), $script:TargetPnPCapabilities)
        Write-Host ("ASPM={0} (target=0)" -f $(if ($null -eq $aspm) { "<missing>" } else { $aspm }))
        foreach ($t in $(if ($script:ActiveTargets) { $script:ActiveTargets } else { $script:AdvTargets })) {
            $adv = Find-AdvProperty -AdapterName $Adapter.Name -Target $t
            if ($adv) {
                Write-Host ("  {0}={1}  [DisplayName={2}]" -f $adv.RegistryKeyword, ($adv.RegistryValue -join ","), $adv.DisplayName)
            } else {
                $v = Get-RegValueSafe -Path $RegPath -Name $t.RegistryKeyword
                if ($null -ne $v) {
                    Write-Host ("  {0}={1}  [REG only]" -f $t.RegistryKeyword, $v)
                }
            }
        }
    } else {
        Write-Host "WARN: NIC class registry path not found for this GUID."
    }

    # Слой cmdlet: LSO / RSC / Checksum
    try {
        $lso = Get-NetAdapterLso -Name $Adapter.Name -ErrorAction Stop
        Write-Host ("LSO IPv4Enabled={0} IPv6Enabled={1}" -f $lso.IPv4Enabled, $lso.IPv6Enabled)
    } catch {
        Write-Host "LSO: (query unavailable)"
    }
    try {
        $rsc = Get-NetAdapterRsc -Name $Adapter.Name -ErrorAction Stop
        Write-Host ("RSC IPv4Enabled={0} IPv6Enabled={1}" -f $rsc.IPv4Enabled, $rsc.IPv6Enabled)
    } catch {
        Write-Host "RSC: (query unavailable)"
    }
    try {
        $csum = Get-NetAdapterChecksumOffload -Name $Adapter.Name -ErrorAction SilentlyContinue
        if ($csum) {
            Write-Host ("ChecksumOffload present (TcpIPv4={0})" -f $csum.TcpIPv4Enabled)
        } else {
            Write-Host "ChecksumOffload: (none / disabled)"
        }
    } catch {
        Write-Host "ChecksumOffload: (query unavailable)"
    }
}

function Set-AdvOrReg {
    param(
        [string]$AdapterName,
        [string]$RegPath,
        [hashtable]$Target
    )
    # Применить одно advanced-свойство через cmdlet или напрямую в реестр
    $want = $Target.Value
    $adv = Find-AdvProperty -AdapterName $AdapterName -Target $Target
    if ($adv) {
        $kw = [string]$adv.RegistryKeyword
        $cur = ($adv.RegistryValue -join ",")
        if (Test-ValueMatches $cur $want) {
            Write-Step ("OK already ADV {0}={1} ({2})" -f $kw, $want, $adv.DisplayName)
            return
        }
        # Запись через Set-NetAdapterAdvancedProperty (без рестарта адаптера)
        Set-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $kw -RegistryValue $want -NoRestart -ErrorAction Stop
        Write-Step ("SET ADV {0}={1} — {2}" -f $kw, $want, $Target.Why)
        return
    }

    # Fallback: ключ только в реестре (свойство не в UI драйвера)
    $kw = $Target.RegistryKeyword
    $had = Get-RegValueSafe -Path $RegPath -Name $kw
    if (Test-ValueMatches $had $want) {
        Write-Step ("OK already REG {0}={1}" -f $kw, $want)
        return
    }
    New-ItemProperty -Path $RegPath -Name $kw -PropertyType String -Value $want -Force -ErrorAction Stop | Out-Null
    Write-Step ("SET REG {0}={1} — {2}" -f $kw, $want, $Target.Why)
}

# --- main ---
Write-Host "=== Apply-Lu4EthernetNic ==="
Write-Host "Lu4 NIC known-good (Ethernet desktop OR WiFi notebook)"
Write-Host "Root cause: NIC power-save/offload on the path you use — not ISP/IP."
Write-Host ""
$null = Write-Lu4OsBanner
Write-Host ""

# Apply требует Elevation
$isAdmin = Test-IsAdmin
if (-not $isAdmin) {
    Write-Host "ERROR: Run elevated (Administrator). Registry + Disable-NetAdapter* need admin."
    Write-Host "Example:"
    Write-Host '  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1'
    Write-Host '  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -Media WiFi'
    exit 1
}

# Выбрать адаптер: Auto → Ethernet если есть, иначе WiFi (ноутбук)
$resolved = Resolve-Lu4Adapter -Media $Media -Name $Name -InterfaceDescription $InterfaceDescription
$adapter = $resolved.Adapter
$mediaKind = $resolved.MediaKind
Write-Host ("Target media: {0} | Adapter: {1} | {2}" -f $mediaKind, $adapter.Name, $adapter.InterfaceDescription)

# Набор advanced-свойств зависит от среды
$targets = if ($mediaKind -eq "WiFi") { $script:WifiAdvTargets } else { $script:AdvTargets }
$script:ActiveTargets = $targets

# Ветка адаптера в реестре Class
$regPath = Get-NicRegPath -InterfaceGuid ([string]$adapter.InterfaceGuid)
if (-not $regPath) {
    Write-Host "ERROR: Could not resolve NIC class registry path for $($adapter.InterfaceGuid)"
    exit 1
}

# Состояние ДО применения
Show-AdapterState -Adapter $adapter -RegPath $regPath -Label ("BEFORE ($mediaKind)")

# Считать текущие значения и сохранить снимок ДО любых SET (не затирать при повторном Apply)
$snapPath = Get-SnapshotPath -AdapterGuid ([string]$adapter.InterfaceGuid)
$snap = New-Lu4NicSnapshot -Adapter $adapter -MediaKind $mediaKind -RegPath $regPath -Targets $targets
$null = Save-Lu4NicSnapshot -Snapshot $snap -Path $snapPath

Write-Host ""
Write-Step ("Applying known-good ONLY where current ≠ target ({0})..." -f $mediaKind)

# Точечно: только свойства, которые отличаются от known-good (Set-AdvOrReg сам skip'ает совпадения)
foreach ($t in $targets) {
    try {
        Set-AdvOrReg -AdapterName $adapter.Name -RegPath $regPath -Target $t
    } catch {
        Write-Step ("FAIL {0}: {1}" -f $t.RegistryKeyword, $_)
    }
}

# PnPCapabilities=24 — запрет отключения устройства Windows для экономии энергии
$oldPnP = Get-RegValueSafe -Path $regPath -Name "PnPCapabilities"
$pnpMsg = "PnPCapabilities '{0}' -> {1}" -f $(if ($null -eq $oldPnP -or $oldPnP -eq "") { "<empty>" } else { $oldPnP }), $script:TargetPnPCapabilities
if ([string]$oldPnP -eq [string]$script:TargetPnPCapabilities) {
    Write-Step ("OK already {0}" -f $pnpMsg)
} else {
    New-ItemProperty -Path $regPath -Name PnPCapabilities -PropertyType DWord -Value $script:TargetPnPCapabilities -Force | Out-Null
    Write-Step ("SET {0}" -f $pnpMsg)
}

# ASPM=0 — только имеет смысл на PCIe Ethernet; на WiFi best-effort
$oldAspm = Get-RegValueSafe -Path $regPath -Name "ASPM"
if ($null -eq $oldAspm) {
    Write-Step "SKIP ASPM (absent on this INF)"
} elseif ($oldAspm -eq "0") {
    Write-Step "OK already ASPM=0"
} else {
    New-ItemProperty -Path $regPath -Name ASPM -PropertyType String -Value "0" -Force | Out-Null
    Write-Step "SET ASPM=0"
}

# Если адаптер был Disabled — включить перед cmdlet-слоем
try {
    if ($adapter.Status -eq "Disabled") {
        Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 2
        $adapter = Get-NetAdapter -Name $adapter.Name
        Write-Step "Enable-NetAdapter OK"
    }
} catch {
    Write-Step ("Enable-NetAdapter: {0}" -f $_)
}

# Cmdlet: выключить Large Send Offload (если драйвер поддерживает)
try {
    Disable-NetAdapterLso -Name $adapter.Name -Confirm:$false -ErrorAction Stop
    Write-Step "Disable-NetAdapterLso OK"
} catch { Write-Step ("Disable-NetAdapterLso: {0}" -f $_) }

# Cmdlet: выключить Receive Segment Coalescing
try {
    Disable-NetAdapterRsc -Name $adapter.Name -Confirm:$false -ErrorAction Stop
    Write-Step "Disable-NetAdapterRsc OK"
} catch { Write-Step ("Disable-NetAdapterRsc: {0}" -f $_) }

# Cmdlet: выключить checksum offload
try {
    Disable-NetAdapterChecksumOffload -Name $adapter.Name -Confirm:$false -ErrorAction Stop
    Write-Step "Disable-NetAdapterChecksumOffload OK"
} catch { Write-Step ("Disable-NetAdapterChecksumOffload: {0}" -f $_) }

# Cmdlet: запретить Windows гасить NIC + отключить Wake-on-*
try {
    Set-NetAdapterPowerManagement -Name $adapter.Name `
        -AllowComputerToTurnOffDevice Disabled `
        -WakeOnMagicPacket Disabled `
        -WakeOnPattern Disabled `
        -Confirm:$false -ErrorAction Stop
    Write-Step "Set-NetAdapterPowerManagement AllowComputerToTurnOffDevice=Disabled"
} catch { Write-Step ("Set-NetAdapterPowerManagement: {0}" -f $_) }

# Опционально: выключить WiFi только на Ethernet-пути (на ноуте WiFi — сам фикс)
if ($DisableWifi) {
    if ($mediaKind -eq "WiFi") {
        Write-Step "IGNORE -DisableWifi: target media is WiFi (notebook path)."
    } else {
        Write-Host ""
        Write-Step "-DisableWifi: disabling wireless adapters (optional; NOT required for Ethernet fix)"
        $wifiList = @(
            Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
                $_.Status -ne "Not Present" -and (Test-IsWifiAdapter $_)
            }
        )
        foreach ($w in $wifiList) {
            try {
                Disable-NetAdapter -Name $w.Name -Confirm:$false -ErrorAction Stop
                Write-Step ("Disabled WiFi '{0}'" -f $w.Name)
            } catch {
                Write-Step ("Disable WiFi '{0}': {1}" -f $w.Name, $_)
            }
        }
    }
} else {
    Write-Step "Other adapters left unchanged."
}

# Состояние ПОСЛЕ применения
$adapter = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
if ($adapter) {
    Show-AdapterState -Adapter $adapter -RegPath $regPath -Label ("AFTER ($mediaKind)")
}

Write-Host ""
Write-Host "=== Done ==="
Write-Host ("Applied to: {0}" -f $mediaKind)
Write-Host ("Snapshot (for Rollback): {0}" -f $snapPath)
Write-Host "Verify Lu4: E-Net OFF → faction Black → Recommended → select Black in Servers → OK → character select."
Write-Host "(After Black is selected in the server list, press OK only — do not pick Black again.)"
Write-Host "TCP check: world :9971 Established >= 20s."
Write-Host "Rollback restores ONLY values from the snapshot (your pre-fix settings)."
Write-Host "Rollback: .\Rollback-Lu4EthernetNic.ps1   (same -Media / -Name)"
exit 0
