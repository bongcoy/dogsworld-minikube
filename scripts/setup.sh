#!/usr/bin/env bash
# Menyiapkan seluruh DogsWorld di cluster minikube (macOS atau Linux). Padanan scripts/setup.ps1.
# Aman dijalankan ulang: Secret yang sudah ada tidak ditimpa.
#
# Contoh:
#   ./scripts/setup.sh                                          # tanya site, API key, env, clusterName
#   ./scripts/setup.sh --site ap1.datadoghq.com --env alice --cluster-name dogsworld-alice
#   ./scripts/setup.sh --no-datadog                             # tanpa Datadog sama sekali
#   ./scripts/setup.sh --skip-cluster                           # pakai cluster yang sudah jalan
#   ./scripts/setup.sh --local-images                           # build image lokal, tidak menarik dari GHCR
#
# API key: dibaca dari env DD_API_KEY, atau ditanya (input tersembunyi). Tidak ditulis ke file atau log.
set -euo pipefail

SITE=""; ENV_TAG=""; CLUSTER_NAME=""
NO_DATADOG=0; SKIP_CLUSTER=0; LOCAL_IMAGES=0
OPERATOR_VERSION="2.30.0"
DRIVER="podman"; CPUS=4; MEMORY_MB=4096

while [ $# -gt 0 ]; do
  case "$1" in
    --site) SITE="$2"; shift 2 ;;
    --env) ENV_TAG="$2"; shift 2 ;;
    --cluster-name) CLUSTER_NAME="$2"; shift 2 ;;
    --no-datadog) NO_DATADOG=1; shift ;;
    --skip-cluster) SKIP_CLUSTER=1; shift ;;
    --local-images) LOCAL_IMAGES=1; shift ;;
    --operator-version) OPERATOR_VERSION="$2"; shift 2 ;;
    --driver) DRIVER="$2"; shift 2 ;;
    --cpus) CPUS="$2"; shift 2 ;;
    --memory-mb) MEMORY_MB="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Opsi tidak dikenal: $1" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K8S="$ROOT/k8s/base"
K8S_MINIKUBE="$ROOT/k8s/overlays/minikube"

step() { printf '\n== %s\n' "$1"; }
secret_exists() { kubectl get secret "$2" -n "$1" >/dev/null 2>&1; }
new_password() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; }

for tool in kubectl helm minikube; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool belum terpasang atau belum ada di PATH" >&2; exit 1; }
done

if [ "$NO_DATADOG" -eq 0 ]; then
  [ -n "$SITE" ] || read -r -p "Datadog site (contoh: ap1.datadoghq.com, datadoghq.com, us5.datadoghq.com): " SITE
  [ -n "$ENV_TAG" ] || read -r -p "Nilai tag env (contoh: dev, atau namamu): " ENV_TAG
  [ -n "$CLUSTER_NAME" ] || read -r -p "Nama cluster di Datadog (contoh: dogsworld-namamu): " CLUSTER_NAME
  if [ -z "$SITE" ] || [ -z "$ENV_TAG" ] || [ -z "$CLUSTER_NAME" ]; then
    echo "Site, env, dan clusterName tidak boleh kosong" >&2; exit 1
  fi
  case "$ENV_TAG" in
    [a-z]*) ;;
    *) echo "env harus diawali huruf kecil (lihat TAGS.md)" >&2; exit 1 ;;
  esac
  if printf '%s' "$ENV_TAG" | grep -q '[^a-z0-9_./-]'; then
    echo "env hanya boleh huruf kecil, angka, _ . / - (lihat TAGS.md)" >&2; exit 1
  fi
else
  ENV_TAG="dev"
fi

# sed -e aman untuk BSD (macOS) dan GNU. Pemisah '|' dipakai karena nilai tidak memuat '|'.
subst_env() { sed -e "s|tags.datadoghq.com/env: dev|tags.datadoghq.com/env: ${ENV_TAG}|g"; }

# --- 1. Cluster ---
if [ "$SKIP_CLUSTER" -eq 0 ]; then
  step "Cluster minikube (driver $DRIVER)"
  minikube start --driver="$DRIVER" --container-runtime=cri-o --cpus="$CPUS" --memory="$MEMORY_MB"
fi
kubectl get nodes

