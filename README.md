# DogsWorld

Proyek belajar **Podman, Kubernetes, Helm, dan Datadog** lewat praktik. Beberapa aplikasi CRUD "anjing" dengan kontrak API yang sama dijalankan di cluster minikube dan di-instrument Datadog APM memakai **Single Step Instrumentation (SSI)**.

Dokumen lain:
- [`PLAN.md`](PLAN.md): rencana, checklist, dan catatan progres (sumber kebenaran).
- [`AGENTS.md`](AGENTS.md): panduan untuk agent AI, berisi gotcha dan konvensi.

## Struktur repo

Repo ini **monorepo**: semua aplikasi dan konfigurasi deploy-nya ada di satu repo.

```
DogsWorld/
├── README.md
├── AGENTS.md
├── PLAN.md
├── apps/
│   ├── dogsworld-dotnet/   .NET Core 3.1 (ASP.NET + EF Core), port 8080
│   ├── dogsworld-js/       Node 20 (Express + mssql), port 8080
│   └── dogsworld-java/     Java (Javalin), belum dibuat (Fase 7)
├── k8s/                    manifest Kubernetes yang dipakai bersama
└── .archify/               diagram arsitektur dan sequence (HTML)
```

Setiap aplikasi punya `Dockerfile` dan `.dockerignore` sendiri. Konteks build adalah folder aplikasinya.

## Gambaran besar

| Namespace | Komponen | Keterangan |
|---|---|---|
| `dogsworld` | `dogsworld-dotnet` (.NET) | Disuntik tracer oleh SSI |
| `dogsworld` | `dogsworld-js` (Node) | Disuntik tracer oleh SSI |
| `dogsworld` | `sqlserver` | SQL Server 2019 Express, data disimpan di PVC. Tidak disuntik |
| `dogsworld` | `db-init` | Job sekali jalan yang membuat database `Dogs` dan tabel `dbo.Dog` |
| `datadog` | Operator, Agent, Cluster Agent | Mengirim data ke `ap1.datadoghq.com` |

Semua aplikasi memakai **database yang sama**. Menghapus data dari satu aplikasi juga menghapusnya untuk aplikasi lain. Itu disengaja untuk bahan belajar.

## Kontrak API

Sama untuk semua aplikasi. JSON memakai camelCase: `id`, `name`, `breed`, `age`, `birthDate`, `hasOwner`.

| Method | Path | Hasil |
|---|---|---|
| GET | `/api/dogs` | 200, daftar dog |
| GET | `/api/dogs/{id}` | 200, atau 404 |
| POST | `/api/dogs` | 201 + header `Location` |
| PUT | `/api/dogs/{id}` | 204. 400 jika id URL tidak cocok dengan body, 404 jika tidak ada |
| DELETE | `/api/dogs/{id}` | 200 berisi dog yang dihapus, atau 404 |

Swagger UI ada di `/swagger/index.html` pada setiap aplikasi.

## Prasyarat

Windows dengan PowerShell, lalu:

- Podman (VM WSL, mode rootful)
- minikube, kubectl, Helm
- Akun Datadog dengan API key (site `ap1.datadoghq.com`)

RAM yang dibutuhkan sekitar 5,5 GB untuk seluruh cluster. Tutup aplikasi berat sebelum mulai.

Di PowerShell yang baru dibuka, PATH kadang belum diperbarui. Jalankan ini dulu:

```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
```

## Menjalankan dari nol

### 1. Cluster

```powershell
minikube start --driver=podman --container-runtime=cri-o --cpus=4 --memory=4096
kubectl get nodes
```

### 2. Datadog Operator dan Agent

```powershell
helm repo add datadog https://helm.datadoghq.com
helm repo update
helm install datadog-operator datadog/datadog-operator -n datadog --create-namespace
```

Buat Secret API key **sendiri**. Ganti `<API_KEY>` dengan key kamu. Jangan menempelkan key ke chat, file, atau log.

