#requires -Version 5.1
<#
.SYNOPSIS
    Read-only verification of Adobe network blocking state (no admin needed).

.DESCRIPTION
    Reports:
      - Windows Firewall profile states (rules only take effect when a profile
        is enabled - third-party AV often disables them all).
      - Count of BlockAdobe_* rules (total / enabled outbound / enabled inbound),
        plus legacy rules left by earlier attempts.
      - Which discovered Adobe executables are NOT covered by any rule yet.
      - Whether license-cache backups (.bak) exist.
      - Currently running Adobe processes.
#>
$ErrorActionPreference = 'Continue'

Write-Output '== Firewall profiles =='
Get-NetFirewallProfile | ForEach-Object { Write-Output ("  {0}: Enabled={1}" -f $_.Name, $_.Enabled) }

Write-Output '== BlockAdobe rules =='
$rules = @(Get-NetFirewallRule -DisplayName 'BlockAdobe_*' -ErrorAction SilentlyContinue)
$out = @($rules | Where-Object { $_.Direction -eq 'Outbound' -and $_.Action -eq 'Block' -and $_.Enabled })
$inn = @($rules | Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block' -and $_.Enabled })
Write-Output ("  Total: {0} | Enabled Outbound-Block: {1} | Enabled Inbound-Block: {2}" -f $rules.Count, $out.Count, $inn.Count)
$legacy = @($rules | Where-Object { $_.DisplayName -notmatch '^BlockAdobe_(OUT|IN)_' })
if ($legacy.Count -gt 0) { Write-Output ("  Legacy rules from earlier attempts (also match BlockAdobe_*): {0}" -f $legacy.Count) }

Write-Output '== Coverage check (discovered exes vs rules) =='
$candidates = @()
$uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($k in $uninstallKeys) {
    Get-ItemProperty $k -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Adobe*' -and $_.InstallLocation } |
        ForEach-Object { $candidates += $_.InstallLocation }
}
$candidates += @(
    'C:\Program Files\Adobe',
    'C:\Program Files (x86)\Adobe',
    'C:\Program Files\Common Files\Adobe',
    'C:\Program Files (x86)\Common Files\Adobe',
    (Join-Path $env:LOCALAPPDATA 'Adobe'),
    (Join-Path $env:APPDATA 'Adobe')
)
$roots = @()
foreach ($c in ($candidates | Select-Object -Unique)) {
    $full = [System.Environment]::ExpandEnvironmentVariables($c)
    if (Test-Path -LiteralPath $full) { $roots += $full }
}
$exes = @()
foreach ($r in $roots) {
    $exes += Get-ChildItem -LiteralPath $r -Recurse -Filter *.exe -File -ErrorAction SilentlyContinue
}
$exes = $exes | Sort-Object { $_.FullName.ToLowerInvariant() } -Unique

$covered = @()
foreach ($r in $rules) {
    $app = $r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
    if ($app -and $app.Program) { $covered += $app.Program }
}
$missing = @($exes | Where-Object { $covered -notcontains $_.FullName })
if ($missing.Count -eq 0) { Write-Output "  All $($exes.Count) discovered executables are covered." }
else {
    Write-Output "  $($missing.Count) executables NOT covered:"
    $missing | ForEach-Object { Write-Output "    $($_.FullName)" }
}

Write-Output '== License cache backups (.bak present?) =='
$bakChecks = @(
    'C:\Program Files (x86)\Common Files\Adobe\Adobe PCD\cache\cache.db.bak',
    'C:\Program Files (x86)\Common Files\Adobe\Adobe PCD\pcd.db.bak'
)
foreach ($b in $bakChecks) {
    Write-Output ("  {0} : {1}" -f $b, (Test-Path -LiteralPath $b))
}

Write-Output '== Running Adobe processes =='
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -like '*Adobe*' } |
    Select-Object Name, ProcessId, ExecutablePath |
    Sort-Object Name |
    Format-Table -AutoSize | Out-String | Write-Output
