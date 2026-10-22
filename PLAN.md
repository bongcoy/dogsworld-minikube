# Plan: Instrumentasi DogsWorld (.NET) di Kubernetes (minikube + Podman) dengan Datadog

Dokumen ini adalah rencana dan checklist pekerjaan. Centang `[x]` setiap langkah yang sudah selesai.

## 1. Tujuan

Menjalankan aplikasi **DogsWorld** (.NET Core 3.1, ASP.NET + EF Core + SQL Server) di cluster Kubernetes lokal (minikube di atas Podman), lalu meng-instrument-nya dengan **Datadog APM** memakai **Single Step Instrumentation (SSI)** lewat **Datadog Operator**. Trace dikirim ke site **ap1.datadoghq.com**.

Tujuan kedua adalah belajar: container, Podman, Kubernetes, Helm, dan Datadog.

## 2. Keputusan

| Topik | Keputusan |
|---|---|
| Container runtime | Podman 6.1.4 (VM WSL `podman-machine-default`, rootful) |
| Cluster Kubernetes | minikube, driver `podman`, runtime `cri-o` |
| Package manager K8s | Helm (belum terpasang, dipasang via winget) |
| Cara instrumentasi | Single Step Instrumentation (SSI) lewat Datadog Operator |
| Datadog site | `ap1.datadoghq.com` |
| Aplikasi | DogsWorld, .NET Core 3.1 (folder ini) |
| Database | SQL Server sebagai Pod di dalam cluster |
| Install Operator | `helm install` (instalasi pertama), bukan `helm upgrade` |

## 3. Kondisi awal (hasil pengecekan)

- Podman 6.1.4 terpasang, VM `podman-machine-default` jalan dan sudah rootful.
- `kubectl` 1.37 terpasang (Chocolatey). Belum ada cluster atau context.
- Helm, minikube, dan kind belum terpasang.
- RAM laptop 15,4 GB, bebas sekitar 3,5 GB. Mepet, tutup aplikasi berat sebelum mulai.
- File `%USERPROFILE%\.wslconfig` belum ada. Batas memori WSL memakai default (50% RAM, sekitar 7,7 GB).

## 4. Temuan pada aplikasi

1. `Dockerfile` memasang tracer Datadog secara manual (`CORECLR_PROFILER`, `DD_AGENT_HOST=datadog-agent`). Ini bentrok dengan SSI, jadi harus dihapus.
2. Dockerfile mengunduh tracer versi terbaru, sedangkan `DogsWorld.csproj` memakai NuGet `Datadog.Trace 2.1.0`. Versinya bisa tidak cocok dengan tracer SSI.
3. `appsettings.json` berisi connection string ke `DESKTOP-IB1AF6A` lengkap dengan password. Tidak terjangkau dari cluster dan tidak aman di file teks.
4. Target `netcoreapp3.1` sudah end-of-life. Image `mcr.microsoft.com/dotnet/core/*:3.1` bisa saja sudah tidak tersedia.

## 5. Perkiraan RAM

| Komponen | RAM |
|---|---|
| minikube (K8s) | ~2 GB |
| Datadog Operator + Agent + Cluster Agent | ~1 GB |
| SQL Server | ~2 GB (minimum Microsoft) |
| DogsWorld | ~0,3 GB |
| **Total** | **~5,5 GB** |

## 6. Risiko yang harus diverifikasi

- [x] SSI untuk .NET mendukung .NET Core 3.1 (cek dokumentasi Datadog).
- [x] Versi NuGet `Datadog.Trace` cocok dengan tracer yang disuntikkan SSI. Kalau tidak, sesuaikan atau hapus.
- [x] Image dasar .NET 3.1 masih bisa diunduh. Kalau tidak, pakai tag yang tersedia.
- [x] RAM cukup. Kalau tidak, kurangi memori minikube atau batasi WSL.
- [x] `Program.cs` atau migrasi EF membuat database dan tabel. Kalau tidak, jalankan migrasi manual.

## 7. Checklist pekerjaan

