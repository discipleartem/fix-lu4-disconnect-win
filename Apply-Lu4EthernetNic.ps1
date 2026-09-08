<#
.SYNOPSIS
  Один скрипт: применить или проверить known-good Realtek Ethernet NIC для Lu4 cold login (Win10+Win11).

.DESCRIPTION
  RU — что выключаем и зачем (кратко; подробности в README.md):
    *EEE / Green Ethernet = 0  — энергосбережение линка; NIC «дремлет» → drop TCP :9971 (~2 с)
    PnPCapabilities = 24       — запрет «разрешить отключение устройства для экономии энергии»
    *LsoV2 IPv4/IPv6 = 0       — Large Send Offload; HW-нарезка TCP на Realtek ломает игровой сеанс
    *Rsc IPv4/IPv6 = 0         — Receive Segment Coalescing; склейка RX портит тайминг handshake
    Checksum offload = 0       — HW checksum TCP/UDP/IP; баги драйвера Realtek
    *SelectiveSuspend = 0      — сон устройства в паузе login→world
    *IdlePowerDown = 0         — sleep между пакетами на коротком world TCP
    ASPM = 0                   — PCIe Active State Power Management (latency на шине)

  Контекст: Ethernet Realtek disconnect после Servers→OK; тот же <PUBLIC_WAN_IP> на WiFi — OK.
  E-Net ON — другой egress (<ENET_EGRESS_IP>), не этот фикс.

  EN: Idempotent apply of known-good NIC power-save/offload disables for Lu4 world :9971.
      -Test / -Check = read-only drift check (exit 0 OK, 1 drift). Win10 and Win11 same script.
      Does NOT disable WiFi unless -DisableWifi. Does NOT touch stream / E-Net / public IP.

.PARAMETER Name
  NetAdapter Name (default: auto-detect Realtek Ethernet).

.PARAMETER InterfaceDescription
  Match InterfaceDescription (e.g. "Realtek PCIe GbE Family Controller").

.PARAMETER DisableWifi
  Also disable wireless adapters after apply (optional; not required for the fix).

.PARAMETER Test
  Read-only check only. Exit 0 = known-good present, 1 = drift. Alias: -Check.

.PARAMETER WhatIf
  Show planned changes without writing registry / cmdlets (apply mode only).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -Test

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Name,
    [string]$InterfaceDescription,
    [switch]$DisableWifi,
    [Alias("Check")]
    [switch]$Test
)

$ErrorActionPreference = "Continue"

# --- known-good targets (inline; was Lu4EthernetNic.Shared.ps1) ---
$script:NicClassPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
# PnPCapabilities=24 (0x18): forbid "allow computer to turn off this device"
$script:TargetPnPCapabilities = 24

