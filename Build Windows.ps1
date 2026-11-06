# From the Godot project folder, create Bomb Defender.exe + .pck + .zip.
# Requires matching Godot export templates (Godot > Editor > Manage Export Templates).
param([string]$GodotPath = "")
$ErrorActionPreference = "Stop"
$project = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -ne $command) { $GodotPath = $command.Source }
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    Write-Host "Godot not found on PATH. Provide its EXE location:" -ForegroundColor Yellow
    $GodotPath = Read-Host 'Godot executable path (e.g. C:\Godot\Godot_v4.4.1-stable_win64.exe)'
    $GodotPath = $GodotPath.Trim('"')
}
if (-not (Test-Path $GodotPath)) { throw "Godot executable not found: $GodotPath" }
$consoleGodotPath = $GodotPath -replace '(?i)\.exe$', '_console.exe'
if ((Test-Path $consoleGodotPath) -and ($GodotPath -notmatch '(?i)_console\.exe$')) {
    $GodotPath = $consoleGodotPath
}
$godotVersion = (& $GodotPath --version | Select-Object -First 1).Trim()
$versionMatch = [regex]::Match($godotVersion, '^(\d+\.\d+)')
if (-not $versionMatch.Success) { throw "Could not read Godot version: $godotVersion" }

$rceditDirectory = Join-Path $env:LOCALAPPDATA 'Godot/tools'
$rceditPath = Join-Path $rceditDirectory 'rcedit-x64.exe'
New-Item -ItemType Directory -Force -Path $rceditDirectory | Out-Null
if (-not (Test-Path $rceditPath)) {
    Invoke-WebRequest -Uri 'https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe' -OutFile $rceditPath
}

$settingsDirectory = Join-Path $env:APPDATA 'Godot'
New-Item -ItemType Directory -Force -Path $settingsDirectory | Out-Null
$settingsFile = Join-Path $settingsDirectory ("editor_settings-{0}.tres" -f $versionMatch.Value)
$rceditSetting = 'export/windows/rcedit = "' + $rceditPath.Replace('\','/') + '"'
if (Test-Path $settingsFile) {
    $settings = Get-Content -LiteralPath $settingsFile -Raw
    if ($settings -match '(?m)^export/windows/rcedit\s*=') {
        $settings = [regex]::Replace($settings, '(?m)^export/windows/rcedit\s*=.*$', $rceditSetting)
    } elseif ($settings.Contains('[resource]')) {
        $settings = $settings.TrimEnd() + "`n" + $rceditSetting + "`n"
    } else {
        $settings = $settings.TrimEnd() + "`n[resource]`n" + $rceditSetting + "`n"
    }
} else {
    $settings = "[gd_resource type=`"EditorSettings`" format=3]`n`n[resource]`n$rceditSetting`n"
}
[System.IO.File]::WriteAllText($settingsFile, $settings, [System.Text.UTF8Encoding]::new($false))

Push-Location -LiteralPath $project
try {
    New-Item -ItemType Directory -Force -Path 'dist' | Out-Null
    & $GodotPath --headless --path . --editor --quit
    if ($LASTEXITCODE -ne 0) { throw 'Project import failed' }

    & $GodotPath --headless --path . --export-release 'Windows Desktop' 'dist/Bomb Defender.exe'
    if ($LASTEXITCODE -ne 0) { throw 'Export failed. Install export templates in Godot.' }

    $exe = Join-Path $project 'dist/Bomb Defender.exe'
    $pck = Join-Path $project 'dist/Bomb Defender.pck'
    if (-not ((Test-Path $exe) -and (Test-Path $pck))) { throw 'Missing EXE or PCK after export' }
    $productName = (& $rceditPath $exe --get-version-string ProductName | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $productName -ne 'Bomb Defender') { throw 'Windows EXE icon or metadata was not applied' }

    $zip = Join-Path $project 'dist/Bomb Defender.zip'
    Compress-Archive -LiteralPath $exe, $pck -DestinationPath $zip -Force
    Write-Host "DONE: $zip" -ForegroundColor Green
}
finally {
    Pop-Location
}
