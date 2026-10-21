# AGENTS.md

Panduan untuk agent yang bekerja di repo ini. Baca file ini dulu, lalu baca `PLAN.md` sebelum mengerjakan apa pun.

## 1. Rangkuman sesi

**Tujuan pengguna:** belajar Podman, Kubernetes, Helm, dan Datadog lewat praktik. Pengguna pemula, jadi setiap langkah dan istilah perlu dijelaskan.

**Yang sudah dibangun:**
- Aplikasi **DogsWorld** (.NET Core 3.1, ASP.NET + EF Core + SQL Server) di `apps/dogsworld-dotnet/`. Berjalan di cluster minikube dan di-instrument Datadog APM dengan **Single Step Instrumentation (SSI)** lewat **Datadog Operator**.
- Aplikasi **dogsworld-js** (Express + `mssql`) di `apps/dogsworld-js/`. CRUD-nya sama dengan .NET dan memakai database yang sama. Sudah ter-instrument SSI.
- Rencana untuk aplikasi **dogsworld-java** (Javalin + `mssql-jdbc`) di namespace `dogsworld-java-test`. Belum dibuat (Fase 7).
- Diagram arsitektur dan sequence dibuat dengan skill Archify (lolos validate, deliver, check, dan browser-check) di `.archify/`.

**Status terkini:**
- Fase 1 sampai 5 selesai.
- Fase 6 (JS) selesai, kecuali item 6.8: pengecekan di UI Datadog belum dikonfirmasi pengguna. Agent sudah menerima trace dari `nodejs v20.20.2` (tracer 5.132.0).
- Fase 7 (Java) dan Fase 8 (pengamatan bersama) belum dikerjakan.

**Topologi di cluster:**

| Namespace | Pod | Container | Catatan |
|---|---|---|---|
| `dogsworld` | `dogsworld-dotnet-*` | `dogsworld-dotnet` | .NET, disuntik SSI (js dan dotnet) |
| `dogsworld` | `dogsworld-js-*` | `dogsworld-js` | Node, disuntik SSI (js dan dotnet) |
| `dogsworld` | `sqlserver-*` | `sqlserver` | SQL Server 2019 Express, tidak disuntik |
| `dogsworld` | `db-init-*` | `sqlcmd` | Job sekali jalan, tidak disuntik |
| `datadog` | `datadog-agent-*` | `agent`, `trace-agent`, `system-probe` | DaemonSet, 1 pod per node |
| `datadog` | `datadog-cluster-agent-*` | `cluster-agent` | |
| `datadog` | `datadog-operator-*` | `datadog-operator` | |

Cluster hanya punya 1 node: `minikube`, yang juga control plane.

**Konsep yang sudah dijelaskan ke pengguna:**
- Pod, Deployment, dan kapan pod baru dibuat. Container dalam satu pod berbagi jaringan dan volume (pola sidecar). Pisahkan jadi pod berbeda jika komponen bisa di-scale atau di-update sendiri.
- Cluster adalah kumpulan node ditambah control plane. Banyak cluster dikelola lewat context `kubectl`.
- Namespace adalah pengelompokan nama. Secret dan Service DNS terikat namespace (`sqlserver.dogsworld.svc.cluster.local`).
- SSI: `DatadogAgent` dengan `targets` memilih workload lewat namespace dan `ddTraceVersions` memilih bahasa. Cluster Agent menyuntik init container lewat admission webhook. Tracer dipasang ke pod dan diaktifkan lewat `LD_PRELOAD`.
- Port-forward bisa dibuat dari Podman Desktop (Kubernetes → Services → Forward...) atau dengan `kubectl port-forward`.

## 2. Informasi tambahan yang perlu didokumentasikan

### Lingkungan
- OS: Windows. Shell: PowerShell. Runtime container: Podman 6.1.4 (VM WSL `podman-machine-default`, rootful).
- Cluster: `minikube start --driver=podman --container-runtime=cri-o --cpus=4 --memory=4096`.
- Helm 4.3.1, minikube 1.39.0, Datadog Operator 2.30.0 (app 1.31.1).
- Datadog site: `ap1.datadoghq.com`. Secret API key (`datadog-secret`) dibuat sendiri oleh pengguna di namespace `datadog`.
- RAM Windows sekitar 15,4 GB. Pada pengecekan terakhir hanya ~2,8 GB bebas. VM WSL sekitar 7,6 GB.