### Fase 1: Persiapan alat
- [x] 1.1 Cek batas memori WSL (hasil: VM Linux sudah punya ~7,6 GB, `.wslconfig` tidak perlu dibuat)
- [x] 1.2 Pasang Helm: `winget install Helm.Helm`
- [x] 1.3 Pasang minikube: `winget install Kubernetes.minikube`
- [x] 1.4 Buka ulang terminal, cek `helm version`, `minikube version`, `kubectl version --client`, `podman --version`

### Fase 2: Cluster dan Datadog
- [x] 2.1 `minikube start --driver=podman --container-runtime=cri-o --cpus=4 --memory=4096`
- [x] 2.2 `kubectl get nodes` menunjukkan node `Ready`
- [x] 2.3 `helm repo add datadog https://helm.datadoghq.com` dan `helm repo update`
- [x] 2.4 `helm install datadog-operator datadog/datadog-operator -n datadog --create-namespace`
- [x] 2.5 Pod operator `Running` (`kubectl get pods -n datadog`)
- [x] 2.6 Pengguna membuat Secret API key sendiri (key tidak lewat chat):
  `kubectl create secret generic datadog-secret -n datadog --from-literal api-key=<API_KEY>`
- [x] 2.7 Buat `k8s/datadog-agent.yaml` (site `ap1.datadoghq.com`, SSI aktif, target namespace `dogsworld`, `kubelet.tlsVerify: false` untuk minikube)
- [x] 2.8 `kubectl apply -f k8s/datadog-agent.yaml`
- [x] 2.9 Pod `datadog-agent-*` dan `datadog-cluster-agent-*` berstatus `Running`

### Fase 3: Aplikasi
- [x] 3.1 Ubah `Dockerfile`: hapus tracer manual dan semua `CORECLR_*` serta `DD_AGENT_HOST`; perbaiki base image kalau perlu
- [x] 3.2 Pindahkan connection string ke environment variable; password dari Kubernetes Secret (bukan di `appsettings.json`)
- [x] 3.3 Sesuaikan versi `Datadog.Trace` di `.csproj` kalau perlu
- [x] 3.4 Buat `k8s/namespace.yaml`
- [x] 3.5 Buat `k8s/sqlserver.yaml` (Secret, PVC, Deployment, Service)
- [x] 3.6 Buat `k8s/dogsworld.yaml` (Deployment + Service, label `tags.datadoghq.com/env|service|version`)
- [x] 3.7 `podman build -t dogsworld:1.0 .`
- [x] 3.8 `minikube image load dogsworld:1.0`
- [x] 3.9 Terapkan manifest, lalu pastikan pod SQL Server dan DogsWorld `Running`
- [x] 3.10 Database dan tabel dibuat lewat Job `k8s/db-init-job.yaml` (3 data contoh)
- [x] 3.11 Pastikan init container SSI muncul di pod DogsWorld (`kubectl describe pod`)

### Fase 4: Verifikasi
- [x] 4.1 Akses aplikasi (`kubectl port-forward` atau `minikube service`)
- [x] 4.2 Buka `/swagger`, panggil `/api/dogs` beberapa kali
- [x] 4.3 Buka `ap1.datadoghq.com` lalu APM, Services: `dogsworld-app` muncul
- [x] 4.4 Trace memuat span ASP.NET dan SQL
- [x] 4.5 Infrastructure, Kubernetes: cluster dan pod terlihat

### Fase 5: Pembersihan (opsional)
- [ ] 5.1 `minikube stop` saat tidak dipakai (hemat RAM)
- [ ] 5.2 `minikube delete` kalau ingin mengulang dari nol

### Fase 6: Aplikasi JS (namespace `dogsworld`)
Tujuan: DogsWorld versi JavaScript dengan CRUD sama seperti .NET, memakai database `Dogs` yang sama. Berhenti di akhir fase ini dan pastikan trace muncul sebelum lanjut ke Fase 7.

Kontrak API (sama dengan `Controllers/DogsController.cs`):

