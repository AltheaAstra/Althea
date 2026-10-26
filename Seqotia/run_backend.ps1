$projectRoot = $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$env:PYTHONUNBUFFERED = '1'

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($null -ne $pythonCommand -and $pythonCommand.Source -notlike (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\*')) {
    & $pythonCommand.Source --version
    if ($LASTEXITCODE -eq 0) {
        & $pythonCommand.Source -u -m backend.app.main
        exit $LASTEXITCODE
    }
}

$pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
if ($null -ne $pythonLauncher) {
    & $pythonLauncher.Source -3 --version
    if ($LASTEXITCODE -eq 0) {
        & $pythonLauncher.Source -3 -u -m backend.app.main
        exit $LASTEXITCODE
    }
}

$codexPython = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if (Test-Path -LiteralPath $codexPython -PathType Leaf) {
    & $codexPython -u -m backend.app.main
    exit $LASTEXITCODE
}

Write-Error 'Python 3.10+ was not found. Install Python and add it to PATH, or run this script inside the configured Codex installation.'
exit 1
