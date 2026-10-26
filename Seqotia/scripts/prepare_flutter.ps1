$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterExecutable = if ($null -ne $flutterCommand) {
    $flutterCommand.Source
} else {
    Join-Path $env:LOCALAPPDATA 'Programs\flutter\bin\flutter.bat'
}

if (-not (Test-Path -LiteralPath $flutterExecutable -PathType Leaf)) {
    throw 'Flutter is not installed. In VS Code choose Terminal > Run Task > Seqotia: Install prerequisites, then restart VS Code.'
}

if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'windows\CMakeLists.txt') -PathType Leaf)) {
    & $flutterExecutable create --platforms=windows --project-name seqotia .
    if ($LASTEXITCODE -ne 0) {
        throw 'Flutter could not create the Windows runner.'
    }
}

& $flutterExecutable pub get
if ($LASTEXITCODE -ne 0) {
    throw 'Flutter could not download the project dependencies.'
}
