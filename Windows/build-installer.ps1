param([ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'build.ps1') -Runtime $Runtime
$compiler = Get-Command makensis.exe -ErrorAction SilentlyContinue
if ($compiler) { $makensis = $compiler.Source }
else {
    $makensis = Join-Path ${env:ProgramFiles(x86)} 'NSIS/makensis.exe'
    if (-not (Test-Path $makensis)) { throw 'Install NSIS from https://nsis.sourceforge.io/Download and try again.' }
}
$dependencies = Join-Path $PSScriptRoot 'installer/dependencies'
New-Item -ItemType Directory -Path $dependencies -Force | Out-Null
$bootstrapper = Join-Path $dependencies 'MicrosoftEdgeWebview2Setup.exe'
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $bootstrapper
$signature = Get-AuthenticodeSignature $bootstrapper
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
    throw 'Microsoft WebView2 bootstrapper signature verification failed.'
}
python (Join-Path $PSScriptRoot 'installer/build.py') --runtime $Runtime --makensis $makensis --bootstrapper $bootstrapper
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