| Method | Path | Hasil |
|---|---|---|
| GET | `/api/dogs` | 200, daftar dog |
| GET | `/api/dogs/{id}` | 200, atau 404 |
| POST | `/api/dogs` | 201 + header `Location` |
| PUT | `/api/dogs/{id}` | 204. 400 kalau id URL ≠ id body, 404 kalau tidak ada |
| DELETE | `/api/dogs/{id}` | 200 berisi dog yang dihapus, atau 404 |

JSON: `id`, `name`, `breed`, `age`, `birthDate`, `hasOwner`. Tabel: `Dogs.dbo.Dog`. Tag kustom `username` dan `dog_request_id` dari app .NET tidak ditiru.

- [x] 6.1 Buat `apps/dogsworld-js/` (Express + `mssql`, `package.json`, `Dockerfile` berbasis `node:20-slim`)
- [x] 6.2 `podman build -t dogsworld-js:1.0 apps/dogsworld-js` lalu `minikube image load`
- [x] 6.3 Buat `k8s/dogsworld-js.yaml` (Deployment + Service, label `tags.datadoghq.com/*` dengan service `dogsworld-js`, memori limit 256Mi, password dari Secret `sqlserver-secret`)
- [x] 6.4 Tambahkan `js` di target `dogsworld` pada `k8s/datadog-agent.yaml`, lalu `kubectl apply`
- [x] 6.5 Deploy app JS, pastikan init container `datadog-lib-js-init` muncul
- [x] 6.6 Uji teori: apakah pod `sqlserver` tetap tidak disuntik setelah `js` ditambahkan (hasil: tetap tidak disuntik)
- [x] 6.7 Uji CRUD lewat `kubectl port-forward svc/dogsworld-js 8081:80 -n dogsworld`
- [x] 6.8 Cek trace di Agent (`agent status`) dan di Datadog UI (APM, Services: `dogsworld-js`). Agent sudah menerima trace (terbukti), UI sudah dicek pengguna
- [x] 6.9 Tambahkan Swagger UI ke app JS (`swagger-ui-express` + `src/openapi.json` ditulis manual). Image `dogsworld-js:1.1`, buka `http://localhost:8081/swagger/index.html` setelah port-forward

### Fase 7: Aplikasi Java (namespace `dogsworld-java-test`)
- [ ] 7.1 Buat `apps/dogsworld-java/` (Javalin + `mssql-jdbc`, `pom.xml`, Dockerfile multi-stage Maven, JRE `eclipse-temurin:17-jre`)
- [ ] 7.2 `podman build -t dogsworld-java:1.0` lalu `minikube image load`
- [ ] 7.3 Buat namespace `dogsworld-java-test`
- [ ] 7.4 Uji teori: Secret `sqlserver-secret` tidak terbaca dari namespace lain. Buat salinannya di namespace baru tanpa menampilkan isinya
- [ ] 7.5 Buat `k8s/dogsworld-java.yaml` dengan koneksi ke `sqlserver.dogsworld.svc.cluster.local:1433` (memori limit 512Mi, `-Xmx256m`)
- [ ] 7.6 Uji teori: nama pendek `sqlserver` tidak bekerja dari namespace lain
- [ ] 7.7 Tambahkan target SSI `dogsworld-java-test` dengan `java` di `datadog-agent.yaml`, lalu `kubectl apply`
- [ ] 7.8 Deploy, pastikan init container `datadog-lib-java-init` muncul
- [ ] 7.9 Uji CRUD lewat port-forward 8082 dan cek trace
- [ ] 7.10 Tambahkan Swagger UI ke app Java, setara dengan .NET dan JS: UI di `/swagger/index.html` dan spesifikasi OpenAPI untuk 5 endpoint. Pilihan yang diperiksa dulu saat eksekusi (cek dokumentasi Javalin versi yang dipakai, jangan menebak): plugin OpenAPI dan Swagger milik Javalin (spesifikasi dari anotasi, otomatis) atau file `openapi.json` manual dengan Swagger UI dari webjar (seperti app JS). Build ulang image dengan tag baru (`dogsworld-java:1.1`), `minikube image load`, lalu perbarui label `version` dan `image` di manifest

