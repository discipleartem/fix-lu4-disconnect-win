<#
.SYNOPSIS
  Read-only check: are Lu4 known-good Ethernet NIC settings applied?

.DESCRIPTION
  RU: Проверяет, что known-good настройки Ethernet уже выставлены (Win10+Win11).
      Exit 0 = OK, Exit 1 = drift (после обновления драйвера — снова Apply).
  EN: Reports whether known-good settings are present. Exit 0 = OK, 1 = drift.
      Useful after Realtek driver updates on Windows 10 or 11.

.PARAMETER Name
  NetAdapter Name (default: auto-detect Realtek Ethernet).

.PARAMETER InterfaceDescription
  Match InterfaceDescription.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Test-Lu4EthernetNic.ps1
#>
[CmdletBinding()]
param(
    [string]$Name,
    [string]$InterfaceDescription
)

$ErrorActionPreference = "Continue"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here "Lu4EthernetNic.Shared.ps1")

Write-Host "=== Test-Lu4EthernetNic (read-only) ==="
$null = Write-Lu4OsBanner
Write-Host ""

$adapter = Resolve-EthernetAdapter -Name $Name -InterfaceDescription $InterfaceDescription
$regPath = Get-NicRegPath -InterfaceGuid ([string]$adapter.InterfaceGuid)
if (-not $regPath) {
    Write-Host "ERROR: NIC class registry path not found."
    exit 1
}

Write-Host ("Adapter: Name={0} Desc={1} Status={2}" -f $adapter.Name, $adapter.InterfaceDescription, $adapter.Status)
Write-Host ("RegPath: {0}" -f $regPath)
Write-Host ""

$drift = @()
$ok = @()
$skip = @()

foreach ($t in $script:AdvTargets) {
    $label = $t.RegistryKeyword
    $adv = Find-AdvProperty -AdapterName $adapter.Name -Target $t
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
    $reg = Get-RegValueSafe -Path $regPath -Name $t.RegistryKeyword
    if ($null -eq $reg) {
        # Property absent on this INF — not counted as drift (driver-specific set).
        $skip += "missing $label (not exposed by this driver INF — OK if N/A)"
        continue
    }
    if (Test-ValueIsDisabled $reg) {
        $ok += "REG $label = $reg"
    } else {
        $drift += "REG $label = $reg (want 0)"
    }
}

$pnp = Get-RegValueSafe -Path $regPath -Name "PnPCapabilities"
if ([string]$pnp -eq [string]$script:TargetPnPCapabilities) {
    $ok += "PnPCapabilities=$pnp"
} else {
    $drift += ("PnPCapabilities={0} (want {1})" -f $(if ($null -eq $pnp -or $pnp -eq "") { "<empty>" } else { $pnp }), $script:TargetPnPCapabilities)
}

$aspm = Get-RegValueSafe -Path $regPath -Name "ASPM"
if ($aspm -eq "0") {
    $ok += "ASPM=0"
} elseif ($null -eq $aspm) {
    $skip += "ASPM missing (optional on some INF)"
} else {
    $drift += "ASPM=$aspm (want 0)"
}

try {
    $lso = Get-NetAdapterLso -Name $adapter.Name -ErrorAction Stop
    if ($lso.IPv4Enabled -or $lso.IPv6Enabled) {
        $drift += ("LSO still enabled IPv4={0} IPv6={1}" -f $lso.IPv4Enabled, $lso.IPv6Enabled)
    } else {
        $ok += "LSO disabled (cmdlet)"
    }
} catch {
    $skip += "LSO query unavailable"
}

try {
    $rsc = Get-NetAdapterRsc -Name $adapter.Name -ErrorAction Stop
    if ($rsc.IPv4Enabled -or $rsc.IPv6Enabled) {
        $drift += ("RSC still enabled IPv4={0} IPv6={1}" -f $rsc.IPv4Enabled, $rsc.IPv6Enabled)
    } else {
        $ok += "RSC disabled (cmdlet)"
    }
} catch {
    $skip += "RSC query unavailable"
}

try {
    $csum = Get-NetAdapterChecksumOffload -Name $adapter.Name -ErrorAction SilentlyContinue
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
    Write-Host "RESULT: DRIFT — re-run Apply-Lu4EthernetNic.ps1 as Administrator, then Test again."
    Write-Host "Verify Lu4: faction Black → Recommended → select Black in Servers → OK (no second Black)."
    exit 1
}

Write-Host ""
Write-Host "RESULT: OK — known-good settings present."
Write-Host "Verify Lu4: faction Black → Recommended → select Black in Servers → OK → character select."
Write-Host "(After Black is selected in Servers, press OK only.)"
exit 0
