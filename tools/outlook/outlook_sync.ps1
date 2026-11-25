<#
Outlook meetings for SanctuaryUI's alarm clock.

Reads the next days of meetings from classic Outlook on this PC (its COM interface, so
recurring meetings are expanded by Outlook itself) and writes them into a tiny addon,
SanctuaryUI_Calendar, as the global SanctuaryUICalendar. SanctuaryUI reads it at login and
on /reload and rings each meeting at its start (Alarm.lua).

The addon folder lives only in the game's AddOns folder, never in the repo, so meeting
titles stay on this PC. install.ps1 copies this script there and schedules it.

    powershell -NoProfile -ExecutionPolicy Bypass -File outlook_sync.ps1 [-AddOn <folder>] [-Days 7]

-AddOn defaults to the folder this script sits in. Skipped: all-day events, cancelled
meetings and ones you declined. Writes the file only when the meetings changed.
#>
param(
    [string]$AddOn = $PSScriptRoot,
    [int]$Days = 7
)
$ErrorActionPreference = "Stop"

function LuaString([string]$s) {
    if ($null -eq $s) { return '""' }
    $s = $s -replace '[\x00-\x08\x0B-\x1F]', ' '
    $s = $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", ' ')
    if ($s.Length -gt 120) { $s = $s.Substring(0, 117) + '...' }
    return '"' + $s.Trim() + '"'
}

function Epoch([datetime]$t) {
    return ([DateTimeOffset]::new($t)).ToUnixTimeSeconds()
}

$outlook = New-Object -ComObject Outlook.Application
$session = $outlook.Session
$from = (Get-Date).AddHours(-1)
$to = (Get-Date).AddDays($Days)
$filter = "[Start] >= '" + $from.ToString("g") + "' AND [Start] <= '" + $to.ToString("g") + "'"

$events = @{}
foreach ($store in $session.Stores) {
    try { $folder = $store.GetDefaultFolder(9) } catch { continue } # olFolderCalendar
    $items = $folder.Items
    $items.IncludeRecurrences = $true
    $items.Sort("[Start]")
    foreach ($item in $items.Restrict($filter)) {
        try {
            if ($item.AllDayEvent) { continue }
            if ($item.MeetingStatus -eq 5 -or $item.MeetingStatus -eq 7) { continue } # cancelled
            if ($item.ResponseStatus -eq 4) { continue } # declined
            $start = Epoch $item.Start
            $subject = [string]$item.Subject
            $key = "$start|$subject"
            if (-not $events.ContainsKey($key)) {
                $events[$key] = [pscustomobject]@{
                    start = $start; finish = (Epoch $item.End)
                    subject = $subject; location = [string]$item.Location
                }
            }
        } catch { }
    }
}

$lines = @()
foreach ($e in ($events.Values | Sort-Object start)) {
    $lines += ("`t{{ start = {0}, finish = {1}, subject = {2}, location = {3} }}," -f $e.start, $e.finish, (LuaString $e.subject), (LuaString $e.location))
}
$body = "SanctuaryUICalendar = {`n`tupdated = __UPDATED__,`n`tevents = {`n" + ($lines -join "`n") + "`n`t},`n}`n"

New-Item -ItemType Directory -Force -Path $AddOn | Out-Null
$file = Join-Path $AddOn "Calendar.lua"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$old = if (Test-Path $file) { [IO.File]::ReadAllText($file, $utf8) -replace 'updated = \d+', 'updated = __UPDATED__' } else { "" }
$now = [DateTimeOffset]::Now.ToUnixTimeSeconds()
# Rewritten when the meetings change, and at least hourly so the addon can tell the sync runs.
$stale = (Test-Path $file) -and ((Get-Date) - (Get-Item $file).LastWriteTime).TotalMinutes -ge 60
if ($old -ne $body -or $stale) {
    [IO.File]::WriteAllText($file, $body.Replace('__UPDATED__', [string]$now), $utf8)
}

$toc = Join-Path $AddOn "SanctuaryUI_Calendar.toc"
if (-not (Test-Path $toc)) {
    $tocText = "## Interface: 16001`n## Title: SanctuaryUI Calendar`n## Notes: Your Outlook meetings for SanctuaryUI's alarm clock (written by outlook_sync.ps1)`n## AllowLoadGameType: camelot`nCalendar.lua`n"
    [IO.File]::WriteAllText($toc, $tocText, $utf8)
}
Write-Output ("{0} meetings in the next {1} days" -f $events.Count, $Days)