### Fase 8: Pengamatan bersama
- [ ] 8.1 Buat dog dari app JS, baca dari app .NET dan Java (data database bersama)
- [ ] 8.2 Datadog APM: 3 service tampil dan terhubung ke SQL Server di Service Map
- [ ] 8.3 Cek pemakaian RAM node (`kubectl describe node minikube`, RAM Windows)

Risiko Fase 6 sampai 8: RAM Windows bebas hanya sekitar 2,8 GB (build Maven paling berat). DELETE dari satu app menghapus data untuk semua app, itu disengaja.

### Fase 9: Migrasi database ke PostgreSQL (dikerjakan sebelum Fase 7)
Alasan: SQL Server 2019 dan `mssql-tools` hanya punya image amd64, jadi tidak jalan di Apple Silicon. `postgres:16`, base image .NET 3.1, dan `node:20-slim` sudah multi-arch. Keputusan: data lama (9 baris) dipindahkan sebagai seed, tabel dibuat lewat ConfigMap `initdb`, versi .NET tetap 3.1.

- [x] 9.1 Cek dukungan arm64: SSI mendukung x86_64 dan arm64 (dokumentasi Datadog), integrasi `Npgsql` 4.0+ didukung tracer .NET, `Npgsql.EntityFrameworkCore.PostgreSQL` 3.1.18 tersedia. .NET 3.1 tidak perlu di-upgrade
- [x] 9.2 Ekspor 9 baris dari SQL Server (Id 1 sampai 9, nilai identity terakhir 12)
- [x] 9.3 Buat `k8s/postgres.yaml` (ConfigMap `init.sql` berisi skema dan seed, PVC, Deployment `postgres:16`, Service `postgres`, label `admission.datadoghq.com/enabled: "false"`)
- [ ] 9.4 Pengguna membuat Secret `postgres-secret` (key `password`) sendiri
- [x] 9.5 App .NET: `UseNpgsql`, paket `Npgsql.EntityFrameworkCore.PostgreSQL` 3.1.18, hapus paket SqlServer/Sqlite dan folder `Migrations/`
- [x] 9.6 App JS: `mssql` diganti `pg`, query memakai `$n` dan `RETURNING`
- [x] 9.7 Dockerfile multi-arch tanpa emulasi (tahap build memakai `--platform=$BUILDPLATFORM`), image `1.2` (build lokal amd64 berhasil; build arm64 diuji di Fase 11)
- [x] 9.8 Deploy, uji CRUD kedua app, data bersama, SSI masih menyuntik, span `postgresql` ada di trace
- [x] 9.9 Pengguna mengonfirmasi trace di UI Datadog
- [x] 9.10 Hapus `sqlserver`, `db-init`, PVC lama, dan `sqlserver-secret`
- [x] 9.11 Perbarui `AGENTS.md`, `README.md`, dan diagram Archify (Node 20). Diagram diubah ke PostgreSQL, di-finalize (gate lolos), SVG diekspor ulang

### Fase 10: Datadog Database Monitoring (DBM) untuk Postgres
Catatan implementasi (22 Okt):
- Postgres: `args` di `k8s/postgres.yaml` mengaktifkan `shared_preload_libraries=pg_stat_statements` dan `track_activity_query_size=4096` (diverifikasi dengan `SHOW`).
- Setup user `datadog` dijalankan lewat `kubectl exec` dengan password yang dibaca dari Secret di dalam pod. Dibuat di database `postgres` dan `dogs`.
- Koreksi: format referensi secret untuk backend `k8s.secrets` adalah `ENC[namespace/secret-name;key]`, bukan `ENC[k8s_secret@...]`.
- Agent butuh izin baca Secret lintas namespace. Ditulis di `k8s/datadog-dbm-rbac.yaml` (Role + RoleBinding di `dogsworld`).
- Hasil `agent status`: check `postgres` OK, dengan Database Monitoring Query Metrics, Query Samples, Activity Samples, dan Metadata Samples bernilai > 0.
- Peringatan yang terlihat: "APM traces invalid status code 404" di endpoint health `trace.agent`. Belum diselidiki, perlu dicek jika trace tidak masuk.
- [x] 10.1 `pg_stat_statements` aktif, user `datadog`, schema `datadog`, fungsi `explain_statement`
- [x] 10.2 Password user `datadog` di Secret `datadog-pg-secret` (key `password`, dibuat acak lewat kubectl, nilainya tidak ditampilkan), dibaca Agent lewat `ENC[dogsworld/datadog-pg-secret;password]`
- [x] 10.3 Konfigurasi check postgres dengan `dbm: true` (di `DatadogAgent` lewat `override.nodeAgent.extraConfd`)
- [x] 10.4 `DD_DBM_PROPAGATION_MODE=full` untuk .NET dan JS (didukung: dd-trace-dotnet 2.35.0+ dan dd-trace-js 3.17.0+, tracer saat ini .NET 3.56.0.0 dan JS 5.132.0)
- [ ] 10.5 Verifikasi di `agent status` dan pengguna mengonfirmasi di UI

