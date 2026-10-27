# SS13 - Prometheus & Monitoring

Bài tập thực hành về giám sát hệ thống với **Prometheus**, **Spring Boot Actuator**, và **Node Exporter**.

---

## Cấu trúc thư mục

```
SS13/
├── bai1/
│   ├── prometheus.yml    ← Cấu hình đã sửa (fix lỗi localhost & metrics_path)
│   └── README.md         ← Phân tích nguyên nhân và giải pháp
├── bai2/
│   ├── build.gradle      ← Dependencies: actuator + micrometer-registry-prometheus
│   ├── application.yml   ← Expose prometheus endpoint, khóa endpoint nguy hiểm
│   └── README.md         ← Giải thích bẫy dependency bị thiếu
├── bai3/
│   ├── docker-compose.yml ← Node Exporter với volume /proc, /sys, /
│   ├── prometheus.yml    ← Job scrape node-exporter
│   └── README.md         ← Giải thích volume đặc biệt và bảo mật port 9100
└── bai4/
    ├── docker-compose.yml ← Liên minh ecommerce-api + prometheus
    ├── prometheus.yml    ← Scrape bằng service name Docker
    └── README.md         ← Giải thích Docker network, Bind Mount, reload config
```

---

## Tóm tắt kiến thức

| Bài | Chủ đề | Điểm mấu chốt |
|-----|--------|---------------|
| Bài 1 | Fix lỗi Scrape Metrics | `localhost` trong container ≠ máy Host → dùng `host.docker.internal`; Spring Boot dùng `/actuator/prometheus` thay vì `/metrics` |
| Bài 2 | Spring Boot Actuator | Cần **cả 2** dependency: `actuator` + `micrometer-registry-prometheus`; chỉ expose endpoint an toàn |
| Bài 3 | Node Exporter | Mount `/proc`, `/sys`, `/` từ Host; port 9100 không nên public ra Internet |
| Bài 4 | Docker Compose Stack | Dùng service name trong Docker network; Bind Mount cho config; reload bằng `POST /-/reload` |
