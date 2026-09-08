#requires -Version 5.1
<#
.SYNOPSIS
  Rollback Lu4 NIC fix using pre-Apply snapshot (Ethernet or WiFi) — surgical restore.

.DESCRIPTION
  Restores ONLY values saved by Apply-Lu4EthernetNic.ps1 in
  %LOCALAPPDATA%\fix-lu4-disconnect-win\snapshot-<GUID>.json
  Does not apply blind factory defaults (avoids wiping unrelated NIC settings).
  Works for desktop Ethernet and notebook WiFi (-Media Auto|Ethernet|WiFi).
  Exit: 0 = done; 1 = no snapshot / not admin / no adapter.

.PARAMETER Media
  Auto (default) | Ethernet | WiFi — same selection rules as Apply.

.PARAMETER Name
  NetAdapter Name.

.PARAMETER InterfaceDescription
  Match InterfaceDescription.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1 -Media WiFi
#>
[CmdletBinding()]
param(
    [ValidateSet("Auto", "Ethernet", "WiFi")]
    [string]$Media = "Auto",
    [string]$Name,
    [string]$InterfaceDescription
)

# Продолжать при некритичных ошибках отдельных свойств
$ErrorActionPreference = "Continue"

# Путь класса сетевых адаптеров в реестре Windows
$script:NicClassPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
# PnPCapabilities=0 — типичный default (галка «разрешить отключение…» снова доступна)
$script:TargetPnPCapabilities = 0

# Типичные defaults: keyword → значение ON + алиасы INF
$script:AdvTargets = @(
    @{
        RegistryKeyword = "*EEE"
        AltKeywords     = @("EEE", "*EnergyEfficientEthernet")
        DisplayNames    = @("*Energy-Efficient Ethernet*", "*Energy Efficient Ethernet*", "*Энергоэффективный Ethernet*", "*EEE*")
        Value           = "1"
        Why             = "EEE ON — типичный default"
    }
    @{
        RegistryKeyword = "*EEELinkAdvertisement"
        AltKeywords     = @("EEELinkAdvertisement")
        DisplayNames    = @("*EEE Link Advertisement*", "*EEE*Advert*", "*Реклам*EEE*", "*Объявлен*EEE*")
        Value           = "1"
        Why             = "EEE Link Advertisement ON"
    }
    @{
        RegistryKeyword = "*GreenEthernet"
        AltKeywords     = @("GreenEthernet", "*Green*")
        DisplayNames    = @("*Green Ethernet*", "*Зелёный Ethernet*", "*Зеленый Ethernet*", "*Энергосберегающий Ethernet*")
        Value           = "1"
        Why             = "Green Ethernet ON"
    }
    @{
        RegistryKeyword = "GreenEthernet"
        AltKeywords     = @()
        DisplayNames    = @()
        Value           = "1"
        Why             = "Legacy GreenEthernet=1"
    }
    @{
        RegistryKeyword = "*SelectiveSuspend"
        AltKeywords     = @("SelectiveSuspend", "*SS*")
        DisplayNames    = @("*Selective Suspend*", "*Выборочная приостановка*", "*Селективн*")
        Value           = "1"
        Why             = "Selective Suspend ON"
    }
    @{
        RegistryKeyword = "*IdlePowerDown"
        AltKeywords     = @("IdlePowerDown")
        DisplayNames    = @("*Idle Power*", "*Простой*питан*", "*Idle*Down*")
        Value           = "1"
        Why             = "Idle Power Down ON"
    }
    @{
        RegistryKeyword = "*LsoV2IPv4"
        AltKeywords     = @("*LSO*IPv4*", "*LsoV2*IPv4*")
        DisplayNames    = @("*Large Send Offload*v2*IPv4*", "*LSO*v2*IPv4*", "*Большой объем отправки*IPv4*", "*Большой объём отправки*IPv4*")
        Value           = "1"
        Why             = "LSO v2 IPv4 ON"
    }
    @{
        RegistryKeyword = "*LsoV2IPv6"
        AltKeywords     = @("*LSO*IPv6*", "*LsoV2*IPv6*")
        DisplayNames    = @("*Large Send Offload*v2*IPv6*", "*LSO*v2*IPv6*", "*Большой объем отправки*IPv6*", "*Большой объём отправки*IPv6*")
        Value           = "1"
        Why             = "LSO v2 IPv6 ON"
    }
    @{
        RegistryKeyword = "*RscIPv4"
        AltKeywords     = @("*RSC*IPv4*", "*RecvSegmentCoalescing*IPv4*")
        DisplayNames    = @("*Recv Segment Coalescing*IPv4*", "*Receive Segment Coalescing*IPv4*", "*RSC*IPv4*", "*Объединение сегментов*IPv4*")
        Value           = "1"
        Why             = "RSC IPv4 ON"
    }
    @{
        RegistryKeyword = "*RscIPv6"
        AltKeywords     = @("*RSC*IPv6*", "*RecvSegmentCoalescing*IPv6*")
        DisplayNames    = @("*Recv Segment Coalescing*IPv6*", "*Receive Segment Coalescing*IPv6*", "*RSC*IPv6*", "*Объединение сегментов*IPv6*")
        Value           = "1"
        Why             = "RSC IPv6 ON"
    }
    @{
        RegistryKeyword = "*TCPChecksumOffloadIPv4"
        AltKeywords     = @("*TCPChecksum*IPv4*")
        DisplayNames    = @("*TCP Checksum Offload*IPv4*", "*TCP*контрольной суммы*IPv4*", "*Проверка контрольной суммы TCP*IPv4*")
        Value           = "3"
        Why             = "TCP checksum Rx&Tx Enabled (типично 3)"
    }
    @{
        RegistryKeyword = "*TCPChecksumOffloadIPv6"
        AltKeywords     = @("*TCPChecksum*IPv6*")
        DisplayNames    = @("*TCP Checksum Offload*IPv6*", "*TCP*контрольной суммы*IPv6*", "*Проверка контрольной суммы TCP*IPv6*")
        Value           = "3"
        Why             = "TCP checksum Rx&Tx Enabled"
    }
    @{
        RegistryKeyword = "*UDPChecksumOffloadIPv4"
        AltKeywords     = @("*UDPChecksum*IPv4*")
        DisplayNames    = @("*UDP Checksum Offload*IPv4*", "*UDP*контрольной суммы*IPv4*", "*Проверка контрольной суммы UDP*IPv4*")
        Value           = "3"
        Why             = "UDP checksum Rx&Tx Enabled"
    }
    @{
        RegistryKeyword = "*UDPChecksumOffloadIPv6"
        AltKeywords     = @("*UDPChecksum*IPv6*")
        DisplayNames    = @("*UDP Checksum Offload*IPv6*", "*UDP*контрольной суммы*IPv6*", "*Проверка контрольной суммы UDP*IPv6*")
        Value           = "3"
        Why             = "UDP checksum Rx&Tx Enabled"
    }
    @{
        RegistryKeyword = "*IPChecksumOffloadIPv4"
        AltKeywords     = @("*IPChecksumOffload*", "*IPChecksum*")
        DisplayNames    = @("*IP Checksum Offload*", "*IP*контрольной суммы*", "*Проверка контрольной суммы IP*")
        Value           = "3"
        Why             = "IP checksum Rx&Tx Enabled"
    }
)