# --- 2. Datadog Operator ---
if [ "$NO_DATADOG" -eq 0 ]; then
  step "Datadog Operator $OPERATOR_VERSION"
  helm repo add datadog https://helm.datadoghq.com >/dev/null 2>&1 || true
  helm repo update >/dev/null
  helm upgrade --install datadog-operator datadog/datadog-operator -n datadog --create-namespace --version "$OPERATOR_VERSION" --wait

  if ! secret_exists datadog datadog-secret; then
    KEY="${DD_API_KEY:-}"
    if [ -z "$KEY" ]; then
      read -r -s -p "Datadog API key (tidak ditampilkan): " KEY; echo
    fi
    [ -n "$KEY" ] || { echo "API key kosong" >&2; exit 1; }
    kubectl create secret generic datadog-secret -n datadog --from-literal=api-key="$KEY" >/dev/null
    KEY=""
    echo "Secret datadog-secret dibuat."
  else
    echo "Secret datadog-secret sudah ada, dipakai ulang."
  fi
fi

# --- 3. Namespace dan Secret database ---
step "Namespace dan Secret"
kubectl apply -f "$K8S/namespace.yaml"
if ! secret_exists dogsworld postgres-secret; then
  kubectl create secret generic postgres-secret -n dogsworld --from-literal=password="$(new_password)" >/dev/null
  echo "Secret postgres-secret dibuat (password acak)."
fi
if [ "$NO_DATADOG" -eq 0 ] && ! secret_exists dogsworld datadog-pg-secret; then
  kubectl create secret generic datadog-pg-secret -n dogsworld --from-literal=password="$(new_password)" >/dev/null
  echo "Secret datadog-pg-secret dibuat (password acak)."
fi

# --- 4. Postgres ---
step "PostgreSQL"
subst_env <"$K8S/postgres.yaml" | kubectl apply -f -
kubectl rollout status deployment/postgres -n dogsworld --timeout=300s

if [ "$NO_DATADOG" -eq 0 ]; then
  step "Setup user datadog untuk Database Monitoring"
  POD="$(kubectl get pod -n dogsworld -l app=postgres -o jsonpath='{.items[0].metadata.name}')"
  kubectl exec -i -n dogsworld "$POD" -- sh -c 'cat > /tmp/dbm-setup.sh && sh /tmp/dbm-setup.sh' <"$ROOT/scripts/dbm-setup.sh"
fi

# --- 5. Datadog Agent ---
if [ "$NO_DATADOG" -eq 0 ]; then
  step "DatadogAgent (site $SITE, cluster $CLUSTER_NAME, env $ENV_TAG)"
  sed -e "s|clusterName: .*|clusterName: ${CLUSTER_NAME}|" \
      -e "s|site: .*|site: ${SITE}|" \
      -e "s|\"env:dev\"|\"env:${ENV_TAG}\"|" \
      "$K8S_MINIKUBE/datadog-agent.yaml" | kubectl apply -f -
  kubectl apply -f "$K8S/datadog-dbm-rbac.yaml"
fi

# --- 6. Aplikasi ---
step "Aplikasi"
APPS="dogsworld-dotnet dogsworld-js"
for app in $APPS; do
  if [ "$LOCAL_IMAGES" -eq 1 ]; then
    VER="$(sed -n "s|.*ghcr.io/bongcoy/${app}:\([0-9A-Za-z.]*\).*|\1|p" "$K8S/$app.yaml" | head -n1)"
    ENGINE="docker"; command -v podman >/dev/null 2>&1 && ENGINE="podman"
    "$ENGINE" build -t "localhost/${app}:${VER}" "$ROOT/apps/$app"
    minikube image load "localhost/${app}:${VER}"
    subst_env <"$K8S/$app.yaml" | sed -e "s|ghcr.io/bongcoy/${app}:|localhost/${app}:|" | kubectl apply -f -
  else
    subst_env <"$K8S/$app.yaml" | kubectl apply -f -
  fi
done
for app in $APPS; do kubectl rollout status "deployment/$app" -n dogsworld --timeout=300s; done

# SSI hanya menyuntik saat pod dibuat. Restart sekali agar tracer ikut disuntik.
if [ "$NO_DATADOG" -eq 0 ]; then
  step "Menunggu Cluster Agent, lalu restart app agar tracer disuntik"
  kubectl rollout status deployment/datadog-cluster-agent -n datadog --timeout=300s || true
  for app in $APPS; do kubectl rollout restart "deployment/$app" -n dogsworld >/dev/null; done
  for app in $APPS; do kubectl rollout status "deployment/$app" -n dogsworld --timeout=300s >/dev/null; done
fi

step "Selesai"
kubectl get pods -n dogsworld
[ "$NO_DATADOG" -eq 0 ] && kubectl get pods -n datadog
echo
echo "Akses dari laptop (terminal terpisah):"
echo "  kubectl port-forward svc/dogsworld-dotnet 8080:80 -n dogsworld"
echo "  kubectl port-forward svc/dogsworld-js 8081:80 -n dogsworld"
