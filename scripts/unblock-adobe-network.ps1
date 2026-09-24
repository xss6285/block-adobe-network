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

Write-Output '== Restoring proxy bypass list =='
$inet = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
try {
    $cur = (Get-ItemProperty -Path $inet -Name ProxyOverride -ErrorAction SilentlyContinue).ProxyOverride
    $adobeParts = 'adobe.com;*.adobe.com;adobe.io;*.adobe.io;adobe.net;*.adobe.net;adobecreativecloud.com;*.adobecreativecloud.com;adobessm.com;*.adobessm.com;adobessm.net;*.adobessm.net' -split ';'
    if ($cur) {
        $new = @($cur -split ';' | Where-Object { $adobeParts -notcontains $_ }) -join ';'
        if ($new -ne $cur) {
            Set-ItemProperty -Path $inet -Name ProxyOverride -Value $new
            $log.Add('Removed Adobe domains from proxy bypass list.')
        } else {
            $log.Add('No Adobe domains found in proxy bypass list.')
        }
    } else {
        $log.Add('No proxy bypass list present.')
    }
} catch {
    $log.Add("FAIL proxy bypass restore :: $($_.Exception.Message)")
}

Write-Output '== Restoring Clash Verge proxy bypass config =='
$vergeYaml = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev\verge.yaml'
if (Test-Path -LiteralPath $vergeYaml) {
    try {
        $lines = @(Get-Content -LiteralPath $vergeYaml)
        $changed = $false
        $newLines = foreach ($line in $lines) {
            if ($line -match '^\s*system_proxy_bypass:\s*"([^"]*)"') {
                $curVal = $Matches[1]
                $adobeParts = 'adobe.com;*.adobe.com;adobe.io;*.adobe.io;adobe.net;*.adobe.net;adobecreativecloud.com;*.adobecreativecloud.com;adobessm.com;*.adobessm.com;adobessm.net;*.adobessm.net' -split ';'
                $reduced = @($curVal -split ';' | Where-Object { $adobeParts -notcontains $_ }) -join ';'
                if ($reduced -ne $curVal) {
                    $changed = $true
                    "system_proxy_bypass: `"$reduced`""
                } else { $line }
            } else { $line }
        }
        if ($changed) {
            Set-Content -LiteralPath $vergeYaml -Value $newLines -Encoding UTF8
            $log.Add('Removed Adobe domains from Clash Verge system proxy bypass.')
        } else {
            $log.Add('No Adobe domains found in Clash Verge system proxy bypass.')
        }
    } catch {
        $log.Add("FAIL Clash Verge config restore :: $($_.Exception.Message)")
    }
}

Write-Output '== Removing Adobe block entries from hosts file =='
$hostsFile = "$env:windir\System32\drivers\etc\hosts"
try {
    $hostnames = @('adobe.io','adobestats.io','lmlicenses.wip4.adobe.com','lm.licenses.adobe.com','prod.adobegenuine.com','genuine.adobe.com','cc-api.adobe.io','ic.adobe.io','na1r.services.adobe.com','hlrcv.stage.adobe.com','3dns.adobe.com','3dns-1.adobe.com','3dns-2.adobe.com','3dns-3.adobe.com','adobe-dns.adobe.com','adobe-dns-1.adobe.com','adobe-dns-2.adobe.com','adobe-dns-3.adobe.com','ereg.adobe.com','activate.adobe.com','practivate.adobe.com','entitlement.adobe.com','wip.adobe.com')
    $content = Get-Content -LiteralPath $hostsFile -ErrorAction SilentlyContinue
    $kept = @($content | Where-Object {
        $m = $_ -match '^\s*(0\.0\.0\.0|127\.0\.0\.1)\s+([^\s#]+)'
        if ($m) { $hostnames -notcontains $Matches[2] } else { $true }
    })
    if ($kept.Count -ne $content.Count) {
        Set-Content -LiteralPath $hostsFile -Value $kept -Encoding ASCII
        $log.Add("Removed Adobe entries from hosts file ($($content.Count - $kept.Count) lines).")
    } else {
        $log.Add('No Adobe entries found in hosts file.')
    }
} catch {
    $log.Add("FAIL hosts restore :: $($_.Exception.Message)")
}

$log | ForEach-Object { Write-Output $_ }
