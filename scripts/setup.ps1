# Menyiapkan seluruh DogsWorld di cluster minikube (Windows PowerShell 5.1 atau PowerShell 7).
# Aman dijalankan ulang: Secret yang sudah ada tidak ditimpa.
#
# Contoh:
#   .\scripts\setup.ps1                                    # tanya site, API key, env, clusterName
#   .\scripts\setup.ps1 -Site ap1.datadoghq.com -Env alice -ClusterName dogsworld-alice
#   .\scripts\setup.ps1 -NoDatadog                         # tanpa Datadog sama sekali
#   .\scripts\setup.ps1 -SkipCluster                       # pakai cluster yang sudah jalan (context kubectl aktif)
#   .\scripts\setup.ps1 -LocalImages                       # build image lokal, tidak menarik dari GHCR
#
# API key: dibaca dari env DD_API_KEY, atau ditanya (input tersembunyi). Tidak ditulis ke file atau log.
param(
    [string]$Site,
    [string]$Env,
    [string]$ClusterName,
    [switch]$NoDatadog,
    [switch]$SkipCluster,
    [switch]$LocalImages,
    [string]$OperatorVersion = "2.30.0",
    [string]$Driver = "podman",
    [int]$Cpus = 4,
    [int]$MemoryMb = 4096
)

$ErrorActionPreference = "Stop"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
$root = Split-Path -Parent $PSScriptRoot
$k8s = Join-Path $root "k8s"

function Step($msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }
function Run($label) { if ($LASTEXITCODE -ne 0) { throw "Gagal: $label" } }
function SecretExists($ns, $name) {
    kubectl get secret $name -n $ns *> $null
    return ($LASTEXITCODE -eq 0)
}
function NewPassword { -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ }) }
function ApplyText($text) { $text | kubectl apply -f -; Run "kubectl apply" }

foreach ($tool in @("kubectl", "helm", "minikube")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool belum terpasang atau belum ada di PATH" }
}

# --- Pilihan Datadog ---
if (-not $NoDatadog) {
    if (-not $Site)        { $Site = Read-Host "Datadog site (contoh: ap1.datadoghq.com, datadoghq.com, us5.datadoghq.com)" }
    if (-not $Env)         { $Env = Read-Host "Nilai tag env (contoh: dev, atau namamu)" }
    if (-not $ClusterName) { $ClusterName = Read-Host "Nama cluster di Datadog (contoh: dogsworld-namamu)" }
    foreach ($v in @($Site, $Env, $ClusterName)) { if ([string]::IsNullOrWhiteSpace($v)) { throw "Site, env, dan clusterName tidak boleh kosong" } }
    if ($Env -cnotmatch '^[a-z][a-z0-9_./-]*$') { throw "env harus huruf kecil, diawali huruf, tanpa spasi (lihat TAGS.md)" }
}
else { $Env = "dev" }

# --- 1. Cluster ---
if (-not $SkipCluster) {
    Step "Cluster minikube (driver $Driver)"
    minikube start --driver=$Driver --container-runtime=cri-o --cpus=$Cpus --memory=$MemoryMb
    Run "minikube start"
}
kubectl get nodes; Run "kubectl get nodes"

# --- 2. Datadog Operator ---
if (-not $NoDatadog) {
    Step "Datadog Operator $OperatorVersion"
    helm repo add datadog https://helm.datadoghq.com *> $null
    helm repo update | Out-Null
    helm upgrade --install datadog-operator datadog/datadog-operator -n datadog --create-namespace --version $OperatorVersion --wait
    Run "helm upgrade --install"

    if (-not (SecretExists "datadog" "datadog-secret")) {
        $key = $env:DD_API_KEY
        if (-not $key) {
            $sec = Read-Host "Datadog API key (tidak ditampilkan)" -AsSecureString
            $key = [System.Net.NetworkCredential]::new("", $sec).Password
        }
        if ([string]::IsNullOrWhiteSpace($key)) { throw "API key kosong" }
        kubectl create secret generic datadog-secret -n datadog --from-literal=api-key=$key | Out-Null
        Run "buat datadog-secret"
        $key = $null
        Write-Host "Secret datadog-secret dibuat."
    }
    else { Write-Host "Secret datadog-secret sudah ada, dipakai ulang." }
}

