#requires -Version 5.1
<#
.SYNOPSIS
    Undo the Adobe network blocking: remove every BlockAdobe_* firewall rule
    and restore license caches from their .bak backups.

.DESCRIPTION
    - Removes all rules whose DisplayName starts with BlockAdobe_ (including
      legacy rules left by earlier attempts).
    - Moves *.bak / *.bak_<timestamp> license-cache files back to their
      original names, so Adobe apps can reach the network and re-validate
      online again.

.NOTES
    Must run in an elevated (admin) PowerShell. Recommended launch:
        Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<this script>' -Wait
#>
$ErrorActionPreference = 'Continue'
$log = New-Object System.Collections.Generic.List[string]

Write-Output '== Removing BlockAdobe_* firewall rules =='
$rules = @(Get-NetFirewallRule -DisplayName 'BlockAdobe_*' -ErrorAction SilentlyContinue)
foreach ($r in $rules) {
    try {
        Remove-NetFirewallRule -DisplayName $r.DisplayName -ErrorAction Stop
        $log.Add("Removed rule: $($r.DisplayName)")
    } catch {
        $log.Add("FAIL remove $($r.DisplayName) :: $($_.Exception.Message)")
    }
}
if ($rules.Count -eq 0) { $log.Add('No BlockAdobe_* rules found.') }

Write-Output '== Restoring license caches =='
$bakPatterns = @(
    'C:\Program Files (x86)\Common Files\Adobe\Adobe PCD\cache\cache.db.bak*',
    'C:\Program Files (x86)\Common Files\Adobe\Adobe PCD\pcd.db.bak*'
)
foreach ($pat in $bakPatterns) {
    Get-Item -Path $pat -ErrorAction SilentlyContinue | ForEach-Object {
        $orig = $_.FullName -replace '\.bak(?:_\d+)?$', ''
        try {
            Move-Item -LiteralPath $_.FullName -Destination $orig -Force -ErrorAction Stop
            $log.Add("Restored: $($_.FullName) -> $orig")
        } catch {
            $log.Add("FAIL restore $($_.FullName) :: $($_.Exception.Message)")
        }
    }
}

$log | ForEach-Object { Write-Output $_ }
