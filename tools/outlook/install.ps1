<#
Sets up the Outlook sync for SanctuaryUI's alarm clock:
  1. makes <AddOns>\SanctuaryUI_Calendar and copies outlook_sync.ps1 and run_hidden.vbs into it,
  2. runs the sync once,
  3. schedules it every 15 minutes while you're logged on (task "SanctuaryUI Outlook sync").

    powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -AddOns "D:\Games\World of Warcraft\_forever_\Interface\AddOns"

Undo: Unregister-ScheduledTask -TaskName "SanctuaryUI Outlook sync" and delete the folder.
The game finds a new addon folder only when it starts, so restart WoW once after installing.
#>
param(
    [Parameter(Mandatory = $true)][string]$AddOns,
    [int]$Minutes = 15,
    [switch]$NoSchedule
)
$ErrorActionPreference = "Stop"
$target = Join-Path $AddOns "SanctuaryUI_Calendar"
New-Item -ItemType Directory -Force -Path $target | Out-Null
foreach ($f in "outlook_sync.ps1", "run_hidden.vbs") {
    Copy-Item -Force (Join-Path $PSScriptRoot $f) (Join-Path $target $f)
}
& (Join-Path $target "outlook_sync.ps1") -AddOn $target

if (-not $NoSchedule) {
    $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ('"' + (Join-Path $target "run_hidden.vbs") + '"')
    $every = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $Minutes)
    $logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName "SanctuaryUI Outlook sync" -Action $action -Trigger @($every, $logon) -Settings $settings `
        -Description "Copies your upcoming Outlook meetings into WoW for SanctuaryUI's alarm clock." -Force | Out-Null
    Write-Output "scheduled every $Minutes minutes: SanctuaryUI Outlook sync"
}
Write-Output "installed in $target"