# WiFi rollback: типичные «включено» для power-save ключей
$script:WifiAdvTargets = @(
    @{
        RegistryKeyword = "*PowerSaveMode"
        AltKeywords     = @("PowerSaveMode", "*PMWiFi", "*WiFiPower*", "*WirelessPower*")
        DisplayNames    = @("*Power Saving*", "*Режим энергосбережения*", "*Энергосбережение*", "*Power Save*")
        Value           = "1"
        Why             = "WiFi Power Saving ON (типичный default)"
    }
    @{
        RegistryKeyword = "*DeviceSleepOnDisconnect"
        AltKeywords     = @("DeviceSleepOnDisconnect")
        DisplayNames    = @("*Sleep*Disconnect*", "*Сон*отключ*", "*Device Sleep*")
        Value           = "1"
        Why             = "Device Sleep On Disconnect ON"
    }
    @{
        RegistryKeyword = "*uAPSDSupport"
        AltKeywords     = @("*uAPSD*", "uAPSD")
        DisplayNames    = @("*uAPSD*", "*U-APSD*")
        Value           = "1"
        Why             = "uAPSD ON"
    }
    @{
        RegistryKeyword = "*RoamingAggressiveness"
        AltKeywords     = @("RoamingAggressiveness", "*Roaming*")
        DisplayNames    = @("*Roaming Aggressiveness*", "*Агрессивность роуминга*")
        Value           = "2"
        Why             = "Roaming medium (типично 2)"
    }
    @{
        RegistryKeyword = "*SelectiveSuspend"
        AltKeywords     = @("SelectiveSuspend")
        DisplayNames    = @("*Selective Suspend*", "*Выборочная приостановка*")
        Value           = "1"
        Why             = "Selective Suspend ON"
    }
    @{
        RegistryKeyword = "*IdlePowerDown"
        AltKeywords     = @("IdlePowerDown")
        DisplayNames    = @("*Idle Power*", "*Простой*питан*")
        Value           = "1"
        Why             = "Idle Power Down ON"
    }
    @{
        RegistryKeyword = "*LsoV2IPv4"
        AltKeywords     = @("*LSO*IPv4*")
        DisplayNames    = @("*Large Send Offload*IPv4*", "*LSO*IPv4*")
        Value           = "1"
        Why             = "LSO ON"
    }
    @{
        RegistryKeyword = "*LsoV2IPv6"
        AltKeywords     = @("*LSO*IPv6*")
        DisplayNames    = @("*Large Send Offload*IPv6*", "*LSO*IPv6*")
        Value           = "1"
        Why             = "LSO v2 IPv6 ON"
    }
    @{
        RegistryKeyword = "*RscIPv4"
        AltKeywords     = @("*RSC*IPv4*")
        DisplayNames    = @("*Recv Segment Coalescing*IPv4*", "*RSC*IPv4*")
        Value           = "1"
        Why             = "RSC ON"
    }
    @{
        RegistryKeyword = "*RscIPv6"
        AltKeywords     = @("*RSC*IPv6*")
        DisplayNames    = @("*Recv Segment Coalescing*IPv6*", "*RSC*IPv6*")
        Value           = "1"
        Why             = "RSC IPv6 ON"
    }
    @{
        RegistryKeyword = "*TCPChecksumOffloadIPv4"
        AltKeywords     = @("*TCPChecksum*IPv4*")
        DisplayNames    = @("*TCP Checksum Offload*IPv4*")
        Value           = "3"
        Why             = "TCP checksum Rx&Tx"
    }
    @{
        RegistryKeyword = "*TCPChecksumOffloadIPv6"
        AltKeywords     = @("*TCPChecksum*IPv6*")
        DisplayNames    = @("*TCP Checksum Offload*IPv6*")
        Value           = "3"
        Why             = "TCP checksum IPv6 Rx&Tx"
    }
    @{
        RegistryKeyword = "*UDPChecksumOffloadIPv4"
        AltKeywords     = @("*UDPChecksum*IPv4*")
        DisplayNames    = @("*UDP Checksum Offload*IPv4*")
        Value           = "3"
        Why             = "UDP checksum Rx&Tx"
    }
    @{
        RegistryKeyword = "*UDPChecksumOffloadIPv6"
        AltKeywords     = @("*UDPChecksum*IPv6*")
        DisplayNames    = @("*UDP Checksum Offload*IPv6*")
        Value           = "3"
        Why             = "UDP checksum IPv6 Rx&Tx"
    }
    @{
        RegistryKeyword = "*IPChecksumOffloadIPv4"
        AltKeywords     = @("*IPChecksum*")
        DisplayNames    = @("*IP Checksum Offload*")
        Value           = "3"
        Why             = "IP checksum Rx&Tx"
    }
)

