# Build image multi-arch (linux/amd64 dan linux/arm64) lalu push ke GHCR.
# Login dulu sendiri (token tidak dimasukkan ke script ini):
#   podman login ghcr.io -u bongcoy
# Pemakaian:
#   .\scripts\build-push.ps1 -Version 1.2
#   .\scripts\build-push.ps1 -Version 1.2 -Apps dogsworld-js
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string[]]$Apps = @("dogsworld-dotnet", "dogsworld-js"),
    [string]$Registry = "ghcr.io/bongcoy",
    [string[]]$Platforms = @("linux/amd64", "linux/arm64")
)

$ErrorActionPreference = "Stop"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
$root = Split-Path -Parent $PSScriptRoot

$host.UI.RawUI.WindowTitle = "build-push $Version"
podman login --get-login ghcr.io *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Belum login ke ghcr.io. Jalankan: podman login ghcr.io -u bongcoy (pakai Personal Access Token dengan scope write:packages)"
}

foreach ($app in $Apps) {
    $dir = Join-Path $root "apps\$app"
    if (-not (Test-Path (Join-Path $dir "Dockerfile"))) { Write-Error "Tidak ada Dockerfile di $dir" }
    $ref = "$Registry/${app}:$Version"

    Write-Host "== Build $ref ($($Platforms -join ', '))"
    podman manifest rm $ref *> $null
    podman build --platform ($Platforms -join ",") --manifest $ref $dir
    if ($LASTEXITCODE -ne 0) { Write-Error "Build $app gagal" }

    Write-Host "== Push $ref"
    podman manifest push --all $ref "docker://$ref"
    if ($LASTEXITCODE -ne 0) { Write-Error "Push $app gagal" }
}

Write-Host ""
Write-Host "Selesai. Jangan lupa: naikkan tag image dan label tags.datadoghq.com/version di k8s/*.yaml jika versi berubah."
Write-Host "Package GHCR baru bersifat private. Ubah ke Public di GitHub > Packages > Package settings."
