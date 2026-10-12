param([ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'source/CampusConnect.csproj'
$output = Join-Path $PSScriptRoot "dist/$Runtime"
$staging = Join-Path $PSScriptRoot ("work/publish-" + [guid]::NewGuid().ToString('N'))
dotnet publish $project -c Release -r $Runtime --self-contained true -p:PublishReadyToRun=true -o $staging
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
$files = @(Get-ChildItem $staging -Recurse -File)
if ($files.Count -ne 1 -or $files[0].Name -ne 'CampusConnect.exe') {
    throw 'Single-file publish produced unexpected extra files.'
}
# The directory is a generated build output; stage first to avoid stale DLLs on subsequent builds.
if (Test-Path $output) { Remove-Item $output -Recurse -Force }
New-Item -ItemType Directory -Path (Split-Path $output) -Force | Out-Null
Move-Item $staging $output
Write-Host "Built single-file app: $output/CampusConnect.exe"