function Get-Lu4OsInfo {
    # Считать версию ОС
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
    # Показать баннер ОС
    $os = Get-Lu4OsInfo
    Write-Host ("OS: {0} | Family={1} | Version={2} | Build={3} | Arch={4}" -f `
        $os.Caption, $os.Family, $os.Version, $os.Build, $os.Architecture)
    return $os
}

function Test-IsAdmin {
    # Проверка прав администратора
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
    # Heuristic: WiFi / Wireless / 802.11
    return (
        $Adapter.InterfaceDescription -match "Wireless|Wi-?Fi|802\.11|WLAN" -or
        $Adapter.Name -match "Wi-?Fi|WLAN|Беспровод" -or
        $Adapter.MediaType -match "Native 802.11|Wireless"
    )
}

function Test-IsEthernetAdapter {
    param($Adapter)
    # Heuristic: проводной Ethernet
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

    # Явный -Name
    if ($Name) {
        $hit = $all | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if (-not $hit) { throw "Adapter Name='$Name' not found." }
        return [pscustomobject]@{ Adapter = $hit; MediaKind = $(if (Test-IsWifiAdapter $hit) { "WiFi" } else { "Ethernet" }) }
    }

    # Явный InterfaceDescription
    if ($InterfaceDescription) {
        $hit = $all | Where-Object { $_.InterfaceDescription -like "*$InterfaceDescription*" } | Select-Object -First 1
        if (-not $hit) { throw "Adapter InterfaceDescription matching '$InterfaceDescription' not found." }
        return [pscustomobject]@{ Adapter = $hit; MediaKind = $(if (Test-IsWifiAdapter $hit) { "WiFi" } else { "Ethernet" }) }
    }

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
            throw "Multiple Realtek Ethernet — pass -Name."
        }
        if ($ethAny.Count -eq 1) {
            return [pscustomobject]@{ Adapter = $ethAny[0]; MediaKind = "Ethernet" }
        }
        if ($ethAny.Count -gt 1) { throw "Multiple Ethernet — pass -Name." }
        throw "Ethernet requested but no wired adapter. Use -Media WiFi."
    }

    if ($kind -eq "WiFi") {
        if ($wifiAny.Count -eq 0) { throw "WiFi requested but no wireless adapter found." }
        $up = @($wifiAny | Where-Object { $_.Status -eq "Up" })
        $pick = if ($up.Count -ge 1) { $up[0] } else { $wifiAny[0] }
        return [pscustomobject]@{ Adapter = $pick; MediaKind = "WiFi" }
    }

    throw "Unknown Media='$Media'"
}

function Get-NicRegPath {
    param([string]$InterfaceGuid)
    # Найти ветку Class по NetCfgInstanceId
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
    # Безопасное чтение значения реестра
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

    # Все advanced-свойства для поиска по алиасам
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

    # Мягкий поиск по stem
    $stem = $kw.TrimStart("*")
    if ($stem.Length -ge 3) {
        $hit = $all | Where-Object { $_.RegistryKeyword -like "*$stem*" } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

function Test-ValueMatches {
    param($Raw, [string]$Want)
    # Сравнить текущее значение с целевым
    if ($null -eq $Raw) { return $false }
    $s = ([string]$Raw).Trim()
    if ($s -eq $Want) { return $true }
    return $false
}

function Show-AdapterState {
    param($Adapter, [string]$RegPath, [string]$Label)

    # Дамп состояния адаптера
    Write-Host ""
    Write-Host "======== $Label ========"
    Write-Host ("Name={0}" -f $Adapter.Name)
    Write-Host ("Desc={0}" -f $Adapter.InterfaceDescription)
    Write-Host ("Status={0} Link={1} IfIndex={2}" -f $Adapter.Status, $Adapter.LinkSpeed, $Adapter.ifIndex)

    if ($RegPath) {
        # PnPCapabilities и ASPM
        $pnp = Get-RegValueSafe -Path $RegPath -Name "PnPCapabilities"
        $aspm = Get-RegValueSafe -Path $RegPath -Name "ASPM"
        Write-Host ("PnPCapabilities={0} (rollback target={1})" -f $(if ($null -eq $pnp -or $pnp -eq "") { "<empty>" } else { $pnp }), $script:TargetPnPCapabilities)
        Write-Host ("ASPM={0} (rollback target=1)" -f $(if ($null -eq $aspm) { "<missing>" } else { $aspm }))
    }
}

function Set-AdvOrReg {
    param(
        [string]$AdapterName,
        [string]$RegPath,
        [hashtable]$Target
    )
    # Восстановить одно advanced-свойство к типичному default
    $want = $Target.Value
    $adv = Find-AdvProperty -AdapterName $AdapterName -Target $Target
    if ($adv) {
        $kw = [string]$adv.RegistryKeyword
        $cur = ($adv.RegistryValue -join ",")
        if (Test-ValueMatches $cur $want) {
            Write-Step ("OK already ADV {0}={1}" -f $kw, $want)
            return
        }
        # Запись через Set-NetAdapterAdvancedProperty
        Set-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $kw -RegistryValue $want -NoRestart -ErrorAction Stop
        Write-Step ("SET ADV {0}={1} — {2}" -f $kw, $want, $Target.Why)
        return
    }

    # Fallback в реестр, если ключ уже есть
    $kw = $Target.RegistryKeyword
    $had = Get-RegValueSafe -Path $RegPath -Name $kw
    if ($null -eq $had) {
        Write-Step ("SKIP REG {0} (absent on this INF)" -f $kw)
        return
    }
    if (Test-ValueMatches $had $want) {
        Write-Step ("OK already REG {0}={1}" -f $kw, $want)
        return
    }
    New-ItemProperty -Path $RegPath -Name $kw -PropertyType String -Value $want -Force -ErrorAction Stop | Out-Null
    Write-Step ("SET REG {0}={1} — {2}" -f $kw, $want, $Target.Why)
}

# --- main ---
Write-Host "=== Rollback-Lu4EthernetNic ==="
Write-Host "Restore PRE-FIX values from snapshot (Ethernet or WiFi notebook)."
Write-Host "Does NOT wipe unrelated NIC settings — only keys saved by Apply."
Write-Host ""
$null = Write-Lu4OsBanner
Write-Host ""

# Rollback требует Elevation
$isAdmin = Test-IsAdmin
if (-not $isAdmin) {
    Write-Host "ERROR: Run elevated (Administrator)."
    Write-Host '  powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1'
    exit 1
}

# Тот же выбор адаптера, что у Apply (Auto / Ethernet / WiFi)
$resolved = Resolve-Lu4Adapter -Media $Media -Name $Name -InterfaceDescription $InterfaceDescription
$adapter = $resolved.Adapter
$mediaKind = $resolved.MediaKind
Write-Host ("Target media: {0} | Adapter: {1}" -f $mediaKind, $adapter.Name)

$regPath = Get-NicRegPath -InterfaceGuid ([string]$adapter.InterfaceGuid)
if (-not $regPath) {
    Write-Host "ERROR: Could not resolve NIC class registry path for $($adapter.InterfaceGuid)"
    exit 1
}

# Путь снимка, созданного Apply до изменений
$guidSafe = ($adapter.InterfaceGuid.Trim("{}") -replace "[^A-Fa-f0-9\-]", "")
$snapDir = Join-Path $env:LOCALAPPDATA "fix-lu4-disconnect-win"
$snapPath = Join-Path $snapDir ("snapshot-{0}.json" -f $guidSafe)

# Без снимка откат не угадывает «типичные» defaults — чтобы не сбить чужие настройки
if (-not (Test-Path -LiteralPath $snapPath)) {
    Write-Host "ERROR: Snapshot not found:"
    Write-Host "  $snapPath"
    Write-Host "Run Apply-Lu4EthernetNic.ps1 first (it saves pre-fix values). Refusing blind factory rollback."
    exit 1
}

# Прочитать снимок до-фикса
Write-Step ("Loading snapshot: {0}" -f $snapPath)
$snap = Get-Content -LiteralPath $snapPath -Raw -Encoding UTF8 | ConvertFrom-Json

Show-AdapterState -Adapter $adapter -RegPath $regPath -Label ("BEFORE ROLLBACK ($mediaKind)")

Write-Host ""
Write-Step "Restoring ONLY snapshot previousValue (surgical)..."

# Вернуть каждое advanced/reg свойство к previousValue из снимка
foreach ($p in @($snap.properties)) {
    if (-not $p.present) {
        Write-Step ("SKIP {0} (was absent)" -f $p.registryKeyword)
        continue
    }
    $prev = [string]$p.previousValue
    if ($null -eq $p.previousValue -or $prev -eq "") {
        Write-Step ("SKIP {0} (empty previous)" -f $p.registryKeyword)
        continue
    }
    try {
        # Попытка через AdvancedProperty API
        $adv = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $p.registryKeyword -ErrorAction SilentlyContinue
        if ($adv) {
            $cur = ($adv.RegistryValue -join ",")
            if ($cur -eq $prev) {
                Write-Step ("OK already ADV {0}={1}" -f $p.registryKeyword, $prev)
            } else {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $p.registryKeyword -RegistryValue $prev -NoRestart -ErrorAction Stop
                Write-Step ("RESTORE ADV {0}={1}" -f $p.registryKeyword, $prev)
            }
        } else {
            # Fallback в реестр Class
            $had = $null
            try { $had = (Get-ItemProperty -Path $regPath -Name $p.registryKeyword -ErrorAction Stop).($p.registryKeyword) } catch {}
            if ([string]$had -eq $prev) {
                Write-Step ("OK already REG {0}={1}" -f $p.registryKeyword, $prev)
            } else {
                New-ItemProperty -Path $regPath -Name $p.registryKeyword -PropertyType String -Value $prev -Force -ErrorAction Stop | Out-Null
                Write-Step ("RESTORE REG {0}={1}" -f $p.registryKeyword, $prev)
            }
        }
    } catch {
        Write-Step ("FAIL restore {0}: {1}" -f $p.registryKeyword, $_)
    }
}

# PnPCapabilities из снимка
if ($snap.registry -and $snap.registry.PnPCapabilities) {
    $prevPnP = $snap.registry.PnPCapabilities.previous
    if ($null -ne $prevPnP -and [string]$prevPnP -ne "") {
        try {
            $val = [int]$prevPnP
            New-ItemProperty -Path $regPath -Name PnPCapabilities -PropertyType DWord -Value $val -Force | Out-Null
            Write-Step ("RESTORE PnPCapabilities={0}" -f $val)
        } catch {
            Write-Step ("FAIL PnPCapabilities: {0}" -f $_)
        }
    } else {
        # Если до фикса ключа не было — удалить наш 24
        try {
            Remove-ItemProperty -Path $regPath -Name PnPCapabilities -ErrorAction Stop
            Write-Step "REMOVE PnPCapabilities (was empty before Apply)"
        } catch {
            Write-Step ("PnPCapabilities cleanup: {0}" -f $_)
        }
    }
}

# ASPM из снимка
if ($snap.registry -and $snap.registry.ASPM -and $snap.registry.ASPM.present) {
    $prevAspm = [string]$snap.registry.ASPM.previous
    if ($prevAspm -ne "") {
        try {
            New-ItemProperty -Path $regPath -Name ASPM -PropertyType String -Value $prevAspm -Force | Out-Null
            Write-Step ("RESTORE ASPM={0}" -f $prevAspm)
        } catch {
            Write-Step ("FAIL ASPM: {0}" -f $_)
        }
    }
}

# Включить адаптер если Disabled
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

# Cmdlet LSO/RSC/Checksum по снимку (если знали предыдущее состояние)
if ($snap.cmdlets) {
    $lso = $snap.cmdlets.Lso
    if ($null -ne $lso -and $null -ne $lso.ipv4) {
        try {
            if ($lso.ipv4 -or $lso.ipv6) {
                Enable-NetAdapterLso -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Write-Step "RESTORE Enable-NetAdapterLso (was enabled)"
            } else {
                Disable-NetAdapterLso -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Write-Step "RESTORE Disable-NetAdapterLso (was disabled)"
            }
        } catch { Write-Step ("LSO restore: {0}" -f $_) }
    }
    $rsc = $snap.cmdlets.Rsc
    if ($null -ne $rsc -and $null -ne $rsc.ipv4) {
        try {
            if ($rsc.ipv4 -or $rsc.ipv6) {
                Enable-NetAdapterRsc -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Write-Step "RESTORE Enable-NetAdapterRsc (was enabled)"
            } else {
                Disable-NetAdapterRsc -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Write-Step "RESTORE Disable-NetAdapterRsc (was disabled)"
            }
        } catch { Write-Step ("RSC restore: {0}" -f $_) }
    }
    if ($null -ne $snap.cmdlets.ChecksumPresent) {
        try {
            if ($snap.cmdlets.ChecksumPresent) {
                Enable-NetAdapterChecksumOffload -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Write-Step "RESTORE Enable-NetAdapterChecksumOffload"
            } else {
                Disable-NetAdapterChecksumOffload -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Write-Step "RESTORE Disable-NetAdapterChecksumOffload"
            }
        } catch { Write-Step ("Checksum restore: {0}" -f $_) }
    }
}

# Power management: после отката снова разрешить (типично до фикса) — только если снимок не хранит иначе
try {
    Set-NetAdapterPowerManagement -Name $adapter.Name `
        -AllowComputerToTurnOffDevice Enabled `
        -Confirm:$false -ErrorAction Stop
    Write-Step "Set-NetAdapterPowerManagement AllowComputerToTurnOffDevice=Enabled"
} catch { Write-Step ("Set-NetAdapterPowerManagement: {0}" -f $_) }

$adapter = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
if ($adapter) {
    Show-AdapterState -Adapter $adapter -RegPath $regPath -Label ("AFTER ROLLBACK ($mediaKind)")
}

Write-Host ""
Write-Host "=== Done ==="
Write-Host ("Rolled back from snapshot: {0}" -f $snapPath)
Write-Host "Re-apply: .\Apply-Lu4EthernetNic.ps1  (-Media WiFi on notebooks)"
exit 0
