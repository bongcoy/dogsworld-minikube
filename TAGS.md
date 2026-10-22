# TAGS.md

Konvensi tag untuk semua entity Datadog di repo ini (Deployment, Job, Pod, `DatadogAgent`, monitor, dashboard, SLO, metrik kustom, dan sejenisnya). Setiap entity baru atau yang diubah wajib mengikuti dokumen ini. Dokumen ini mengacu pada [Getting Started with Tags](https://docs.datadoghq.com/getting_started/tagging/).

## 1. Format tag

- Pakai format `key:value`. Dokumentasi Datadog merekomendasikan format ini karena lebih jelas dan memudahkan filter maupun grouping.
- `key` adalah identifier, misalnya `env`, `service`, `team`. `value` adalah datanya, misalnya `dev`, `dogsworld-js`, `bongcoy`.
- Nilai yang sama boleh dipakai di banyak resource. Tag memang dimaksudkan untuk agregasi.

## 2. Aturan penulisan

Dari dokumentasi Datadog:

- Tag harus **diawali huruf**.
- Karakter yang boleh: huruf (termasuk Unicode), angka, `_`, `-`, `:`, `.`, `/`. Di log yang dikirim lewat HTTP, `@` juga boleh.
- Karakter lain (spasi, koma, emoji, backslash) diubah menjadi `_`.
- Maksimal **200 karakter**, termasuk key, `:`, dan value.
- Pakai **huruf kecil**. Hindari camelCase, karena span dan metrik dinormalisasi ke huruf kecil dan cloud provider menanganinya tidak konsisten.
- Di `DD_TAGS`, pemisahnya spasi, dan spasi di nilai **tidak** diubah menjadi `_`. Untuk nilai yang mengandung spasi, pakai file YAML.
- Jangan pakai sumber tak terbatas sebagai nilai, misalnya epoch timestamp, user ID, atau request ID. Nilai seperti itu membuat jumlah metrik terus bertambah (kardinalitas tinggi).

Contoh: `env:staging:east` berarti key `env` dan value `staging:east`. Key selalu berakhir di titik dua pertama.

## 3. Reserved tag keys

Datadog menyediakan key khusus yang menghubungkan metrik, trace, dan log.

| Key | Fungsi |
|---|---|
| `host` | Menghubungkan metrik, trace, proses, dan log. |
| `device` | Memisahkan data per perangkat atau disk. |
| `source` | Filter span dan pipeline otomatis di Log Management. |
| `service` | Mengelompokkan data aplikasi di metrik, trace, dan log. |
| `env` | Mengelompokkan data aplikasi di metrik, trace, dan log. |
| `version` | Mengelompokkan data aplikasi di metrik, trace, dan log. |
| `team` | Menentukan kepemilikan resource. |

## 4. Tag wajib untuk aplikasi

Setiap workload aplikasi memakai **Unified Service Tagging**: tiga tag `env`, `service`, `version`, ditambah `team`.

| Tag | Nilai | Aturan |
|---|---|---|
| `env` | `dev` | Sama untuk semua aplikasi di cluster ini. |
| `service` | `dogsworld-<bahasa>` | Sama dengan nama aplikasi (lihat AGENTS.md, bagian Konvensi). |
| `version` | Tag image, misalnya `1.2` | Harus sama dengan tag di `image`. Naikkan setiap build ulang. |
| `team` | `bongcoy` | Pemilik resource. |

Tiga tag UST (`env`, `service`, `version`) ditulis sebagai label `tags.datadoghq.com/*` di **metadata Deployment** dan di **pod template**. Admission Controller Datadog membaca label pod untuk mengisi `DD_ENV`, `DD_SERVICE`, dan `DD_VERSION` saat pod dibuat.

Tag `team` **tidak** ditulis sebagai label pod. Label Kubernetes biasa tidak otomatis menjadi tag Datadog. `team` ditulis di `global.tags` pada `DatadogAgent` (lihat bagian 6), sehingga berlaku untuk seluruh data dari Agent.

Contoh:

```yaml
metadata:
  labels:
    tags.datadoghq.com/env: dev
    tags.datadoghq.com/service: dogsworld-js
    tags.datadoghq.com/version: "1.2"
spec:
  template:
    metadata:
      labels:
        tags.datadoghq.com/env: dev
        tags.datadoghq.com/service: dogsworld-js
        tags.datadoghq.com/version: "1.2"
```

Catatan: `version` berupa string, jadi beri tanda kutip (`"1.2"`) supaya YAML tidak membacanya sebagai angka.

## 5. Infrastruktur non-aplikasi

Database dan komponen infrastruktur lain (misalnya `postgres`) tidak disuntik tracer, tetapi tetap perlu tag supaya bisa difilter dan dimiliki.

| Tag | Nilai |
|---|---|
| `env` | `dev` |
| `service` | Nama komponen, misalnya `postgres` |
| `team` | `bongcoy` |

Tag `env` dan `service` ditulis sebagai label `tags.datadoghq.com/*` seperti aplikasi. Tag `team` ditulis di `global.tags` pada `DatadogAgent` (bagian 6).

## 6. Tag level cluster (`DatadogAgent`)

Tag cluster ditulis di `k8s/datadog-agent.yaml`:

- `spec.global.clusterName`: nama cluster, saat ini `dogsworld-minikube`.
- `spec.global.tags`: daftar tag yang ditambahkan ke semua data dari Agent, misalnya `"env:dev"`, `"team:bongcoy"`. Di sinilah `team` ditulis.

Perhatian: Agent mengumpulkan **semua** nilai untuk satu key dari setiap sumber, tanpa urutan prioritas. Jika `service` diisi di tempat lain dengan nilai berbeda, data akan memuat dua nilai. Jadi jangan mengisi `env` atau `service` dengan nilai berbeda di sumber lain.

## 7. Entity lain

| Entity | Tag wajib |
|---|---|
| Monitor, dashboard, SLO, notebook | `env`, `service` (jika terkait aplikasi tertentu), `team` |
| Metrik kustom / DogStatsD | Mengikuti bagian 2. Untuk aplikasi, pakai `env`, `service`, `version` dari UST. |
| Job atau CronJob sekali jalan | `env`, `service`, `team` |

## 8. Daftar periksa sebelum entity baru dibuat

- [ ] Ada `env`, `service`, `version` (untuk aplikasi), dan `team` (`team` di `global.tags` DatadogAgent).
- [ ] Nilai `service` sama dengan nama aplikasi dan nama folder `apps/`.
- [ ] Label `tags.datadoghq.com/*` ada di Deployment **dan** pod template.
- [ ] `version` sama dengan tag image dan sudah dinaikkan.
- [ ] Tidak ada spasi, huruf besar, atau sumber tak terbatas di nilai tag.
- [ ] Tidak ada tag yang sama dengan nilai berbeda di sumber lain.
