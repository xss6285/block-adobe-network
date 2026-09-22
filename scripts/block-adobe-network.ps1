#requires -Version 5.1
<#
.SYNOPSIS
    Block network access for all Adobe software on this Windows machine.

.DESCRIPTION
    1. Discovers Adobe install directories (registry uninstall keys + known
       common locations + per-user AppData).
    2. Enumerates every .exe under those directories.
    3. Creates per-executable Windows Firewall Block rules (outbound + inbound).
    4. Enables Windows Firewall profiles if disabled (third-party security
       software often turns the built-in firewall off, which silently disables
       every rule).
    5. Backs up Adobe license-check cache DBs (Adobe PCD / SLStore) by renaming
       them to .bak, so apps re-validate offline instead of reading a cached
       "not entitled" verdict - this is what fixes the "You no longer have
       access to this app" popup after blocking.
    6. Optionally stops Adobe background helper processes (never the main apps:
       Photoshop.exe / Illustrator.exe / Lightroom.exe are never touched).

.NOTES
    Must run in an elevated (admin) PowerShell. Recommended launch:
        Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<this script>' -Wait
    Idempotent: safe to re-run; rules that already exist are skipped.
    Log is written to $env:TEMP\block-adobe-network-<timestamp>.log.
#>
param(
    [switch]$SkipLicenseCacheBackup,
    [switch]$SkipFirewallEnable,
    [switch]$SkipKillHelpers
)

$ErrorActionPreference = 'Continue'
$log = New-Object System.Collections.Generic.List[string]
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$logPath = Join-Path $env:TEMP "block-adobe-network-$stamp.log"

function Write-Log($msg) { $log.Add($msg); Write-Output $msg }

Write-Log "== block-adobe-network $stamp =="

# ---- 1. Discover Adobe install roots ----
$candidates = New-Object System.Collections.Generic.List[string]
$uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($k in $uninstallKeys) {
    Get-ItemProperty $k -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Adobe*' -and $_.InstallLocation } |
        ForEach-Object { $candidates.Add($_.InstallLocation) }
}
$candidates.Add('C:\Program Files\Adobe')
$candidates.Add('C:\Program Files (x86)\Adobe')
$candidates.Add('C:\Program Files\Common Files\Adobe')
$candidates.Add('C:\Program Files (x86)\Common Files\Adobe')
$candidates.Add((Join-Path $env:LOCALAPPDATA 'Adobe'))
$candidates.Add((Join-Path $env:APPDATA 'Adobe'))

$roots = @()
foreach ($c in ($candidates | Select-Object -Unique)) {
    $full = [System.Environment]::ExpandEnvironmentVariables($c)
    if (Test-Path -LiteralPath $full) { $roots += $full }
}

# ---- 2. Enumerate executables ----
$exes = @()
foreach ($r in $roots) {
    $exes += Get-ChildItem -LiteralPath $r -Recurse -Filter *.exe -File -ErrorAction SilentlyContinue
}
$exes = $exes | Sort-Object { $_.FullName.ToLowerInvariant() } -Unique
Write-Log "Discovered $($exes.Count) Adobe executables under $($roots.Count) root(s)."

