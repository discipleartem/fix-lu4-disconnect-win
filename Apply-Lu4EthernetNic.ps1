<#
.SYNOPSIS
  Apply known-good Realtek Ethernet NIC settings for Lu4 cold login (E-Net OFF).

.DESCRIPTION
  RU: Отключает энергосбережение и TCP offload на Ethernet (EEE/Green/LSO/RSC/checksum/PnP),
      которые ломали вход в мир Lu4 (:9971 drop ~2s) на Realtek PCIe GbE при том же белом IP.
      Работает на Windows 10 и Windows 11 (один скрипт).
  EN: Disables NIC power-save and TCP offloads that caused Lu4 world :9971 drop after server OK
      on Realtek PCIe GbE Ethernet — same public IP that worked on WiFi.
      Supports Windows 10 and Windows 11 (single script).

  Idempotent. Does NOT disable WiFi unless -DisableWifi is passed.
  Does NOT touch stream bitrate / E-Net / public IP.

.PARAMETER Name
  NetAdapter Name (default: auto-detect Realtek Ethernet).

.PARAMETER InterfaceDescription
  Match InterfaceDescription (e.g. "Realtek PCIe GbE Family Controller").

.PARAMETER DisableWifi
  Also disable wireless adapters after apply (optional; not required for the fix).

.PARAMETER WhatIf
  Show planned changes without writing registry / cmdlets.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -WhatIf

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1 -Name Ethernet -DisableWifi
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Name,
    [string]$InterfaceDescription,
    [switch]$DisableWifi
)

$ErrorActionPreference = "Continue"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here "Lu4EthernetNic.Shared.ps1")

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

    # Fallback: write primary RegistryKeyword into NIC class key (driver may pick it up on reload).
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

# --- main ---
Write-Host "=== Apply-Lu4EthernetNic ==="
Write-Host "Lu4 Realtek Ethernet known-good (EEE/Green/LSO/RSC/checksum/PnPCapabilities=24)"
Write-Host "Keep your white public WAN IP. Do NOT use hotspot/VPN as 'the fix'."
Write-Host ""
$null = Write-Lu4OsBanner
Write-Host ""

$isAdmin = Test-IsAdmin
if (-not $isAdmin -and -not $WhatIfPreference) {
    Write-Host "ERROR: Run elevated (Administrator). Registry + Disable-NetAdapterLso need admin."
    Write-Host "Example:"
    Write-Host '  powershell -ExecutionPolicy Bypass -File .\Apply-Lu4EthernetNic.ps1'
    exit 1
}
if (-not $isAdmin -and $WhatIfPreference) {
    Write-Host "WARN: -WhatIf without admin — detection/show may be incomplete."
}

$adapter = Resolve-EthernetAdapter -Name $Name -InterfaceDescription $InterfaceDescription
$regPath = Get-NicRegPath -InterfaceGuid ([string]$adapter.InterfaceGuid)
if (-not $regPath -and -not $WhatIfPreference) {
    throw "Could not resolve NIC class registry path for $($adapter.InterfaceGuid)"
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
Write-Host "After NIC driver update on Win10 or Win11: re-run Apply, then Test-Lu4EthernetNic.ps1."
if ($WhatIfPreference) {
    Write-Host "(WhatIf only — no changes written.)"
}
exit 0