# --- 3. Namespace dan Secret database ---
Step "Namespace dan Secret"
kubectl apply -f (Join-Path $k8s "namespace.yaml"); Run "namespace"
if (-not (SecretExists "dogsworld" "postgres-secret")) {
    kubectl create secret generic postgres-secret -n dogsworld --from-literal=password=$(NewPassword) | Out-Null
    Run "buat postgres-secret"
    Write-Host "Secret postgres-secret dibuat (password acak)."
}
if (-not $NoDatadog -and -not (SecretExists "dogsworld" "datadog-pg-secret")) {
    kubectl create secret generic datadog-pg-secret -n dogsworld --from-literal=password=$(NewPassword) | Out-Null
    Run "buat datadog-pg-secret"
    Write-Host "Secret datadog-pg-secret dibuat (password acak)."
}

# --- 4. Postgres ---
Step "PostgreSQL"
ApplyText ((Get-Content (Join-Path $k8s "postgres.yaml") -Raw) -replace 'tags\.datadoghq\.com/env: dev', "tags.datadoghq.com/env: $Env")
kubectl rollout status deployment/postgres -n dogsworld --timeout=300s; Run "rollout postgres"

if (-not $NoDatadog) {
    Step "Setup user datadog untuk Database Monitoring"
    $pod = kubectl get pod -n dogsworld -l app=postgres -o jsonpath='{.items[0].metadata.name}'
    $script = (Get-Content (Join-Path $PSScriptRoot "dbm-setup.sh") -Raw) -replace "`r`n", "`n"
    $script | kubectl exec -i -n dogsworld $pod -- sh -c 'cat > /tmp/dbm-setup.sh && sh /tmp/dbm-setup.sh'
    Run "dbm-setup"
}

# --- 5. Datadog Agent ---
if (-not $NoDatadog) {
    Step "DatadogAgent (site $Site, cluster $ClusterName, env $Env)"
    $agent = Get-Content (Join-Path $k8s "datadog-agent.yaml") -Raw
    $agent = $agent -replace 'clusterName: .+', "clusterName: $ClusterName"
    $agent = $agent -replace 'site: .+', "site: $Site"
    $agent = $agent -replace '"env:dev"', "`"env:$Env`""
    ApplyText $agent
    kubectl apply -f (Join-Path $k8s "datadog-dbm-rbac.yaml"); Run "rbac dbm"
}

# --- 6. Aplikasi ---
Step "Aplikasi"
$apps = @("dogsworld-dotnet", "dogsworld-js")
foreach ($app in $apps) {
    $text = Get-Content (Join-Path $k8s "$app.yaml") -Raw
    $text = $text -replace 'tags\.datadoghq\.com/env: dev', "tags.datadoghq.com/env: $Env"
    if ($LocalImages) {
        $ver = [regex]::Match($text, "ghcr\.io/bongcoy/${app}:([\w.]+)").Groups[1].Value
        $engine = if (Get-Command podman -ErrorAction SilentlyContinue) { "podman" } else { "docker" }
        & $engine build -t "localhost/${app}:$ver" (Join-Path $root "apps\$app"); Run "build $app"
        minikube image load "localhost/${app}:$ver"; Run "image load $app"
        $text = $text -replace "ghcr\.io/bongcoy/${app}:", "localhost/${app}:"
    }
    ApplyText $text
}
foreach ($app in $apps) { kubectl rollout status deployment/$app -n dogsworld --timeout=300s; Run "rollout $app" }

# SSI hanya menyuntik saat pod dibuat. Kalau Agent baru siap setelah pod app, restart sekali.
if (-not $NoDatadog) {
    Step "Menunggu Cluster Agent, lalu restart app agar tracer disuntik"
    kubectl rollout status deployment/datadog-cluster-agent -n datadog --timeout=300s 2>$null
    foreach ($app in $apps) { kubectl rollout restart deployment/$app -n dogsworld | Out-Null }
    foreach ($app in $apps) { kubectl rollout status deployment/$app -n dogsworld --timeout=300s | Out-Null }
}

Step "Selesai"
kubectl get pods -n dogsworld
if (-not $NoDatadog) { kubectl get pods -n datadog }
Write-Host ""
Write-Host "Akses dari laptop (terminal terpisah):"
Write-Host "  kubectl port-forward svc/dogsworld-dotnet 8080:80 -n dogsworld"
Write-Host "  kubectl port-forward svc/dogsworld-js 8081:80 -n dogsworld"
