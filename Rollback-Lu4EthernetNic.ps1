#requires -Version 5.1
<#
.SYNOPSIS
  Rollback Realtek Ethernet NIC to typical defaults (undo Apply-Lu4EthernetNic).

.DESCRIPTION
  Restores typical Realtek/Windows defaults: EEE/Green ON, LSO/RSC/checksum ON,
  SelectiveSuspend/IdlePowerDown ON, ASPM=1, PnPCapabilities=0,
  AllowComputerToTurnOffDevice Enabled.
  WARNING: may bring back Lu4 Ethernet disconnect on world :9971.
  Companion: Apply-Lu4EthernetNic.ps1 | Targets: settings.rollback-defaults.json
  Exit: 0 = done; 1 = missing adapter or needs admin.

.PARAMETER Name
  NetAdapter Name (default: auto-detect Realtek Ethernet).

.PARAMETER InterfaceDescription
  Match InterfaceDescription.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Rollback-Lu4EthernetNic.ps1
#>
[CmdletBinding()]
param(
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

function Resolve-EthernetAdapter {
    param([string]$Name, [string]$InterfaceDescription)

    # Список присутствующих адаптеров
    $all = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -ne "Not Present" })

    # Явный выбор по -Name
    if ($Name) {
        $hit = $all | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if (-not $hit) { throw "Adapter Name='$Name' not found." }
        return $hit
    }

    # Явный выбор по описанию интерфейса
    if ($InterfaceDescription) {
        $hit = $all | Where-Object { $_.InterfaceDescription -like "*$InterfaceDescription*" } | Select-Object -First 1
        if (-not $hit) { throw "Adapter InterfaceDescription matching '$InterfaceDescription' not found." }
        return $hit
    }

    # Авто-поиск Realtek Ethernet
    $eth = @(
        $all | Where-Object {
            $_.InterfaceDescription -match "Realtek.*GbE|Realtek.*Ethernet|PCIe GbE" -and
            $_.InterfaceDescription -notmatch "Wireless|Wi-?Fi|802\.11|Bluetooth"
        }
    )
    if ($eth.Count -eq 1) { return $eth[0] }
    if ($eth.Count -gt 1) {
        Write-Host "Multiple Realtek Ethernet adapters:"
        $eth | ForEach-Object { Write-Host ("  - Name={0} Desc={1} Status={2}" -f $_.Name, $_.InterfaceDescription, $_.Status) }
        throw "Pass -Name or -InterfaceDescription to select one."
    }

    # Fallback: единственный проводной адаптер
    $wired = @(
        $all | Where-Object {
            $_.MediaType -eq "802.3" -or
            ($_.InterfaceDescription -match "Ethernet|GbE|LAN" -and $_.InterfaceDescription -notmatch "Wireless|Wi-?Fi|802\.11|Bluetooth|Virtual|Hyper-V|vEthernet")
        }
    )
    if ($wired.Count -eq 1) {
        Write-Host "WARN: Realtek not matched; using single wired adapter: $($wired[0].Name)"
        return $wired[0]
    }

    Write-Host "Available adapters:"
    $all | ForEach-Object { Write-Host ("  - Name={0} Desc={1} Status={2}" -f $_.Name, $_.InterfaceDescription, $_.Status) }
    throw "Could not auto-detect Ethernet. Use -Name or -InterfaceDescription."
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
Write-Host "Restore typical Realtek Ethernet defaults (undo known-good Apply)."
Write-Host "WARNING: may bring back Lu4 disconnect on Ethernet world :9971."
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

# Найти Ethernet-адаптер и ветку реестра
$adapter = Resolve-EthernetAdapter -Name $Name -InterfaceDescription $InterfaceDescription
$regPath = Get-NicRegPath -InterfaceGuid ([string]$adapter.InterfaceGuid)
if (-not $regPath) {
    Write-Host "ERROR: Could not resolve NIC class registry path for $($adapter.InterfaceGuid)"
    exit 1
}

# Состояние ДО отката
Show-AdapterState -Adapter $adapter -RegPath $regPath -Label "BEFORE ROLLBACK"

Write-Host ""
Write-Step "Restoring typical defaults..."

# Включить advanced-свойства к типичным defaults
foreach ($t in $script:AdvTargets) {
    try {
        Set-AdvOrReg -AdapterName $adapter.Name -RegPath $regPath -Target $t
    } catch {
        Write-Step ("FAIL {0}: {1}" -f $t.RegistryKeyword, $_)
    }
}

# PnPCapabilities=0 — снова разрешить отключение для экономии энергии
$oldPnP = Get-RegValueSafe -Path $regPath -Name "PnPCapabilities"
$pnpMsg = "PnPCapabilities '{0}' -> {1}" -f $(if ($null -eq $oldPnP -or $oldPnP -eq "") { "<empty>" } else { $oldPnP }), $script:TargetPnPCapabilities
if ([string]$oldPnP -eq [string]$script:TargetPnPCapabilities) {
    Write-Step ("OK already {0}" -f $pnpMsg)
} else {
    New-ItemProperty -Path $regPath -Name PnPCapabilities -PropertyType DWord -Value $script:TargetPnPCapabilities -Force | Out-Null
    Write-Step ("SET {0}" -f $pnpMsg)
}

# ASPM=1 — типичный enabled
$oldAspm = Get-RegValueSafe -Path $regPath -Name "ASPM"
if ($oldAspm -eq "1") {
    Write-Step "OK already ASPM=1"
} else {
    New-ItemProperty -Path $regPath -Name ASPM -PropertyType String -Value "1" -Force | Out-Null
    Write-Step "SET ASPM=1"
}

# Если адаптер Disabled — включить перед Enable-cmdlets
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

# Cmdlet: включить Large Send Offload
try {
    Enable-NetAdapterLso -Name $adapter.Name -Confirm:$false -ErrorAction Stop
    Write-Step "Enable-NetAdapterLso OK"
} catch { Write-Step ("Enable-NetAdapterLso: {0}" -f $_) }

# Cmdlet: включить Receive Segment Coalescing
try {
    Enable-NetAdapterRsc -Name $adapter.Name -Confirm:$false -ErrorAction Stop
    Write-Step "Enable-NetAdapterRsc OK"
} catch { Write-Step ("Enable-NetAdapterRsc: {0}" -f $_) }

# Cmdlet: включить checksum offload
try {
    Enable-NetAdapterChecksumOffload -Name $adapter.Name -Confirm:$false -ErrorAction Stop
    Write-Step "Enable-NetAdapterChecksumOffload OK"
} catch { Write-Step ("Enable-NetAdapterChecksumOffload: {0}" -f $_) }

# Cmdlet: снова разрешить Windows гасить NIC
try {
    Set-NetAdapterPowerManagement -Name $adapter.Name `
        -AllowComputerToTurnOffDevice Enabled `
        -Confirm:$false -ErrorAction Stop
    Write-Step "Set-NetAdapterPowerManagement AllowComputerToTurnOffDevice=Enabled"
} catch { Write-Step ("Set-NetAdapterPowerManagement: {0}" -f $_) }

# Состояние ПОСЛЕ отката
$adapter = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
if ($adapter) {
    Show-AdapterState -Adapter $adapter -RegPath $regPath -Label "AFTER ROLLBACK"
}

Write-Host ""
Write-Host "=== Done ==="
Write-Host "Typical defaults restored. Re-apply fix: .\Apply-Lu4EthernetNic.ps1"
exit 0
