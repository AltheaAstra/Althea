$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

function Test-SeqotiaPython {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $pythonCommand -and $pythonCommand.Source -notlike (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\*')) {
        return $true
    }

    $pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($null -ne $pythonLauncher) {
        & $pythonLauncher.Source -3 --version
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
    }

    $codexPython = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    return Test-Path -LiteralPath $codexPython -PathType Leaf
}

function Test-SeqotiaCppToolchain {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
        return $false
    }

    $installPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    return -not [string]::IsNullOrWhiteSpace(($installPath | Select-Object -First 1))
}

function Test-SeqotiaDeveloperMode {
    $setting = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
        -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue
    return $setting.AllowDevelopmentWithoutDevLicense -eq 1
}

$flutterRoot = Join-Path $env:LOCALAPPDATA 'Programs\flutter'
$flutterExecutable = Join-Path $flutterRoot 'bin\flutter.bat'
$flutterFromPath = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -ne $flutterFromPath) {
    $flutterExecutable = $flutterFromPath.Source
    $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterExecutable)
}

if (-not (Test-Path -LiteralPath $flutterExecutable -PathType Leaf)) {
    if (Test-Path -LiteralPath $flutterRoot) {
        throw "Flutter folder exists but is incomplete: $flutterRoot. Move that folder aside, then run this setup task again."
    }

    Write-Host 'Downloading the latest stable Flutter SDK...'
    $releaseMetadata = Invoke-RestMethod -Uri 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    $stableHash = [string]$releaseMetadata.current_release.stable
    $stableRelease = $releaseMetadata.releases | Where-Object { $_.hash -eq $stableHash -and $_.channel -eq 'stable' } | Select-Object -First 1
    if ($null -eq $stableRelease -or [string]::IsNullOrWhiteSpace($stableRelease.archive)) {
        throw 'Could not find the current stable Flutter Windows archive.'
    }

    $programsDirectory = Split-Path -Parent $flutterRoot
    New-Item -ItemType Directory -Path $programsDirectory -Force | Out-Null
    $archivePath = Join-Path $env:TEMP "seqotia-flutter-$($stableRelease.version).zip"
    try {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($null -eq $curl) {
            throw 'curl.exe was not found. Install Windows updates or download Flutter manually from the official Flutter site.'
        }

        $archiveUrl = "$($releaseMetadata.base_url)/$($stableRelease.archive)"
        & $curl.Source --fail --location --retry 3 --retry-delay 2 --progress-bar --output $archivePath $archiveUrl
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            throw 'Flutter download failed. Check your internet connection and run this setup task again.'
        }

        $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($archiveHash -ne ([string]$stableRelease.sha256).ToLowerInvariant()) {
            throw 'The downloaded Flutter archive failed its SHA-256 check.'
        }

        Expand-Archive -LiteralPath $archivePath -DestinationPath $programsDirectory -Force
    } finally {
        if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
            Remove-Item -LiteralPath $archivePath -Force
        }
    }

    if (-not (Test-Path -LiteralPath $flutterExecutable -PathType Leaf)) {
        throw "Flutter did not install to the expected location: $flutterRoot"
    }
}

$flutterBin = Join-Path $flutterRoot 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathEntries = @($userPath -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') } | Where-Object { $_ })
if ($pathEntries -notcontains $flutterBin.TrimEnd('\')) {
    $updatedUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $flutterBin } else { "$userPath;$flutterBin" }
    [Environment]::SetEnvironmentVariable('Path', $updatedUserPath, 'User')
}
$env:Path = "$flutterBin;$env:Path"

if (-not (Test-SeqotiaPython)) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw 'Python was not found and winget is unavailable. Install Python 3.10+ or use this project inside the configured Codex installation.'
    }

    Write-Host 'Installing Python for the local API...'
    & $winget.Source install --id Python.Python.3.13 --exact --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw 'Python installation failed. Run this setup task again after resolving the winget message.'
    }
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

if (-not (Test-SeqotiaCppToolchain)) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw 'Visual C++ Build Tools were not found and winget is unavailable. Install Visual Studio Build Tools with the Desktop development with C++ workload.'
    }

    Write-Host 'Installing Visual Studio 2022 C++ Build Tools. Windows may ask for administrator approval.'
    & $winget.Source install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --accept-package-agreements --accept-source-agreements --override '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    if ($LASTEXITCODE -ne 0) {
        throw 'Visual Studio Build Tools installation failed. Run this setup task again after resolving the installer message.'
    }
}

$codeCommand = Get-Command code -ErrorAction SilentlyContinue
if ($null -ne $codeCommand) {
    & $codeCommand.Source --install-extension Dart-Code.flutter
}

if (-not (Test-SeqotiaDeveloperMode)) {
    Write-Warning 'Flutter and Visual Studio prerequisites are installed, but Windows Developer Mode is off.'
    Write-Warning 'Enable Developer Mode in Settings > System > Advanced > For developers, then run this setup task again.'
    throw 'Flutter Windows setup is paused until Developer Mode is enabled for plugin symlinks.'
}

Write-Host 'Enabling Flutter Windows desktop and preparing the project...'
& $flutterExecutable config --enable-windows-desktop
if ($LASTEXITCODE -ne 0) {
    throw 'Flutter could not enable Windows desktop support.'
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

Write-Host ''
Write-Host 'Setup complete. Restart VS Code once, open Run and Debug, and choose Seqotia Windows.'
