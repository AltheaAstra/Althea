$ErrorActionPreference = 'Stop'
$apiHealthUrl = 'http://127.0.0.1:8000/health'

try {
    $health = Invoke-RestMethod -Uri $apiHealthUrl -TimeoutSec 2
    if ($health.status -eq 'ok') {
        Write-Output 'Seqotia backend already ready at http://127.0.0.1:8000'
        exit 0
    }
} catch {
    # Start the local backend when no healthy Seqotia API is listening yet.
}

Write-Output 'Seqotia backend starting'
$backendLauncher = Join-Path (Split-Path -Parent $PSScriptRoot) 'run_backend.ps1'
& $backendLauncher
exit $LASTEXITCODE
