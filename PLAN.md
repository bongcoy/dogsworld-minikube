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
- [x] 6.8 Cek trace di Agent (`agent status`) dan di Datadog UI (APM, Services: `dogsworld-js`). Agent sudah menerima trace (terbukti), UI belum dicek pengguna
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

## 8. Perubahan yang dilakukan di komputer

- Memasang Helm dan minikube (winget).
- Mungkin membuat atau mengubah `%USERPROFILE%\.wslconfig`.
- Mengubah `Dockerfile`, `appsettings.json`, dan mungkin `DogsWorld.csproj`.
- Membuat folder `k8s/` berisi manifest.
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
- Diagram arsitektur dan sequence dibuat manual di `.archify/manual-*.html` karena Archify gagal di Windows ini (`lstat` mengembalikan `dev=0`, `fstat` tidak).
- Pengecekan: hanya pod `dogsworld` yang disuntik SSI. Pod `sqlserver` dan `db-init` di namespace yang sama tidak.
- Fase 6 sampai 8 ditambahkan: aplikasi JS (namespace `dogsworld`) dan Java (namespace `dogsworld-java-test`).
- Fase 6 selesai kecuali cek UI. CRUD JS lolos semua (201/204/200/400/404). Agent menerima trace dari nodejs v20.20.2, tracer 5.132.0, via uds (3 trace, 28 span per menit).
- Temuan: pod JS yang dibuat saat Cluster Agent sedang diganti hanya mendapat tracer .NET. Perlu `kubectl rollout restart` supaya `datadog-lib-js-init` muncul.
- Temuan: karena target `dogsworld` kini memuat `dotnet` dan `js`, pod JS mendapat dua init container tracer (`datadog-lib-js-init` dan `datadog-lib-dotnet-init`). Tracer yang tidak cocok tidak dipakai.
- Temuan: pod `sqlserver` dan `db-init` tetap tidak disuntik meski namespace-nya sama.
- Swagger ditambahkan ke app JS (item 6.9). `/swagger/index.html` dan `/swagger/` keduanya 200, API tetap normal, pod baru tetap disuntik SSI (`datadog-lib-js-init`). Image dinaikkan ke tag `1.1` supaya `minikube image load` pasti memuat versi baru.
- Plan Swagger untuk app Java ditambahkan sebagai item 7.10.