### Fase 11: Paket untuk tim dan registry GHCR
Registry: `ghcr.io/bongcoy`, package **public** (tim tidak butuh token untuk pull). Datadog dibuat fleksibel: site, API key, `env`, dan `clusterName` ditentukan per orang oleh script setup, jadi tim bisa memakai satu org yang sama atau org berbeda.

- [ ] 11.1 Manifest menunjuk ke `ghcr.io/bongcoy/dogsworld-<bahasa>:1.2`
- [ ] 11.2 `scripts/build-push.ps1`: build multi-arch (amd64 dan arm64) lalu push (pengguna login GHCR sendiri)
- [ ] 11.3 `scripts/setup.ps1` dan `scripts/setup.sh`: cluster, Operator (versi dikunci), Datadog (site, key, env, clusterName), Postgres, app. Bisa dijalankan ulang. Ada opsi tanpa Datadog
- [ ] 11.4 README bagian "Untuk tim"
- [ ] 11.5 Pengguna mengatur package GHCR menjadi public
- [ ] 11.6 Uji di Mac Apple Silicon oleh rekan tim (tidak bisa diuji dari laptop Windows ini)

### Fase 12: Konvensi tag Datadog
Dokumen `TAGS.md` di root menjadi aturan untuk semua entity Datadog. Referensi: docs.datadoghq.com/getting_started/tagging/. Keputusan: tag wajib `env`, `service`, `version`, dan `team` (nilai `bongcoy`). Untuk infrastruktur tanpa tracer (`postgres`), cukup `env`, `service`, dan `team`.

- [x] 12.1 Buat `TAGS.md` (format, aturan penulisan, reserved keys, tag UST, tag infrastruktur, tag level cluster, matriks per entity, daftar periksa)
- [x] 12.2 `AGENTS.md`: aturan wajib tag untuk setiap entity Datadog, `TAGS.md` masuk struktur file dan konvensi UST
- [x] 12.3 `README.md`: `TAGS.md` masuk struktur repo
- [x] 12.4 Terapkan `team:bongcoy` di `k8s/datadog-agent.yaml` (`global.tags`) dan pastikan `k8s/postgres.yaml` sesuai `TAGS.md`. `team:bongcoy` sudah ada di manifest (commit `af98c9e`) dan aktif di cluster. Pod `datadog-agent-hmkhp` membawa `DD_TAGS=["env:dev","team:bongcoy"]` dan `DD_CLUSTER_NAME=dogsworld-minikube`. `postgres.yaml` sudah punya label `env:dev` dan `service:postgres` di Deployment dan pod template, jadi tidak diubah. Tidak ada `kubectl apply` baru, dan tidak ada pod yang perlu di-restart
- [x] 12.5 Audit `dogsworld-dotnet.yaml` dan `dogsworld-js.yaml` terhadap daftar periksa `TAGS.md`. Hasil: keduanya sudah punya label UST di metadata dan pod template, `service` sama dengan nama aplikasi, dan `version` `"1.2"` sama dengan tag image. Tidak ada yang perlu diubah

Temuan: label Kubernetes biasa (misalnya `team: bongcoy`) tidak otomatis menjadi tag Datadog. Hanya label `tags.datadoghq.com/*` yang dibaca Admission Controller, jadi `team` harus lewat `global.tags` di `DatadogAgent`.