### Aturan kerja
- **API key tidak boleh masuk chat, file, atau log.** Pengguna sendiri yang mengetiknya.
- **Secret tidak boleh ditampilkan isinya.** Untuk membuat salinan Secret, gunakan cara yang tidak menampilkan nilainya.
- Perubahan progress checklist atau plan project **wajib dicatat di `PLAN.md`** (lihat bagian 3).
- Jangan menambah tracer manual ke Dockerfile. Tracer disuntik lewat SSI. Dockerfile .NET punya komentar yang melarang `CORECLR_*`.
- Repo ini monorepo: setiap aplikasi ada di `apps/<nama>/` dengan Dockerfile dan `.dockerignore` sendiri. Konteks build adalah folder aplikasi itu, bukan root, jadi `.dockerignore` tidak perlu mengecualikan `k8s/`, `apps/`, atau `.archify/`.
- `AGENTS.md` dan `PLAN.md` tetap di root repo.

### Gotcha yang sudah ditemukan
- **Suntikan SSI hanya terjadi saat pod dibuat.** Setelah mengubah `targets` atau `ddTraceVersions`, jalankan `kubectl rollout restart deployment <nama> -n <namespace>`.
- **Pod yang dibuat saat Cluster Agent sedang diganti bisa tidak mendapat tracer yang diharapkan.** Solusinya: rollout restart.
- **Pod yang di-inject hanya mendapat tracer untuk bahasa yang ada di `ddTraceVersions` dan cocok dengan workload.** Pod `sqlserver` dan `db-init` tidak disuntik.
- **Aturan target dievaluasi berurutan**, target pertama yang cocok yang dipakai. Blok `DatadogInstrumentation` per workload butuh Agent/Cluster Agent 7.85+.
- **Bahasa `ddTraceVersions` yang didukung:** `java`, `js`, `python`, `dotnet`, `ruby`, `php`, `c`.
- **Port-forward berhenti** saat terminal ditutup, pod dibuat ulang, atau minikube di-stop. "Not found" di Swagger sebelumnya disebabkan forward yang mati.
- **PATH tidak diperbarui di shell baru.** Setiap perintah PowerShell perlu:
  ```powershell
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
  ```
- **`kubectl -o jsonpath` dengan `\n` gagal di PowerShell.** Gunakan `-o json` lalu `ConvertFrom-Json`.
- **Jalankan Archify dengan Node 20, bukan Node 22.** Node aktif di komputer ini 22.14.0, yang punya bug: `fs.lstat` mengembalikan `dev = 0` sedangkan `fstat` mengembalikan device asli, sehingga Archify gagal dengan `finalize-receipt-changed-during-inspection` dan `output/target-changed`. Node 20.20.2 sudah terpasang lewat nvm. Panggil langsung tanpa mengganti Node aktif: `& "$env:LOCALAPPDATA\nvm\v20.20.2\node.exe" <path-skill>\bin\archify.mjs finalize ...`. Candidate dan HTML hasilnya ada di `.archify/<tipe>-<slug>-<timestamp>/`.
- **Build Maven untuk Java** adalah bagian paling berat. Tutup aplikasi lain sebelum build.
- **Data database dipakai bersama** oleh semua aplikasi. DELETE dari satu aplikasi menghapus data untuk yang lain. Itu disengaja untuk pelajaran.

### Struktur file
```
DogsWorld/
├── README.md                         (pengantar, struktur repo, cara menjalankan dari nol)
├── AGENTS.md                         (file ini)
├── PLAN.md                           (rencana dan checklist, sumber kebenaran progress)
├── apps/
│   ├── dogsworld-dotnet/             (DogsWorld .NET, dulu di root repo)
│   │   ├── DogsWorld.sln, DogsWorld.csproj
│   │   ├── Dockerfile                (tanpa tracer manual)
│   │   ├── .dockerignore             (bin, obj, .vs, *.md, *.user, .git)
│   │   ├── Controllers/DogsController.cs  (kontrak API acuan)
│   │   ├── Models/Dog.cs, Data/DogsWorldContext.cs
│   │   ├── Startup.cs                (Swagger aktif di luar IsDevelopment)
│   │   └── appsettings.json          (connection string untuk jalan lokal)
│   └── dogsworld-js/
│       ├── package.json              (express, mssql, swagger-ui-express)
│       ├── src/server.js             (CRUD /api/dogs, Swagger di /swagger)
│       ├── src/openapi.json          (spesifikasi OpenAPI manual, update jika endpoint berubah)
│       ├── Dockerfile                (node:20-slim, user node)
│       └── .dockerignore             (node_modules/)
├── k8s/
│   ├── datadog-agent.yaml            (DatadogAgent, SSI, targets namespace dogsworld)
│   ├── dogsworld-dotnet.yaml         (Deployment + Service .NET, label UST)
│   ├── dogsworld-js.yaml             (Deployment + Service JS, label UST)
│   ├── sqlserver.yaml                (PVC, Deployment, Service SQL Server)
│   └── db-init-job.yaml              (Job pembuat database Dogs dan tabel dbo.Dog)
└── .archify/
    ├── architecture-dogsworld-20261021-231326/   (Diagram 1: candidate.json + dogsworld-architecture.html)
    └── sequence-dogsworld-request-20261021-231326/ (Diagram 2: candidate.json + dogsworld-request-sequence.html)
```

