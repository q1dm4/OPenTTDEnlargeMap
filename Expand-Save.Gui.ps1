Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$script:Metadata = $null; $script:Options = @(); $script:Run = $null; $script:State = ''; $script:Job = ''; $script:Source = ''; $script:Destination = ''; $script:SourceHash = ''; $script:Choice = $null
$form = New-Object Windows.Forms.Form
$form.Text = 'OpenTTD Save Map Utility'
$form.ClientSize = New-Object Drawing.Size(760, 610)
$form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
function Add-Label([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $control = New-Object Windows.Forms.Label
    $control.Text = $Text; $control.SetBounds($X, $Y, $W, $H); $form.Controls.Add($control)
    return $control
}
$title = Add-Label 'Enlarge an existing save' 22 18 710 32
$title.Font = New-Object Drawing.Font('Segoe UI', 17, [Drawing.FontStyle]::Bold)
[void](Add-Label 'Choose a save, review the added land, then create a separate copy.' 24 58 710 28)
$pathBox = New-Object Windows.Forms.TextBox
$pathBox.ReadOnly = $true; $pathBox.SetBounds(24, 98, 586, 28); $form.Controls.Add($pathBox)
$browse = New-Object Windows.Forms.Button
$browse.Text = 'Choose save...'; $browse.SetBounds(622, 96, 115, 32); $form.Controls.Add($browse)
$summary = Add-Label 'No save selected.' 24 140 712 54
[void](Add-Label 'Proposed enlargement' 24 202 710 24)
$sizes = New-Object Windows.Forms.ComboBox
$sizes.DropDownStyle = 'DropDownList'; $sizes.SetBounds(24, 232, 712, 32); $sizes.Enabled = $false; $form.Controls.Add($sizes)
$detail = Add-Label '' 24 276 712 48
$populate = New-Object Windows.Forms.CheckBox
$populate.Text = 'Populate the added land with towns and industries'; $populate.Checked = $true
$populate.SetBounds(24, 334, 710, 30); $form.Controls.Add($populate)
[void](Add-Label 'New towns' 24 376 120 24)
$towns = New-Object Windows.Forms.NumericUpDown
$towns.Minimum = 0; $towns.Maximum = 2000; $towns.SetBounds(145, 371, 120, 30); $form.Controls.Add($towns)
[void](Add-Label 'New industries' 320 376 140 24)
$industries = New-Object Windows.Forms.NumericUpDown
$industries.Minimum = 0; $industries.Maximum = 10000; $industries.SetBounds(461, 371, 120, 30); $form.Controls.Add($industries)
$hint = Add-Label 'Counts start at the existing density, within engine limits. Actual placements may be lower.' 24 414 710 44
$create = New-Object Windows.Forms.Button
$create.Text = 'Create enlarged save...'; $create.SetBounds(24, 472, 235, 38); $create.Enabled = $false; $form.Controls.Add($create)
$cancel = New-Object Windows.Forms.Button
$cancel.Text = 'Cancel'; $cancel.SetBounds(274, 472, 110, 38); $cancel.Enabled = $false; $form.Controls.Add($cancel)
$open = New-Object Windows.Forms.Button
$open.Text = 'Open output folder'; $open.SetBounds(500, 472, 236, 38); $open.Enabled = $false; $form.Controls.Add($open)
$status = Add-Label 'Required NewGRFs should be in the newgrf folder beside this utility.' 24 532 712 64
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 250

function Set-Busy([bool]$Busy) {
    $browse.Enabled = -not $Busy
    $sizes.Enabled = (-not $Busy -and $null -ne $script:Metadata -and $sizes.Items.Count -gt 0)
    $create.Enabled = $sizes.Enabled
    $populate.Enabled = -not $Busy
    $towns.Enabled = (-not $Busy -and $populate.Checked)
    $industries.Enabled = $towns.Enabled
    $cancel.Enabled = $Busy
}
function Show-UtilityError([string]$Text) {
    $status.Text = $Text
    [void][Windows.Forms.MessageBox]::Show($form, $Text, 'Map utility', 'OK', 'Error')
}
function Finish-Job([bool]$Success, [string]$Message) {
    $timer.Stop(); $script:Run = $null; $script:State = ''
    Set-Busy $false
    $status.Text = $Message
    $open.Enabled = $Success
    if ($Success) { [void][Windows.Forms.MessageBox]::Show($form, $Message, 'Enlarged save created', 'OK', 'Information') }
}
$sizes.Add_SelectedIndexChanged({
    if ($sizes.SelectedIndex -lt 0) { return }
    $o = $script:Options[$sizes.SelectedIndex]
    $towns.Value = [decimal]$o.Towns; $industries.Value = [decimal]$o.Industries
    $detail.Text = ('Adds {0:N0} tiles. New map tile data alone: {1:N0} MiB; game memory will be higher.' -f $o.AddedTiles, ($o.Width * $o.Height * 12 / 1MB))
})
$populate.Add_CheckedChanged({ $towns.Enabled = $populate.Checked; $industries.Enabled = $populate.Checked })
$browse.Add_Click({
    try {
        $dialog = New-Object Windows.Forms.OpenFileDialog
        $dialog.Title = 'Choose an OpenTTD or JGRPP save'; $dialog.Filter = 'OpenTTD saves (*.sav)|*.sav'; $dialog.CheckFileExists = $true
        if ($dialog.ShowDialog($form) -ne 'OK') { return }
        $script:Source = $dialog.FileName; $pathBox.Text = $script:Source
        $script:Metadata = $null; $sizes.Items.Clear(); $open.Enabled = $false
        $summary.Text = 'Reading map dimensions and population counts...'
        $status.Text = 'Inspecting the selected save. No changes are being made.'
        Set-Busy $true
        $script:Run = Start-UtilityProcess $script:Inspector @($script:Source) $script:Root
        $script:State = 'inspect'; $timer.Start()
    } catch { Set-Busy $false; Show-UtilityError $_.Exception.Message }
})
$create.Add_Click({
    try {
        Assert-CompatibleEngine
        $script:Choice = $script:Options[$sizes.SelectedIndex].Clone()
        $script:Choice.Populate = ($populate.Checked -and ($towns.Value + $industries.Value -gt 0))
        $script:Choice.Towns = [int]$towns.Value; $script:Choice.Industries = [int]$industries.Value
        $dialog = New-Object Windows.Forms.SaveFileDialog
        $dialog.Title = 'Choose a new output save'; $dialog.Filter = 'OpenTTD saves (*.sav)|*.sav'; $dialog.DefaultExt = 'sav'; $dialog.AddExtension = $true
        $dialog.InitialDirectory = [IO.Path]::GetDirectoryName($script:Source)
        $dialog.FileName = [IO.Path]::GetFileNameWithoutExtension($script:Source) + '-' + $script:Choice.Width + 'x' + $script:Choice.Height + '.sav'
        $dialog.OverwritePrompt = $false
        if ($dialog.ShowDialog($form) -ne 'OK') { return }
        $script:Destination = $dialog.FileName
        if ([IO.File]::Exists($script:Destination)) { throw 'That file already exists. Choose a new output filename.' }
        $script:Job = Join-Path (Join-Path $env:LOCALAPPDATA 'OpenTTD-Map-Utility\jobs') ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:Job)
        [IO.File]::WriteAllText((Join-Path $script:Job 'request.json'), (@{ Source = $script:Source; Destination = $script:Destination; Original = $script:Metadata; Enlargement = $script:Choice } | ConvertTo-Json -Depth 5), $script:Utf8)
        [IO.File]::Copy($script:Source, (Join-Path $script:Job 'input.sav'), $false)
        # Reinspect the immutable job copy: a selected save may have changed since browsing.
        $script:SourceHash = (Get-FileHash -LiteralPath (Join-Path $script:Job 'input.sav') -Algorithm SHA256).Hash
        [IO.File]::WriteAllText((Join-Path $script:Job 'engine.cfg'), "[gui]`nautosave_on_exit = false`nthreaded_saves = false`n[misc]`nsavegame_format = zlib`n", $script:Utf8)
        $open.Enabled = $false; Set-Busy $true
        $script:Run = Start-UtilityProcess $script:Inspector @((Join-Path $script:Job 'input.sav')) $script:Root
        $script:State = 'preflight'; $status.Text = 'Checking the saved input copy...'; $timer.Start()
    } catch { Set-Busy $false; Show-UtilityError $_.Exception.Message }
})
$timer.Add_Tick({
    try {
        if ($null -eq $script:Run) { return }
        if (-not $script:Run.Process.HasExited) {
            if (([DateTime]::UtcNow - $script:Run.Started).TotalMinutes -gt 5) {
                $script:Run.Process.Kill()
                throw 'The engine did not finish within five minutes. Your original save is unchanged. Check that all required NewGRFs are available. Job logs: ' + $script:Job
            }
            return
        }
        $result = Complete-UtilityProcess $script:Run
        $script:Run = $null
        if ($script:State -ne 'inspect' -and $script:Job) {
            [IO.File]::WriteAllText((Join-Path $script:Job ($script:State + '-process.log')), ($result.Output + "`n" + $result.Error), $script:Utf8)
        }
        if ($result.ExitCode -ne 0) { throw ('The process failed: ' + $result.Error.Trim()) }
        if ($script:State -eq 'inspect') {
            $script:Metadata = $result.Output | ConvertFrom-Json
            $script:Options = @(Get-Enlargements $script:Metadata)
            $summary.Text = ('Current map: {0} x {1} tiles. Towns: {2:N0}. Industries: {3:N0}.' -f $script:Metadata.width, $script:Metadata.height, $script:Metadata.towns, $script:Metadata.industries)
            foreach ($o in $script:Options) { [void]$sizes.Items.Add($o.Label) }
            if ($sizes.Items.Count -gt 0) { $sizes.SelectedIndex = 0; Finish-Job $false 'Choose an enlargement and adjust the added population if desired.' }
            else { Finish-Job $false 'No larger proposal fits this launcher version: maximum 16,777,216 total tiles.' }
            return
        }
        if ($script:State -eq 'preflight') {
            $m = $result.Output | ConvertFrom-Json
            if ($m.width -ne $script:Metadata.width -or $m.height -ne $script:Metadata.height -or $m.towns -ne $script:Metadata.towns -or $m.industries -ne $script:Metadata.industries) { throw 'The selected save changed after inspection. Choose it again to update the proposal.' }
            $cmd = 'expand_map {0} {1} expanded' -f $script:Choice.Width, $script:Choice.Height
            $script:Run = Start-EngineStage $script:Job (Join-Path $script:Job 'input.sav') 'expand' $cmd
            $script:State = 'expand'; $status.Text = 'Creating the larger map. Compatibility checks run in the patched engine.'
            return
        }
        $logPath = Join-Path $script:Job ($script:State + '-console.log')
        $log = if ([IO.File]::Exists($logPath)) { [IO.File]::ReadAllText($logPath) } else { '' }
        if ($script:State -eq 'expand') {
            $expanded = Join-Path $script:Job 'save\expanded.sav'
            if (-not [IO.File]::Exists($expanded) -or $log -notmatch 'Expanded copy exported') { throw ('Expansion did not complete. Check required NewGRFs and compatibility. ' + $log + ' Logs: ' + $script:Job) }
            if ($script:Choice.Populate) {
                $cmd = 'populate_expansion {0} {1} {2} {3} populated' -f $script:Metadata.width, $script:Metadata.height, $script:Choice.Towns, $script:Choice.Industries
                $script:Run = Start-EngineStage $script:Job $expanded 'populate' $cmd
                $script:State = 'populate'; $status.Text = 'Adding towns and industries only in the new land...'
                return
            }
            $script:ResultSave = $expanded
        } elseif ($script:State -eq 'populate') {
            $script:ResultSave = Join-Path $script:Job 'save\populated.sav'
            if (-not [IO.File]::Exists($script:ResultSave) -or $log -notmatch 'Separate populated save written') { throw ('Population did not complete. No output was published. ' + $log + ' Logs: ' + $script:Job) }
            $script:PopulationMessage = ([regex]::Match($log, 'Created [^\r\n]+')).Value
        } elseif ($script:State -eq 'verify') {
            $m = $result.Output | ConvertFrom-Json
            if ($m.width -ne $script:Choice.Width -or $m.height -ne $script:Choice.Height) { throw 'Output dimension verification failed. No output was published.' }
            $hash = (Get-FileHash -LiteralPath (Join-Path $script:Job 'input.sav') -Algorithm SHA256).Hash
            if ($hash -ne $script:SourceHash) { throw 'Input-copy verification failed. No output was published.' }
            Publish-Result $script:ResultSave $script:Destination
            $message = 'Created ' + $script:Destination + "`r`n" + $m.width + ' x ' + $m.height + ' tiles; ' + $m.towns + ' towns; ' + $m.industries + ' industries.'
            if ($script:Choice.Populate) { $message += "`r`n" + $script:PopulationMessage }
            Finish-Job $true $message
            return
        }
        $script:Run = Start-UtilityProcess $script:Inspector @($script:ResultSave) $script:Root
        $script:State = 'verify'; $status.Text = 'Verifying the completed save before writing your chosen output...'
    } catch {
        $timer.Stop()
        if ($null -ne $script:Run) {
            try { if (-not $script:Run.Process.HasExited) { $script:Run.Process.Kill() }; [void](Complete-UtilityProcess $script:Run) } catch { }
        }
        $script:Run = $null; $script:State = ''; Set-Busy $false
        Show-UtilityError $_.Exception.Message
    }
})
$cancel.Add_Click({
    if ($null -ne $script:Run) {
        try { if (-not $script:Run.Process.HasExited) { $script:Run.Process.Kill() }; [void](Complete-UtilityProcess $script:Run) } catch { }
    }
    Finish-Job $false 'Cancelled. Your original save is unchanged; no output was published.'
})
$open.Add_Click({ if ($script:Destination) { [void][Diagnostics.Process]::Start('explorer.exe', ('/select,' + (Quote-NativeArgument $script:Destination))) } })
$form.Add_FormClosing({
    if ($null -ne $script:Run) {
        try { if (-not $script:Run.Process.HasExited) { $script:Run.Process.Kill() }; [void](Complete-UtilityProcess $script:Run) } catch { }
    }
    $timer.Stop()
})
try {
    if (-not [IO.File]::Exists($script:Inspector)) { throw 'save-inspect.exe is missing. Extract the complete utility package first.' }
    [void]$form.ShowDialog()
} catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Map utility', 'OK', 'Error') }
finally { $timer.Dispose(); $form.Dispose() }
