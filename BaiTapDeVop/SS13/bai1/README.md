# Bài 1: Khắc phục lỗi Scrape Metrics

## Phân tích vấn đề

### Legacy Code (Lỗi)
```yaml
scrape_configs:
  - job_name: 'backend'
    static_configs:
      - targets: ['localhost:8080']
```

### Nguyên nhân lỗi

**Câu hỏi: Khi Prometheus chạy trong Docker Container, `localhost` trỏ đi đâu?**

> Khi Prometheus chạy trong Docker Container, `localhost` (hay `127.0.0.1`) chỉ trỏ đến **CHÍNH container Prometheus** đó, không phải máy Host bên ngoài.
>
> Vì Backend đang chạy trực tiếp trên máy Host ở port 8080, nên Prometheus trong container sẽ **không thể kết nối được**, dẫn đến lỗi `connection refused`.

### Hai lỗi trong cấu hình gốc:

| # | Vấn đề | Sai | Đúng |
|---|--------|-----|------|
| 1 | **Địa chỉ host** | `localhost` (trỏ vào container) | `host.docker.internal` (Windows/macOS) hoặc IP VPS thật |
| 2 | **Metrics path** | `/metrics` (mặc định Prometheus) | `/actuator/prometheus` (Spring Boot Actuator) |

---

## Giải thích Bẫy: `metrics_path`

**Endpoint mặc định** mà Prometheus gọi vào là `/metrics`.

**Đối với Spring Boot Actuator**, endpoint metrics được phơi bày tại:
```
/actuator/prometheus
```

→ **Phải thêm chỉ thị `metrics_path: '/actuator/prometheus'`** vào cấu hình.

Nếu không thêm, Prometheus sẽ gọi vào `host.docker.internal:8080/metrics` và nhận lỗi `404 Not Found`.

---

## Cấu hình đã sửa

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'backend'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['host.docker.internal:8080']
        # Hoặc dùng IP VPS thật nếu deploy trên Linux:
        # - targets: ['192.168.1.100:8080']
```

---

## Tóm tắt các thay đổi

1. **`localhost:8080`** → **`host.docker.internal:8080`**
   - `host.docker.internal` là hostname đặc biệt mà Docker cung cấp để container truy cập máy Host
   - Trên Linux VPS: thay bằng IP thật của máy chủ (ví dụ `192.168.1.100:8080`)

2. **Thêm `metrics_path: '/actuator/prometheus'`**
   - Spring Boot Actuator expose metrics tại `/actuator/prometheus`
   - Cần thêm `micrometer-registry-prometheus` dependency trong `build.gradle`

---

## Sơ đồ luồng kết nối

```
[Docker Container: Prometheus :9090]
        |
        | host.docker.internal:8080/actuator/prometheus
        |
        ↓
[Host Machine: Spring Boot App :8080]
```