$script:AdvTargets = @(
    @{
        RegistryKeyword = "*EEE"
        AltKeywords     = @("EEE", "*EnergyEfficientEthernet")
        DisplayNames    = @("*Energy-Efficient Ethernet*", "*Energy Efficient Ethernet*", "*Энергоэффективный Ethernet*", "*EEE*")
        Value           = "0"
        Why             = "EEE OFF — NIC link power-save can stall/reset Lu4 world TCP :9971"
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
        Why             = "Green Ethernet OFF — Realtek cable/power gating; same class as EEE vs :9971"
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

function Set-AdvOrReg {
    param(
        [string]$AdapterName,
        [string]$RegPath,
        [hashtable]$Target,
        [switch]$WhatIfMode
    )
    $want = $Target.Value
    $adv = Find-AdvProperty -AdapterName $AdapterName -Target $Target
    if ($adv) {
        $kw = [string]$adv.RegistryKeyword
        $cur = ($adv.RegistryValue -join ",")
        if (Test-ValueIsDisabled $cur) {
            Write-Step ("OK already ADV {0}={1} ({2})" -f $kw, $want, $adv.DisplayName)
            return
        }
        $msg = "ADV Set-NetAdapterAdvancedProperty {0} -> {1} (was {2} / {3}) — {4}" -f `
            $kw, $want, $cur, $adv.DisplayValue, $Target.Why
        if ($WhatIfMode) { Write-Step ("WhatIf: {0}" -f $msg); return }
        if ($PSCmdlet.ShouldProcess($AdapterName, $msg)) {
            Set-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $kw -RegistryValue $want -NoRestart -ErrorAction Stop
            Write-Step ("SET ADV {0}={1}" -f $kw, $want)
        }
        return
    }

    $kw = $Target.RegistryKeyword
    $had = Get-RegValueSafe -Path $RegPath -Name $kw
    if (Test-ValueIsDisabled $had) {
        Write-Step ("OK already REG {0}={1}" -f $kw, $want)
        return
    }
    $msg = "REG {0}={1} (had={2}) — {3}" -f $kw, $want, $(if ($null -eq $had) { "<missing>" } else { $had }), $Target.Why
    if ($WhatIfMode) { Write-Step ("WhatIf: {0}" -f $msg); return }
    if ($PSCmdlet.ShouldProcess($RegPath, $msg)) {
        New-ItemProperty -Path $RegPath -Name $kw -PropertyType String -Value $want -Force -ErrorAction Stop | Out-Null
        Write-Step ("SET REG {0}={1}" -f $kw, $want)
    }
}

function Invoke-Lu4NicDriftTest {
    param($Adapter, [string]$RegPath)

    $drift = @()
    $ok = @()
    $skip = @()

    foreach ($t in $script:AdvTargets) {
        $label = $t.RegistryKeyword
        $adv = Find-AdvProperty -AdapterName $Adapter.Name -Target $t
        if ($adv) {
            $cur = ($adv.RegistryValue -join ",")
            $label = "{0} ({1})" -f $adv.RegistryKeyword, $adv.DisplayName
            if (Test-ValueIsDisabled $cur) {
                $ok += "ADV $label = $cur"
            } else {
                $drift += "ADV $label = $cur (want 0 / Disabled)"
            }
            continue
        }
        $reg = Get-RegValueSafe -Path $RegPath -Name $t.RegistryKeyword
        if ($null -eq $reg) {
            $skip += "missing $label (not exposed by this driver INF — OK if N/A)"
            continue
        }
        if (Test-ValueIsDisabled $reg) {
            $ok += "REG $label = $reg"
        } else {
            $drift += "REG $label = $reg (want 0)"
        }
    }

    $pnp = Get-RegValueSafe -Path $RegPath -Name "PnPCapabilities"
    if ([string]$pnp -eq [string]$script:TargetPnPCapabilities) {
        $ok += "PnPCapabilities=$pnp"
    } else {
        $drift += ("PnPCapabilities={0} (want {1})" -f $(if ($null -eq $pnp -or $pnp -eq "") { "<empty>" } else { $pnp }), $script:TargetPnPCapabilities)
    }

    $aspm = Get-RegValueSafe -Path $RegPath -Name "ASPM"
    if ($aspm -eq "0") {
        $ok += "ASPM=0"
    } elseif ($null -eq $aspm) {
        $skip += "ASPM missing (optional on some INF)"
    } else {
        $drift += "ASPM=$aspm (want 0)"
    }

    try {
        $lso = Get-NetAdapterLso -Name $Adapter.Name -ErrorAction Stop
        if ($lso.IPv4Enabled -or $lso.IPv6Enabled) {
            $drift += ("LSO still enabled IPv4={0} IPv6={1}" -f $lso.IPv4Enabled, $lso.IPv6Enabled)
        } else {
            $ok += "LSO disabled (cmdlet)"
        }
    } catch {
        $skip += "LSO query unavailable"
    }

    try {
        $rsc = Get-NetAdapterRsc -Name $Adapter.Name -ErrorAction Stop
        if ($rsc.IPv4Enabled -or $rsc.IPv6Enabled) {
            $drift += ("RSC still enabled IPv4={0} IPv6={1}" -f $rsc.IPv4Enabled, $rsc.IPv6Enabled)
        } else {
            $ok += "RSC disabled (cmdlet)"
        }
    } catch {
        $skip += "RSC query unavailable"
    }

    try {
        $csum = Get-NetAdapterChecksumOffload -Name $Adapter.Name -ErrorAction SilentlyContinue
        if ($csum -and ($csum.TcpIPv4Enabled -or $csum.TcpIPv6Enabled -or $csum.UdpIPv4Enabled -or $csum.UdpIPv6Enabled -or $csum.IpIPv4Enabled)) {
            $drift += "ChecksumOffload still enabled (cmdlet layer)"
        } else {
            $ok += "ChecksumOffload disabled / none (cmdlet)"
        }
    } catch {
        $skip += "ChecksumOffload query unavailable"
    }

    Write-Host "--- OK ---"
    $ok | ForEach-Object { Write-Host ("  + {0}" -f $_) }
    if ($skip.Count -gt 0) {
        Write-Host "--- N/A / skip ---"
        $skip | ForEach-Object { Write-Host ("  ~ {0}" -f $_) }
    }
    if ($drift.Count -gt 0) {
        Write-Host "--- DRIFT ---"
        $drift | ForEach-Object { Write-Host ("  ! {0}" -f $_) }
        Write-Host ""
        Write-Host "RESULT: DRIFT — re-run Apply-Lu4EthernetNic.ps1 as Administrator (without -Test), then -Test again."
        Write-Host "Verify Lu4: faction Black → Recommended → select Black in Servers → OK only (no second Black)."
        return 1
    }

    Write-Host ""
    Write-Host "RESULT: OK — known-good settings present."
    Write-Host "Verify Lu4: faction Black → Recommended → select Black in Servers → OK → character select."
    Write-Host "(After Black is selected in Servers, press OK only.)"
    return 0
}

# --- main ---
Write-Host "=== Apply-Lu4EthernetNic ==="
Write-Host "Lu4 Realtek Ethernet known-good (EEE/Green/LSO/RSC/checksum/PnPCapabilities=24)"
Write-Host "Keep your white public WAN IP. Do NOT use hotspot/VPN as 'the fix'."
if ($Test) { Write-Host "Mode: -Test (read-only drift check)" }
Write-Host ""
$null = Write-Lu4OsBanner
Write-Host ""

$isAdmin = Test-IsAdmin
if (-not $Test -and -not $isAdmin -and -not $WhatIfPreference) {
    Write-Host "ERROR: Run elevated (Administrator). Registry + Disable-NetAdapterLso need admin."
    Write-Host "Example:"
    Write-Host '  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1'
    exit 1
}
if (-not $isAdmin -and ($WhatIfPreference -or $Test)) {
    Write-Host "WARN: without admin — detection/show may be incomplete."
}

$adapter = Resolve-EthernetAdapter -Name $Name -InterfaceDescription $InterfaceDescription
$regPath = Get-NicRegPath -InterfaceGuid ([string]$adapter.InterfaceGuid)
if (-not $regPath -and -not $WhatIfPreference) {
    Write-Host "ERROR: Could not resolve NIC class registry path for $($adapter.InterfaceGuid)"
    exit 1
}

if ($Test) {
    Write-Host ("Adapter: Name={0} Desc={1} Status={2}" -f $adapter.Name, $adapter.InterfaceDescription, $adapter.Status)
    Write-Host ("RegPath: {0}" -f $regPath)
    Write-Host ""
    $code = Invoke-Lu4NicDriftTest -Adapter $adapter -RegPath $regPath
    exit $code
}

Show-AdapterState -Adapter $adapter -RegPath $regPath -Label "BEFORE"

Write-Host ""
Write-Step "Applying known-good settings (idempotent)..."

foreach ($t in $script:AdvTargets) {
    try {
        Set-AdvOrReg -AdapterName $adapter.Name -RegPath $regPath -Target $t -WhatIfMode:$WhatIfPreference
    } catch {
        Write-Step ("FAIL {0}: {1}" -f $t.RegistryKeyword, $_)
    }
}

# PnPCapabilities=24 — forbid "allow computer to turn off this device" (Lu4 :9971 drop if NIC sleeps)
$oldPnP = Get-RegValueSafe -Path $regPath -Name "PnPCapabilities"
$pnpMsg = "PnPCapabilities '{0}' -> {1} (disable allow-computer-to-turn-off-this-device)" -f $(if ($null -eq $oldPnP -or $oldPnP -eq "") { "<empty>" } else { $oldPnP }), $script:TargetPnPCapabilities
if ([string]$oldPnP -eq [string]$script:TargetPnPCapabilities) {
    Write-Step ("OK already {0}" -f $pnpMsg)
} elseif ($WhatIfPreference) {
    Write-Step ("WhatIf: {0}" -f $pnpMsg)
} elseif ($PSCmdlet.ShouldProcess($regPath, $pnpMsg)) {
    New-ItemProperty -Path $regPath -Name PnPCapabilities -PropertyType DWord -Value $script:TargetPnPCapabilities -Force | Out-Null
    Write-Step ("SET {0}" -f $pnpMsg)
}

# ASPM=0 — PCIe Active State Power Management off (bus sleep can add wake latency on world TCP)
$oldAspm = Get-RegValueSafe -Path $regPath -Name "ASPM"
if ($oldAspm -eq "0") {
    Write-Step "OK already ASPM=0"
} elseif ($WhatIfPreference) {
    Write-Step "WhatIf: ASPM -> 0 (PCIe link power management OFF for Lu4 cold path)"
} elseif ($PSCmdlet.ShouldProcess($regPath, "ASPM=0")) {
    New-ItemProperty -Path $regPath -Name ASPM -PropertyType String -Value "0" -Force | Out-Null
    Write-Step "SET ASPM=0"
}

if (-not $WhatIfPreference) {
    try {
        if ($adapter.Status -eq "Disabled") {
            if ($PSCmdlet.ShouldProcess($adapter.Name, "Enable-NetAdapter")) {
                Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 2
                $adapter = Get-NetAdapter -Name $adapter.Name
                Write-Step "Enable-NetAdapter OK"
            }
        }
    } catch {
        Write-Step ("Enable-NetAdapter: {0}" -f $_)
    }

    try {
        if ($PSCmdlet.ShouldProcess($adapter.Name, "Disable-NetAdapterLso")) {
            Disable-NetAdapterLso -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            Write-Step "Disable-NetAdapterLso OK"
        }
    } catch { Write-Step ("Disable-NetAdapterLso: {0}" -f $_) }

    try {
        if ($PSCmdlet.ShouldProcess($adapter.Name, "Disable-NetAdapterRsc")) {
            Disable-NetAdapterRsc -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            Write-Step "Disable-NetAdapterRsc OK"
        }
    } catch { Write-Step ("Disable-NetAdapterRsc: {0}" -f $_) }

    try {
        if ($PSCmdlet.ShouldProcess($adapter.Name, "Disable-NetAdapterChecksumOffload")) {
            Disable-NetAdapterChecksumOffload -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            Write-Step "Disable-NetAdapterChecksumOffload OK"
        }
    } catch { Write-Step ("Disable-NetAdapterChecksumOffload: {0}" -f $_) }

    try {
        if ($PSCmdlet.ShouldProcess($adapter.Name, "Set-NetAdapterPowerManagement AllowComputerToTurnOffDevice=Disabled")) {
            Set-NetAdapterPowerManagement -Name $adapter.Name `
                -AllowComputerToTurnOffDevice Disabled `
                -WakeOnMagicPacket Disabled `
                -WakeOnPattern Disabled `
                -Confirm:$false -ErrorAction Stop
            Write-Step "Set-NetAdapterPowerManagement AllowComputerToTurnOffDevice=Disabled"
        }
    } catch { Write-Step ("Set-NetAdapterPowerManagement: {0}" -f $_) }
}

if ($DisableWifi) {
    Write-Host ""
    Write-Step "-DisableWifi: disabling wireless adapters (optional; NOT required for Ethernet fix)"
    $wifiList = @(
        Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -ne "Not Present" -and
            ($_.InterfaceDescription -match "Wireless|Wi-?Fi|802\.11" -or $_.Name -match "Wi-?Fi|WLAN|Беспровод")
        }
    )
    foreach ($w in $wifiList) {
        if ($WhatIfPreference) {
            Write-Step ("WhatIf: Disable-NetAdapter '{0}'" -f $w.Name)
        } elseif ($PSCmdlet.ShouldProcess($w.Name, "Disable-NetAdapter")) {
            try {
                Disable-NetAdapter -Name $w.Name -Confirm:$false -ErrorAction Stop
                Write-Step ("Disabled WiFi '{0}'" -f $w.Name)
            } catch {
                Write-Step ("Disable WiFi '{0}': {1}" -f $w.Name, $_)
            }
        }
    }
} else {
    Write-Step "WiFi left unchanged (pass -DisableWifi only if you want Ethernet-only)."
}

$adapter = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
if ($adapter) {
    Show-AdapterState -Adapter $adapter -RegPath $regPath -Label "AFTER"
}

Write-Host ""
Write-Host "=== Done ==="
Write-Host "Verify Lu4: E-Net OFF, Ethernet up → faction Black → Recommended → select Black in Servers → OK → character select."
Write-Host "(After Black is selected in the server list, press OK only — do not pick Black again.)"
Write-Host "TCP check: world :9971 Established >= 20s. Public IP should remain your white WAN (<PUBLIC_WAN_IP>)."
Write-Host "After NIC driver update on Win10 or Win11: re-run this script, then: .\Apply-Lu4EthernetNic.ps1 -Test"
if ($WhatIfPreference) {
    Write-Host "(WhatIf only — no changes written.)"
}
exit 0
