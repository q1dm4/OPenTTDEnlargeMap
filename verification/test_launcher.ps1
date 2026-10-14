$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'launcher-source/Expand-Save.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Launcher parser failed.' }
foreach ($f in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    Invoke-Expression $f.Extent.Text
}
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Root = $root
$dir = Join-Path $PSScriptRoot 'paths with spaces'
[void][IO.Directory]::CreateDirectory($dir)
$inputSave=Join-Path $dir 'Sadingham Unicode - café.sav'
[IO.File]::Copy((Join-Path $root 'launcher-base/Sadingham-Population/Sadingham-populated-example-2048.sav'),$inputSave,$true)
$r=Complete-UtilityProcess (Start-UtilityProcess (Join-Path $root 'launcher-build/save-inspect') @($inputSave) $root)
if ($r.ExitCode -ne 0) {throw $r.Error}
$m=$r.Output | ConvertFrom-Json
if ($m.width -ne 2048 -or $m.height -ne 2048 -or $m.towns -ne 1352 -or $m.industries -ne 6401) {throw 'Reader process metadata failed.'}
$script:ExpectedEngineHash='44DB489587AF1216AE569965F8DED51BBDDF480DB86B393B79169F9335F28D53'
$script:Engine=Join-Path $root 'launcher-base/Sadingham-Population/openttd.exe'
Assert-CompatibleEngine
$wrong=Join-Path $dir 'wrong-engine.exe'
[IO.File]::WriteAllText($wrong,'Not the patched engine')
$script:Engine=$wrong
$rejected=$false
try {Assert-CompatibleEngine} catch {$rejected=$true}
if (-not $rejected) {throw 'Stock/different engine guard failed.'}
$o=@(Get-Enlargements @{width=1024;height=512;towns=100;industries=200})
if ($o.Count -ne 3 -or $o[0].Width -ne 2048 -or $o[0].Height -ne 1024 -or $o[0].Towns -ne 300) {throw 'Rectangular proposal failed.'}
$script:Options=$o
$job=Join-Path $dir 'job'
[void][IO.Directory]::CreateDirectory($job)
Write-EngineStage $job 'expand' 'expand_map 2048 1024 expanded'
$content=[IO.File]::ReadAllText((Join-Path $job 'scripts/game_start.scr'))
if ($content -notmatch 'script ".*paths with spaces.*expand-console.log"' -or $content -notmatch 'expand_map 2048 1024 expanded') {throw 'Engine script path quoting failed.'}
$bytes=[IO.File]::ReadAllBytes((Join-Path $job 'scripts/game_start.scr'))
if ($bytes[0] -eq 239) {throw 'Engine script contains a UTF8 BOM.'}
$output=Join-Path $dir 'output.sav'
if ([IO.File]::Exists($output)) {[IO.File]::Delete($output)}
Publish-Result $inputSave $output
if ((Get-FileHash -LiteralPath $inputSave).Hash -ne (Get-FileHash -LiteralPath $output).Hash) {throw 'Published output differs.'}
$before=(Get-FileHash -LiteralPath $output).Hash
$rejected=$false
try {Publish-Result $inputSave $output} catch {$rejected=$true}
if (-not $rejected -or (Get-FileHash -LiteralPath $output).Hash -ne $before) {throw 'Overwrite guard failed.'}
'PowerShell process, Unicode/spaced paths, rectangular proposals, script generation, publication and overwrite tests passed.'
