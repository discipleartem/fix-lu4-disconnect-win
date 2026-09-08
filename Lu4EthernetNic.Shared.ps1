<#
.SYNOPSIS
  Shared known-good Ethernet NIC targets + helpers for Lu4 cold-login fix.
.DESCRIPTION
  RU: Общие цели настроек и хелперы для Apply-Lu4EthernetNic / Test-Lu4EthernetNic (Win10+Win11).
  EN: Shared targets and helpers used by Apply and Test scripts on Windows 10 and 11.
#>

$script:NicClassPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
# PnPCapabilities=24 (0x18): forbid "allow computer to turn off this device" (+ related wake bits in known-good).
# RU docs: docs/SETTINGS-EXPLAINED.ru.md
$script:TargetPnPCapabilities = 24

# Registry keywords from known-good capture (ethernet-fix SUCCESS 2026-09-08).
# DisplayNamePatterns: RU/EN UI labels for Get-NetAdapterAdvancedProperty fallback when keyword missing.
# WHY one-liners for Apply logs; full RU explanations: docs/SETTINGS-EXPLAINED.ru.md
# Context: Lu4 world TCP :9971 Established ~2s then drop after server OK on Ethernet cold path.
$script:AdvTargets = @(
    @{
        RegistryKeyword = "*EEE"
        AltKeywords     = @("EEE", "*EnergyEfficientEthernet")
        DisplayNames    = @("*Energy-Efficient Ethernet*", "*Energy Efficient Ethernet*", "*Энергоэффективный Ethernet*", "*EEE*")
        Value           = "0"
        Why             = "EEE OFF — NIC link power-save can stall/reset Lu4 world TCP :9971 (~2s drop on Ethernet)"
    }
    @{
        RegistryKeyword = "*EEELinkAdvertisement"
        AltKeywords     = @("EEELinkAdvertisement")
        DisplayNames    = @("*EEE Link Advertisement*", "*EEE*Advert*", "*Реклама*EEE*", "*Объявлен*EEE*")
        Value           = "0"
        Why             = "EEE Link Advertisement OFF — companion to full EEE disable"
    }
    @{
        RegistryKeyword = "*GreenEthernet"
        AltKeywords     = @("GreenEthernet", "*Green*")
        DisplayNames    = @("*Green Ethernet*", "*Зелёный Ethernet*", "*Зеленый Ethernet*", "*Энергосберегающий Ethernet*")
        Value           = "0"
        Why             = "Green Ethernet OFF — Realtek cable/power gating; same class as EEE vs short :9971"
    }
    @{
        RegistryKeyword = "GreenEthernet"
        AltKeywords     = @()
        DisplayNames    = @()
        Value           = "0"
        Why             = "Legacy GreenEthernet=0 (some Realtek INF use non-star keyword)"
    }
    @{
        RegistryKeyword = "*SelectiveSuspend"
        AltKeywords     = @("SelectiveSuspend", "*SS*")
        DisplayNames    = @("*Selective Suspend*", "*Выборочная приостановка*", "*Селективн*")
        Value           = "0"
        Why             = "Selective Suspend OFF — NIC sleep in login→world gap can drop :9971"
    }
    @{
        RegistryKeyword = "*IdlePowerDown"
        AltKeywords     = @("IdlePowerDown")
        DisplayNames    = @("*Idle Power*", "*Простой*питан*", "*Idle*Down*")
        Value           = "0"
        Why             = "Idle Power Down OFF — sleep between packets breaks short world handshake"
    }
    @{
        RegistryKeyword = "*LsoV2IPv4"
        AltKeywords     = @("*LSO*IPv4*", "*LsoV2*IPv4*")
        DisplayNames    = @("*Large Send Offload*v2*IPv4*", "*LSO*v2*IPv4*", "*Большой объем отправки*IPv4*", "*Большой объём отправки*IPv4*")
        Value           = "0"
        Why             = "LSO v2 IPv4 OFF — HW segmentation can corrupt/delay game TCP on Realtek"
    }
    @{
        RegistryKeyword = "*LsoV2IPv6"
        AltKeywords     = @("*LSO*IPv6*", "*LsoV2*IPv6*")
        DisplayNames    = @("*Large Send Offload*v2*IPv6*", "*LSO*v2*IPv6*", "*Большой объем отправки*IPv6*", "*Большой объём отправки*IPv6*")
        Value           = "0"
        Why             = "LSO v2 IPv6 OFF — same Realtek HW-segmentation risk as IPv4"
    }
    @{
        RegistryKeyword = "*RscIPv4"
        AltKeywords     = @("*RSC*IPv4*", "*RecvSegmentCoalescing*IPv4*")
        DisplayNames    = @("*Recv Segment Coalescing*IPv4*", "*Receive Segment Coalescing*IPv4*", "*RSC*IPv4*", "*Объединение сегментов*IPv4*")
        Value           = "0"
        Why             = "RSC IPv4 OFF — RX coalesce can break timing-sensitive Lu4 :9971"
    }
    @{
        RegistryKeyword = "*RscIPv6"
        AltKeywords     = @("*RSC*IPv6*", "*RecvSegmentCoalescing*IPv6*")
        DisplayNames    = @("*Recv Segment Coalescing*IPv6*", "*Receive Segment Coalescing*IPv6*", "*RSC*IPv6*", "*Объединение сегментов*IPv6*")
        Value           = "0"
        Why             = "RSC IPv6 OFF — same RX-coalesce risk as IPv4"
    }
    @{
        RegistryKeyword = "*TCPChecksumOffloadIPv4"
        AltKeywords     = @("*TCPChecksum*IPv4*")
        DisplayNames    = @("*TCP Checksum Offload*IPv4*", "*TCP*контрольной суммы*IPv4*", "*Проверка контрольной суммы TCP*IPv4*")
        Value           = "0"
        Why             = "TCP checksum OFF IPv4 — HW checksum bugs on some Realtek drivers"
    }
    @{
        RegistryKeyword = "*TCPChecksumOffloadIPv6"
        AltKeywords     = @("*TCPChecksum*IPv6*")
        DisplayNames    = @("*TCP Checksum Offload*IPv6*", "*TCP*контрольной суммы*IPv6*", "*Проверка контрольной суммы TCP*IPv6*")
        Value           = "0"
        Why             = "TCP checksum OFF IPv6 — batch with IPv4 checksum disable"
    }
    @{
        RegistryKeyword = "*UDPChecksumOffloadIPv4"
        AltKeywords     = @("*UDPChecksum*IPv4*")
        DisplayNames    = @("*UDP Checksum Offload*IPv4*", "*UDP*контрольной суммы*IPv4*", "*Проверка контрольной суммы UDP*IPv4*")
        Value           = "0"
        Why             = "UDP checksum OFF IPv4 — part of known-good offload batch"
    }
    @{
        RegistryKeyword = "*UDPChecksumOffloadIPv6"
        AltKeywords     = @("*UDPChecksum*IPv6*")
        DisplayNames    = @("*UDP Checksum Offload*IPv6*", "*UDP*контрольной суммы*IPv6*", "*Проверка контрольной суммы UDP*IPv6*")
        Value           = "0"
        Why             = "UDP checksum OFF IPv6 — part of known-good offload batch"
    }
    @{
        RegistryKeyword = "*IPChecksumOffloadIPv4"
        AltKeywords     = @("*IPChecksumOffload*", "*IPChecksum*")
        DisplayNames    = @("*IP Checksum Offload*", "*IP*контрольной суммы*", "*Проверка контрольной суммы IP*")
        Value           = "0"
        Why             = "IP checksum OFF IPv4 — part of known-good offload batch"
    }
)

