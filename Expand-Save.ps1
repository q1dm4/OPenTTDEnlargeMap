# Requires Windows PowerShell 5.1. No Python installation needed.
# SPDX-License-Identifier: GPL-2.0-only
[CmdletBinding()]
param([string]$Inspect, [switch]$SelfTest)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Root = $PSScriptRoot
$script:Engine = Join-Path $script:Root 'openttd.exe'
$script:Inspector = Join-Path $script:Root 'save-inspect.exe'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:ExpectedEngineHash = '44DB489587AF1216AE569965F8DED51BBDDF480DB86B393B79169F9335F28D53'

function Assert-CompatibleEngine {
    if (-not [IO.File]::Exists($script:Engine)) { throw 'Extract this utility into the Sadingham-Population folder containing the population v0.2 openttd.exe.' }
    $actual = (Get-FileHash -LiteralPath $script:Engine -Algorithm SHA256).Hash
    if ($actual -ne $script:ExpectedEngineHash) { throw 'This launcher requires the population v0.2 patched openttd.exe. Stock OpenTTD and earlier builds are not supported by this launcher.' }
}

function Quote-NativeArgument([string]$Value) {
    # Windows CRT argument quoting: preserve spaces, quotes and trailing slashes.
    $s = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $s = [regex]::Replace($s, '(\\+)$', '$1$1')
    return '"' + $s + '"'
}
function Start-UtilityProcess([string]$Exe, [string[]]$Arguments, [string]$Directory) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Exe
    $info.Arguments = (($Arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' ')
    $info.WorkingDirectory = $Directory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Could not start the utility process.' }
    return @{ Process = $process; Out = $process.StandardOutput.ReadToEndAsync(); Err = $process.StandardError.ReadToEndAsync(); Started = [DateTime]::UtcNow }
}
function Complete-UtilityProcess($Run) {
    $Run.Process.WaitForExit()
    $result = @{ ExitCode = $Run.Process.ExitCode; Output = $Run.Out.GetAwaiter().GetResult(); Error = $Run.Err.GetAwaiter().GetResult() }
    $Run.Process.Dispose()
    return $result
}
function Get-Enlargements($Metadata) {
    $w = [long]$Metadata.width; $h = [long]$Metadata.height
    $options = @(
        @{ Width = 2 * $w; Height = 2 * $h; Name = 'Double both dimensions' },
        @{ Width = 2 * $w; Height = $h; Name = 'Double width only' },
        @{ Width = $w; Height = 2 * $h; Name = 'Double height only' }
    )
    foreach ($o in $options) {
        # First launcher release limits proposals to 4096 x 4096-equivalent area.
        if ($o.Width -gt 1048576 -or $o.Height -gt 1048576 -or $o.Width * $o.Height -gt 16777216) { continue }
        $o.AddedTiles = $o.Width * $o.Height - $w * $h
        $o.Towns = [Math]::Min(2000, [Math]::Round([double]$Metadata.towns * $o.AddedTiles / ($w * $h)))
        $o.Industries = [Math]::Min(10000, [Math]::Round([double]$Metadata.industries * $o.AddedTiles / ($w * $h)))
        $factor = ($o.Width * $o.Height) / ($w * $h)
        $o.Label = '{0} x {1} - {2} ({3}x total area)' -f $o.Width, $o.Height, $o.Name, $factor
        $o
    }
}
function Write-EngineStage([string]$Job, [string]$Stage, [string]$Command) {
    $scripts = Join-Path $Job 'scripts'
    [void][IO.Directory]::CreateDirectory($scripts)
    $log = (Join-Path $Job ($Stage + '-console.log')).Replace('\', '/')
    # Generated paths cannot contain a quote or a line break on Windows.
    if ($log -match '["\r\n]') { throw 'Unsupported working-folder path.' }
    $text = 'script "' + $log + '"' + "`nmap_report`n" + $Command + "`nmap_report`nexit`n"
    [IO.File]::WriteAllText((Join-Path $scripts 'game_start.scr'), $text, $script:Utf8)
}
function Start-EngineStage([string]$Job, [string]$Save, [string]$Stage, [string]$Command) {
    Write-EngineStage $Job $Stage $Command
    return Start-UtilityProcess $script:Engine @('-X', '-x', '-c', (Join-Path $Job 'engine.cfg'), '-g', $Save, '-v', 'null:ticks=8', '-s', 'null', '-m', 'null') $Job
}
function Publish-Result([string]$Source, [string]$Destination) {
    # CreateNew makes overwrite protection atomic, including a late file race.
    $inputStream = [IO.File]::OpenRead($Source)
    $outputStream = $null
    try {
        $outputStream = New-Object IO.FileStream($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $inputStream.CopyTo($outputStream)
        $outputStream.Flush($true)
    } catch {
        if ($null -ne $outputStream) { $outputStream.Dispose(); $outputStream = $null; [IO.File]::Delete($Destination) }
        throw
    } finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        $inputStream.Dispose()
    }
}
if ($SelfTest) {
    if ((Quote-NativeArgument 'C:\folder with spaces\save.sav') -ne '"C:\folder with spaces\save.sav"') { throw 'Argument quoting failed.' }
    if ((Quote-NativeArgument 'C:\folder\') -ne '"C:\folder\\"') { throw 'Trailing-slash quoting failed.' }
    $o = @(Get-Enlargements @{ width = 1024; height = 1024; towns = 338; industries = 1705 })
    if ($o.Count -ne 3 -or $o[0].Width -ne 2048 -or $o[0].Towns -ne 1014 -or $o[0].Industries -ne 5115) { throw 'Density proposal failed.' }
    if (@(Get-Enlargements @{ width = 4096; height = 4096; towns = 1; industries = 1 }).Count -ne 0) { throw 'Map limit failed.' }
    'Launcher self-test passed.'
    exit 0
}
if ($Inspect) {
    $r = Complete-UtilityProcess (Start-UtilityProcess $script:Inspector @([IO.Path]::GetFullPath($Inspect)) $script:Root)
    if ($r.ExitCode -ne 0) { throw $r.Error }
    $r.Output
    exit 0
}
if ($env:OS -ne 'Windows_NT') { throw 'The graphical launcher requires Windows.' }
. (Join-Path $PSScriptRoot 'Expand-Save.Gui.ps1')