```powershell
kubectl create secret generic datadog-secret -n datadog --from-literal api-key=<API_KEY>
kubectl apply -f k8s/datadog-agent.yaml
kubectl get pods -n datadog
```

### 3. Namespace, SQL Server, dan database

```powershell
kubectl apply -f k8s/namespace.yaml
kubectl create secret generic sqlserver-secret -n dogsworld --from-literal sa-password=<PASSWORD_BARU>
kubectl apply -f k8s/sqlserver.yaml
kubectl apply -f k8s/db-init-job.yaml
```

Ganti `<PASSWORD_BARU>` dengan password kuat pilihanmu. Password tidak ditulis di file YAML mana pun.

### 4. Build dan muat image

Image dibangun di Podman, lalu dimuat ke minikube.

```powershell
podman build -t dogsworld-dotnet:1.1 apps/dogsworld-dotnet
podman build -t dogsworld-js:1.1 apps/dogsworld-js
minikube image load localhost/dogsworld-dotnet:1.1
minikube image load localhost/dogsworld-js:1.1
```

### 5. Deploy aplikasi

```powershell
kubectl apply -f k8s/dogsworld-dotnet.yaml
kubectl apply -f k8s/dogsworld-js.yaml
kubectl get pods -n dogsworld
```

Pod aplikasi yang sehat berstatus `Running`. Kalau tracer SSI tidak muncul di pod, jalankan `kubectl rollout restart deployment <nama> -n dogsworld`. Suntikan hanya terjadi saat pod dibuat.

### 6. Akses dari laptop

Jalankan di terminal terpisah. Port-forward berhenti kalau terminal ditutup atau pod dibuat ulang.

```powershell
kubectl port-forward svc/dogsworld-dotnet 8080:80 -n dogsworld
kubectl port-forward svc/dogsworld-js 8081:80 -n dogsworld
```

| Aplikasi | URL |
|---|---|
| .NET | http://localhost:8080/swagger/index.html |
| JS | http://localhost:8081/swagger/index.html |

### 7. Lihat hasilnya di Datadog

Panggil `/api/dogs` beberapa kali, lalu buka `ap1.datadoghq.com`:
- **APM → Services**: service aplikasi dengan env `dev`.
- **Infrastructure → Kubernetes**: cluster `dogsworld-minikube`.

## Perintah yang sering dipakai

```powershell
minikube status
kubectl get pods -n dogsworld
kubectl get pods -n datadog
kubectl exec <pod-agent> -n datadog -c agent -- agent status
kubectl rollout restart deployment <nama> -n <namespace>
```

## Konvensi

- **Nama image lokal:** `localhost/<nama>:<versi>`. Naikkan tag (misalnya `1.0` ke `1.1`) setiap build ulang, lalu perbarui `image` dan label `tags.datadoghq.com/version` di manifest. Image dengan tag yang sama bisa tidak tertimpa di minikube.
- **Label di setiap Deployment:** `tags.datadoghq.com/env`, `tags.datadoghq.com/service`, `tags.datadoghq.com/version`.
- **Tracer:** jangan dipasang manual di Dockerfile. SSI menyuntiknya.
- **Secret:** dibuat lewat `kubectl`, tidak pernah ditulis di YAML.

## Menghemat RAM

```powershell
minikube stop     # jeda cluster, data tetap ada
minikube delete   # hapus cluster, mulai dari nol
```

## Diagram

- [`dogsworld-architecture.html`](.archify/architecture-dogsworld-20261021-231326/dogsworld-architecture.html): arsitektur.
- [`dogsworld-request-sequence.html`](.archify/sequence-dogsworld-request-20261021-231326/dogsworld-request-sequence.html): alur satu request.

Dibuat dengan skill Archify. Untuk membuat ulang, lihat gotcha Node 20 di `AGENTS.md`.

Buka file HTML itu langsung di browser.