function Get-Lu4OsInfo {
    # RU: Определить семейство ОС (Win10 build <22000, Win11 >=22000).
    # EN: Detect OS family via Environment + Win32_OperatingSystem (Win11 = build >= 22000).
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
    $os = Get-Lu4OsInfo
    Write-Host ("OS: {0} | Family={1} | Version={2} | Build={3} | Arch={4}" -f `
        $os.Caption, $os.Family, $os.Version, $os.Build, $os.Architecture)
    Write-Host "Supported: Windows 10 and Windows 11 (same script / same known-good NIC settings)."
    return $os
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Step([string]$Message) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Resolve-EthernetAdapter {
    param([string]$Name, [string]$InterfaceDescription)

    $all = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -ne "Not Present" })
    if ($Name) {
        $hit = $all | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if (-not $hit) { throw "Adapter Name='$Name' not found." }
        return $hit
    }
    if ($InterfaceDescription) {
        $hit = $all | Where-Object { $_.InterfaceDescription -like "*$InterfaceDescription*" } | Select-Object -First 1
        if (-not $hit) { throw "Adapter InterfaceDescription matching '$InterfaceDescription' not found." }
        return $hit
    }

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
    try {
        $v = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        if ($v -is [array]) { return ($v -join ",") }
        return [string]$v
    } catch {
        return $null
    }
}

function Find-AdvProperty {
    <#
      RU: Найти advanced property по RegistryKeyword, AltKeywords или DisplayName (RU/EN).
      EN: Resolve advanced property via RegistryKeyword, AltKeywords, or DisplayName (RU/EN).
    #>
    param(
        [string]$AdapterName,
        [hashtable]$Target
    )
    $kw = $Target.RegistryKeyword
    $hit = Get-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $kw -ErrorAction SilentlyContinue
    if ($hit) { return $hit }

    $all = $null
    try { $all = @(Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction Stop) } catch { return $null }
    if (-not $all -or $all.Count -eq 0) { return $null }

    foreach ($alt in @($Target.AltKeywords)) {
        if (-not $alt) { continue }
        $hit = $all | Where-Object { $_.RegistryKeyword -like $alt } | Select-Object -First 1
        if ($hit) { return $hit }
    }

    foreach ($pat in @($Target.DisplayNames)) {
        if (-not $pat) { continue }
        $hit = $all | Where-Object { $_.DisplayName -like $pat } | Select-Object -First 1
        if ($hit) { return $hit }
    }

    # Last resort: keyword stem without leading *
    $stem = $kw.TrimStart("*")
    if ($stem.Length -ge 3) {
        $hit = $all | Where-Object { $_.RegistryKeyword -like "*$stem*" } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

function Test-ValueIsDisabled {
    param($Raw)
    if ($null -eq $Raw) { return $false }
    $s = ([string]$Raw).Trim()
    if ($s -eq "" ) { return $false }
    if ($s -eq "0") { return $true }
    # Some drivers expose multi-value arrays joined by comma
    if ($s -match "^(0)(,\s*0)*$") { return $true }
    return $false
}

function Show-AdapterState {
    param($Adapter, [string]$RegPath, [string]$Label)

    Write-Host ""
    Write-Host "======== $Label ========"
    Write-Host ("Name={0}" -f $Adapter.Name)
    Write-Host ("Desc={0}" -f $Adapter.InterfaceDescription)
    Write-Host ("Status={0} Link={1} IfIndex={2}" -f $Adapter.Status, $Adapter.LinkSpeed, $Adapter.ifIndex)
    Write-Host ("Guid={0}" -f $Adapter.InterfaceGuid)

    if ($RegPath) {
        $pnp = Get-RegValueSafe -Path $RegPath -Name "PnPCapabilities"
        $aspm = Get-RegValueSafe -Path $RegPath -Name "ASPM"
        Write-Host ("PnPCapabilities={0} (target={1})" -f $(if ($null -eq $pnp -or $pnp -eq "") { "<empty>" } else { $pnp }), $script:TargetPnPCapabilities)
        Write-Host ("ASPM={0} (target=0)" -f $(if ($null -eq $aspm) { "<missing>" } else { $aspm }))
        foreach ($t in $script:AdvTargets) {
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
