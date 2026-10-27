# Build image multi-arch (linux/amd64 dan linux/arm64) lalu push ke GHCR.
# Login dulu sendiri (token tidak dimasukkan ke script ini):
#   podman login ghcr.io -u bongcoy   (Personal Access Token dengan scope write:packages)
# Package GHCR yang baru dibuat bersifat private. Ubah ke Public sekali di GitHub
# (Packages, Package settings, Change visibility) supaya orang lain bisa menarik image tanpa login.
# Pemakaian:
#   .\scripts\build-push.ps1 -Version 1.2
#   .\scripts\build-push.ps1 -Version 1.2 -Apps dogsworld-js
#
# ECR Private (EKS): kredensial AWS harus sudah aktif. Script login sendiri lewat "aws ecr get-login-password"
# (token berlaku 12 jam, tidak ditulis ke file). Repo ECR harus sudah ada.
#   .\scripts\build-push.ps1 -Version 1.2 -Registry 896986967332.dkr.ecr.ap-southeast-2.amazonaws.com
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string[]]$Apps = @("dogsworld-dotnet", "dogsworld-js"),
    [string]$Registry = "ghcr.io/bongcoy",
    [string[]]$Platforms = @("linux/amd64", "linux/arm64")
)

# "Continue": di Windows PowerShell 5.1, teks stderr dari podman dianggap error bila "Stop".
# Kegagalan sungguhan tetap tertangkap lewat pengecekan $LASTEXITCODE.
$ErrorActionPreference = "Continue"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
$root = Split-Path -Parent $PSScriptRoot

$registryHost = $Registry.Split("/")[0]
if ($registryHost -match '^(\d+)\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com$') {
    $ecrRegion = $Matches[2]
    Write-Host "== Login ke ECR $registryHost"
    $token = aws ecr get-login-password --region $ecrRegion
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        Write-Host "Gagal mengambil token ECR. Pastikan kredensial AWS aktif (aws sts get-caller-identity)." -ForegroundColor Red
        exit 1
    }
    $token | podman login --username AWS --password-stdin $registryHost
    $token = $null
    if ($LASTEXITCODE -ne 0) { Write-Host "podman login ke ECR gagal" -ForegroundColor Red; exit 1 }
}
else {
    podman login --get-login $registryHost 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Belum login ke $registryHost. Untuk ghcr.io jalankan: podman login ghcr.io -u bongcoy (pakai Personal Access Token dengan scope write:packages)" -ForegroundColor Red
        exit 1
    }
}

foreach ($app in $Apps) {
    $dir = Join-Path $root "apps\$app"
    if (-not (Test-Path (Join-Path $dir "Dockerfile"))) { Write-Host "Tidak ada Dockerfile di $dir" -ForegroundColor Red; exit 1 }
    $ref = "$Registry/${app}:$Version"

    Write-Host "== Build $ref ($($Platforms -join ', '))"
    podman manifest exists $ref 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { podman manifest rm $ref | Out-Null }
    podman build --platform ($Platforms -join ",") --manifest $ref $dir
    if ($LASTEXITCODE -ne 0) { Write-Host "Build $app gagal" -ForegroundColor Red; exit 1 }

    Write-Host "== Push $ref"
    podman manifest push --all $ref "docker://$ref"
    if ($LASTEXITCODE -ne 0) { Write-Host "Push $app gagal" -ForegroundColor Red; exit 1 }
}

Write-Host ""
Write-Host "Selesai. Jangan lupa: naikkan tag image dan label tags.datadoghq.com/version di k8s/*.yaml jika versi berubah."
if ($registryHost -eq "ghcr.io") { Write-Host "Package GHCR baru bersifat private. Ubah ke Public di GitHub > Packages > Package settings." }