## 8. Perubahan yang dilakukan di komputer

- Memasang Helm dan minikube (winget).
- Mungkin membuat atau mengubah `%USERPROFILE%\.wslconfig`.
- Mengubah `Dockerfile`, `appsettings.json`, dan mungkin `DogsWorld.csproj`.
- Membuat folder `k8s/` berisi manifest.
- Memindahkan aplikasi .NET dari root ke `apps/dogsworld-dotnet/` (`git mv`, termasuk `.sln`, `.csproj`, `Dockerfile`, `.dockerignore`, dan folder kode).
- Membuat cluster minikube sebagai container Podman.

## 9. Catatan keamanan

- API key Datadog hanya diketik pengguna sendiri, tidak masuk percakapan atau file.
- Password database tidak boleh di file yang di-commit. Pakai Kubernetes Secret.
- Password lama di `appsettings.json` sudah terlanjur tertulis di file. Ganti password itu kalau database aslinya masih dipakai.

## 10. Glosarium singkat

- **Container**: paket aplikasi beserta kebutuhannya, berjalan terisolasi.
- **Podman**: alat untuk menjalankan container (alternatif Docker).
- **Kubernetes**: sistem yang mengatur banyak container (menjalankan, restart, skala).
- **minikube**: cluster Kubernetes kecil untuk laptop.
- **kubectl**: perintah untuk berbicara dengan cluster.
- **Helm**: package manager untuk Kubernetes. Paketnya disebut chart.
- **Datadog Operator**: program di K8s yang memasang dan mengelola Datadog Agent.
- **SSI**: Single Step Instrumentation, tracer disuntikkan otomatis tanpa mengubah kode.
- **APM**: Application Performance Monitoring, merekam trace request aplikasi.

## 11. Catatan progres