# ---- 3. Create firewall rules (idempotent) ----
$createdOut = 0; $createdIn = 0; $skipped = 0; $failed = 0
$i = 0
foreach ($e in $exes) {
    $i++
    $outName = 'BlockAdobe_OUT_{0:000}_{1}' -f $i, $e.Name
    $inName  = 'BlockAdobe_IN_{0:000}_{1}' -f $i, $e.Name
    try {
        if (-not (Get-NetFirewallRule -DisplayName $outName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $outName -Direction Outbound -Action Block -Program $e.FullName -Profile Any -Enabled True -ErrorAction Stop | Out-Null
            $createdOut++
        } else { $skipped++ }
        if (-not (Get-NetFirewallRule -DisplayName $inName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $inName -Direction Inbound -Action Block -Program $e.FullName -Profile Any -Enabled True -ErrorAction Stop | Out-Null
            $createdIn++
        } else { $skipped++ }
    } catch {
        $failed++
        Write-Log "  FAIL $($e.FullName) :: $($_.Exception.Message)"
    }
}
Write-Log "Firewall rules: created out=$createdOut in=$createdIn, skipped=$skipped, failed=$failed."

# ---- 4. Enable firewall profiles ----
if (-not $SkipFirewallEnable) {
    $changed = @()
    foreach ($pf in Get-NetFirewallProfile) {
        if (-not $pf.Enabled) {
            Set-NetFirewallProfile -Name $pf.Name -Enabled $true -ErrorAction SilentlyContinue
            $changed += $pf.Name
        }
    }
    if ($changed.Count -gt 0) { Write-Log "Enabled firewall profile(s): $($changed -join ', ')" }
    else { Write-Log 'All firewall profiles already enabled.' }
} else {
    Write-Log 'Skipped firewall profile enable (SkipFirewallEnable).'
}

# ---- 5. Back up license-check cache DBs ----
if (-not $SkipLicenseCacheBackup) {
    $cacheFiles = @(
        'C:\Program Files (x86)\Common Files\Adobe\Adobe PCD\cache\cache.db',
        'C:\Program Files (x86)\Common Files\Adobe\Adobe PCD\pcd.db'
    )
    $slStore = 'C:\ProgramData\Adobe\SLStore'
    if (Test-Path -LiteralPath $slStore) {
        $cacheFiles += Get-ChildItem -LiteralPath $slStore -File -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }
    foreach ($f in $cacheFiles) {
        if (Test-Path -LiteralPath $f) {
            $dest = "$f.bak"
            if (Test-Path -LiteralPath $dest) { $dest = "$f.bak_$stamp" }
            try {
                Move-Item -LiteralPath $f -Destination $dest -Force -ErrorAction Stop
                Write-Log "Backed up license cache: $f -> $dest"
            } catch {
                Write-Log "  WARN could not back up $f :: $($_.Exception.Message)"
            }
        }
    }
} else {
    Write-Log 'Skipped license cache backup (SkipLicenseCacheBackup).'
}

# ---- 5.5 Ensure Adobe apps bypass the system proxy so firewall rules apply ----
# Apps that honor the system proxy (e.g. Clash/mihomo) can tunnel around
# per-program firewall rules: the real outbound connection is made by the
# proxy process, not the Adobe exe. Forcing Adobe domains to connect directly
# makes the per-program Block rules catch them.
try {
    $inet = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $cur = (Get-ItemProperty -Path $inet -Name ProxyOverride -ErrorAction SilentlyContinue).ProxyOverride
    $adobeBypass = 'adobe.com;*.adobe.com;adobe.io;*.adobe.io;adobe.net;*.adobe.net;adobecreativecloud.com;*.adobecreativecloud.com;adobessm.com;*.adobessm.com;adobessm.net;*.adobessm.net'
    $adobeParts = $adobeBypass -split ';'
    $missing = @($adobeParts | Where-Object { $cur -and $cur.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -lt 0 })
    if (-not $cur) {
        Set-ItemProperty -Path $inet -Name ProxyOverride -Value $adobeBypass
        Write-Log 'Set Adobe domains as proxy bypass (no previous override list).'
    } elseif ($missing.Count -gt 0) {
        Set-ItemProperty -Path $inet -Name ProxyOverride -Value "$cur;$($missing -join ';')"
        Write-Log "Added Adobe domains to proxy bypass: $($missing -join ';')"
    } else {
        Write-Log 'Adobe domains already in proxy bypass list.'
    }
} catch {
    Write-Log "  WARN could not update proxy bypass :: $($_.Exception.Message)"
}

# ---- 6. Stop background helper processes (never main apps) ----
if (-not $SkipKillHelpers) {
    $helperNames = @('CCXProcess', 'CCLibrary', 'AdobeIPCBroker', 'CoreSync', 'LogCollectorTool')
    $killed = @()
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like '*Adobe*' -and $_.Name -in $helperNames } |
        ForEach-Object {
            try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; $killed += "$($_.Name)($($_.Id))" } catch { }
        }
    if ($killed.Count -gt 0) { Write-Log "Stopped helper processes: $($killed -join ', ')" }
    else { Write-Log 'No Adobe helper processes were running.' }
} else {
    Write-Log 'Skipped killing helper processes (SkipKillHelpers).'
}

$log | Set-Content -LiteralPath $logPath -Encoding UTF8
Write-Log "Full log: $logPath"