### Konvensi
- **Satu nama per aplikasi:** `dogsworld-<bahasa>` (`dogsworld-dotnet`, `dogsworld-js`, `dogsworld-java`) dipakai untuk folder `apps/`, image, Deployment, Service, container, label `app`, file manifest `k8s/`, dan service Datadog (`tags.datadoghq.com/service`). Nama service Datadog .NET dulu `dogsworld-app`.
- **Nama image lokal:** `localhost/<nama>:<versi>`, lalu `minikube image load`.
- **Label UST di setiap Deployment:** `tags.datadoghq.com/env`, `tags.datadoghq.com/service`, `tags.datadoghq.com/version`. `service` harus sama dengan nama aplikasi.
- **Koneksi database:** host `sqlserver` untuk namespace `dogsworld`. Password dari Secret `sqlserver-secret` (key `sa-password`), tidak pernah ditulis di YAML.
- **Port lokal untuk port-forward:** 8080 (.NET), 8081 (JS), 8082 (Java, rencana).
- **Swagger:** setiap aplikasi menyediakan UI di `/swagger/index.html` (.NET di 8080, JS di 8081, Java direncanakan, item 7.10 di `PLAN.md`). Di JS, `src/openapi.json` ditulis manual.
- **Tag image:** naikkan tag (misalnya `1.0` menjadi `1.1`) setiap build ulang, lalu perbarui `image` dan label `tags.datadoghq.com/version` di manifest. Image dengan tag yang sama bisa tidak tertimpa di minikube. Image JS saat ini `1.1`.
- **Kontrak API** (sama untuk semua aplikasi): `GET /api/dogs`, `GET /api/dogs/{id}`, `POST /api/dogs` (201 + `Location`), `PUT /api/dogs/{id}` (204, 400 jika id tidak cocok, 404 jika tidak ada), `DELETE /api/dogs/{id}` (200 berisi dog yang dihapus, atau 404). JSON camelCase.

### Perintah yang sering dipakai
```powershell
minikube status
kubectl get pods -n dogsworld
kubectl get pods -n datadog
kubectl port-forward svc/dogsworld-dotnet 8080:80 -n dogsworld
kubectl port-forward svc/dogsworld-js 8081:80 -n dogsworld
kubectl exec <pod-agent> -n datadog -c agent -- agent status
kubectl rollout restart deployment <nama> -n <namespace>
podman build -t <nama>:1.0 apps/<nama-folder>
# contoh: podman build -t dogsworld-dotnet:1.2 apps/dogsworld-dotnet
minikube image load localhost/<nama>:1.0
```

## 3. Referensi ke PLAN.md

`PLAN.md` adalah **sumber kebenaran** untuk rencana dan progress project.

- **Setiap kali ada langkah yang selesai**, centang `[x]` di `PLAN.md` pada item yang sesuai.
- **Setiap kali ada perubahan plan** (fase baru, item dihapus, keputusan berubah), perbarui `PLAN.md`. Jangan hanya menyimpan perubahan di chat.
- **Temuan penting** (misalnya gotcha atau hasil uji teori) dicatat di bagian temuan atau perubahan di `PLAN.md`.
- Item yang belum dikonfirmasi pengguna tidak dicentang.
- Sebelum mulai kerja baru, baca `PLAN.md` untuk melihat fase dan item berikutnya.

## 4. Langkah berikutnya

1. Pengguna memeriksa UI Datadog (`ap1.datadoghq.com`):
   - APM → Services: `dogsworld-js` dengan env `dev`.
   - Trace JS berisi span SQL dari `mssql`.
   - Infrastructure → Kubernetes: cluster `dogsworld-minikube`.
2. Setelah konfirmasi, centang 6.8 di `PLAN.md`.
3. Lanjut ke Fase 7 (Java, namespace `dogsworld-java-test`). Ikuti urutan dan uji teori di `PLAN.md`.
4. Fase 8 (pengamatan bersama) setelah dua aplikasi tambahan berjalan.
5. Fase 5 (`minikube stop`) jika RAM perlu dibebaskan.