- Fase 1 sampai 3 selesai. 4.1 dan 4.2 selesai: 20 request ke /api/dogs dan /api/dogs/{id} semuanya 200.
- Trace terbukti sampai di Datadog Agent: 23 trace dan 69 span dari .NET tracer 3.56 lewat SSI.
- Tersisa: Pembersihan opsional (Fase 5).
- Masalah yang ditemui: Agent CrashLoop karena TLS kubelet di minikube; diperbaiki dengan `kubelet.tlsVerify: false`.
- Perubahan Datadog.Trace NuGet: 2.1.0 menjadi 3.7.0 (versi 3.x sejalan dengan tracer SSI).
- Diagram arsitektur dan sequence dibuat dengan Archify di `.archify/*-20261021-231326/` (lihat catatan Archify di bawah).
- Pengecekan: hanya pod `dogsworld` yang disuntik SSI. Pod `sqlserver` dan `db-init` di namespace yang sama tidak.
- Fase 6 sampai 8 ditambahkan: aplikasi JS (namespace `dogsworld`) dan Java (namespace `dogsworld-java-test`).
- Fase 6 selesai kecuali cek UI. CRUD JS lolos semua (201/204/200/400/404). Agent menerima trace dari nodejs v20.20.2, tracer 5.132.0, via uds (3 trace, 28 span per menit).
- Temuan: pod JS yang dibuat saat Cluster Agent sedang diganti hanya mendapat tracer .NET. Perlu `kubectl rollout restart` supaya `datadog-lib-js-init` muncul.
- Temuan: karena target `dogsworld` kini memuat `dotnet` dan `js`, pod JS mendapat dua init container tracer (`datadog-lib-js-init` dan `datadog-lib-dotnet-init`). Tracer yang tidak cocok tidak dipakai.
- Temuan: pod `sqlserver` dan `db-init` tetap tidak disuntik meski namespace-nya sama.
- Swagger ditambahkan ke app JS (item 6.9). `/swagger/index.html` dan `/swagger/` keduanya 200, API tetap normal, pod baru tetap disuntik SSI (`datadog-lib-js-init`). Image dinaikkan ke tag `1.1` supaya `minikube image load` pasti memuat versi baru.
- Plan Swagger untuk app Java ditambahkan sebagai item 7.10.
- Fase 9 (PostgreSQL): `postgres:16` jalan, 9 baris data lama pindah dengan Id asli, sequence di 12 (Id baru mulai 13, sama seperti SQL Server). Kedua app `1.2` lolos CRUD (201/204/200/400/404), `birthDate` konsisten, dan data bersama terbukti (POST lewat JS terbaca .NET, dan sebaliknya). Init container SSI tetap muncul di kedua pod.
- Bukti trace Fase 9 (log debug tracer di pod, lalu `DD_TRACE_DEBUG` dihapus lagi): JS memunculkan span `pg.query` dengan service `dogsworld-js-postgres`; .NET memunculkan `postgres.query` dengan service `dogsworld-dotnet-postgres` (tag `db.type:postgres`, `component:Npgsql`, `db.name:dogs`, `out.host:postgres`). Agent menerima trace dari nodejs 5.132.0 dan .NET 3.56.0.0.
- Catatan: pesan `Found incompatible integration version: pg@8.23.1` hanya muncul dari proses `node -e` yang saya jalankan sendiri lewat `kubectl exec` (proses itu hanya memuat `package.json` milik `pg`, bukan `pg`). Di log aplikasi yang sebenarnya pesan itu muncul 0 kali, dan hook tracer mendukung `pg >=8.0.3`. Jadi bukan masalah, tetapi jangan menarik kesimpulan dari output `kubectl exec` yang menjalankan node baru karena SSI ikut menyuntiknya.
- Temuan: span database memakai nama service turunan per app (`dogsworld-js-postgres` dan `dogsworld-dotnet-postgres`), jadi di Datadog muncul sebagai dua database terpisah. Itu perilaku bawaan skema penamaan span v0.
- Gotcha: di PowerShell, argumen `psql -c` kehilangan tanda kutip ganda, jadi `"Dog"` terbaca `dog`. Kirim SQL lewat stdin (`@'...'@ | kubectl exec -i ... psql`).
- Restrukturisasi monorepo: aplikasi .NET dipindah ke `apps/dogsworld-dotnet/` dengan `git mv` (riwayat file terjaga). `bin/`, `obj/`, dan `.vs/` dihapus karena hasil build. `.dockerignore` dirapikan karena konteks build kini folder aplikasi, jadi tidak perlu lagi mengecualikan `k8s/`, `apps/`, `.archify/`.
- Verifikasi: `podman build apps/dogsworld-dotnet` berhasil dan menghasilkan image yang identik (semua layer dari cache). Tag `1.0` yang dipakai cluster tidak diubah.
- Path lama di item 3.x dan 4.x (misalnya `Dockerfile`, `DogsWorld.csproj`) menunjuk ke lokasi sebelum pemindahan. Itu catatan sejarah dan sengaja tidak diubah.
- `AGENTS.md` dan `PLAN.md` tetap di root repo.
- Rename app .NET ke `dogsworld-dotnet` (sebelumnya `dogsworld`; service Datadog sebelumnya `dogsworld-app`): file `k8s/dogsworld.yaml` menjadi `k8s/dogsworld-dotnet.yaml`, image `localhost/dogsworld-dotnet:1.1`, label `version` `1.1`. Deployment dan Service lama dihapus setelah yang baru terverifikasi. Hasil: pod baru `Running`, `DD_SERVICE=dogsworld-dotnet`, API mengembalikan data lama (9 baris), SSI tetap menyuntik (`datadog-lib-dotnet-init`), Agent menerima 15 trace dan 45 span dari .NET tracer 3.56.0.0. Node, cluster, namespace, PVC, dan data database tidak terpengaruh.
- Temuan: nama Deployment dan selector tidak bisa diubah di tempat, jadi rename berarti membuat objek baru lalu menghapus yang lama. `kubectl apply` tidak menghapus objek lama. Service Datadog baru muncul terpisah dari `dogsworld-app` di APM, riwayat lama tidak tersambung.
- Pembersihan image: dihapus `localhost/dogsworld:1.0`, `localhost/dogsworld-js:1.0`, `quay.io/podman/hello`, container `hello` yang sudah selesai, dan 2 image dangling (masing-masing 1,22 GB) dari Podman. `localhost/dogsworld:1.0` dan `localhost/dogsworld-js:1.0` juga dihapus dari minikube.
- Archify: dengan Node 22.14.0 `finalize` tetap gagal (`finalize-receipt-changed-during-inspection`, `output/target-changed`). Akar masalah dibuktikan tanpa Archify: `fs.lstatSync(README.md).dev` = 0 sedangkan `fs.fstatSync(...).dev` = 2999742434 untuk file yang sama. Node 20.20.2 dipasang lewat `nvm install 20.20.2` (Node aktif tetap 22.14.0). Di Node 20 `lstat` dan `fstat` sama, dan `finalize` lolos keempat gate (validate, deliver, check, browser-check) untuk kedua diagram. Hasil dibuka di browser dan dicek dengan mata: nama `dogsworld-dotnet` benar, tidak ada label yang menumpuk.
- Diagram dibuat ulang dengan Archify (arsitektur sekarang menampilkan app .NET dan JS). Dua file `manual-*.html` dan folder percobaan gagal lama dihapus. Catatan kegagalan diganti dengan petunjuk memakai Node 20 di `AGENTS.md`, karena bug Node 22 masih ada di komputer ini. `.gitignore` kini hanya mengabaikan receipt (`*.finalize.json`, dll) dan folder `.playwright-mcp/`, sedangkan `candidate.json` dan HTML di-commit.
- Temuan (22 Okt, sesi trace kosong): gejala "service terbaca tapi trace kosong" disebabkan Adaptive Sampling dari Datadog. Log tracer .NET menunjukkan `"sampling_rules": "[{\"sample_rate\":0.01}]"` padahal manifest mengatur `1`. Setelah Adaptive Sampling dimatikan di Ingestion Control, trace muncul dan pengguna mengonfirmasi (9.9). Perbaikan permanen sudah dilakukan lewat UI, bukan lewat manifest.
- Temuan (trace tidak muncul di Live Tail, dan dulu hanya `GET /api/dogs` yang terbaca): Adaptive Sampling di Datadog (Ingestion Control, "All resources dynamically adjusted") mengirim aturan sampling lewat Remote Configuration (`provenance: dynamic`). Log tracer .NET menunjukkan aturan berubah dari tanpa aturan (16:05), menjadi `GET /api/dogs`, `GET /api/dogs/{id}`, dan `*` masing-masing 1 (16:14), lalu `*` = 0,01 (16:25). Pada 300 request GET, Agent menerima 300 trace tetapi hanya menulis 3 ke Datadog. Jalur jaringan, API key, dan tracer JS sudah dipastikan normal.
- Perbaikan: `DD_TRACE_SAMPLING_RULES='[{"sample_rate":1}]'` ditambahkan ke `k8s/dogsworld-dotnet.yaml` dan `k8s/dogsworld-js.yaml`, lalu `kubectl apply` (rollout otomatis). Hasil uji: Agent menerima 22 trace .NET dan 20 trace JS, Writer menulis 62 trace (sebelumnya 3). Namun 3 detik setelah aturan lokal terpasang, log .NET (17:22:25) menunjukkan aturan dynamic menggantikannya (`GET /api/dogs/{id}` = 1 dan `*` = 1). Jadi aturan lokal TIDAK menang atas Adaptive Sampling. Saat ini rate-nya kebetulan 1, tetapi Datadog bisa menurunkannya lagi. Perbaikan permanen: matikan Adaptive Sampling untuk kedua service di Ingestion Control (belum dilakukan, menunggu pengguna), atau pertimbangkan `DD_REMOTE_CONFIGURATION_ENABLED=false`.
- Uji POST, PUT, DELETE: satu dog sementara dibuat, diubah, dihapus di tiap aplikasi (201, 204, 200). Data kembali ke 9 dog (id 1 sampai 9). ID identity 11 dan 12 terpakai dan tidak akan dipakai lagi.
- `README.md` ditambahkan di root: struktur repo, topologi, kontrak API, dan langkah menjalankan dari nol. Kalau struktur, port, atau langkah deploy berubah, perbarui README bersama `AGENTS.md`.
