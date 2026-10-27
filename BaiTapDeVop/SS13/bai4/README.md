# Bài 4: Liên minh Docker Compose (Prometheus + App)

## Kiến trúc tổng quan

```
[Máy Host]
    │
    ├── prometheus.yml (file cấu hình - Bind Mount)
    │
    └── Docker Compose
            │
            ├── Docker Network: monitoring-net
            │       │
            │       ├── [ecommerce-api:8080]  ← Spring Boot App
            │       │        (KHÔNG public port ra ngoài)
            │       │
            │       └── [prometheus:9090]     ← Prometheus
            │                (Public port 9090 cho Dev xem dashboard)
            │
            └── Volume: prometheus_data (lưu TSDB data)
```

---

## Giải thích: Docker Network & Service Name

Khi các service nằm trong **cùng Docker network**, Docker tự động cung cấp DNS resolution.

Thay vì dùng `localhost` hay IP cứng, ta dùng **service name** làm hostname:

```yaml
# prometheus.yml
static_configs:
  - targets: ['ecommerce-api:8080']   # ✅ Docker DNS resolve "ecommerce-api" → IP container
```

> Đây là lý do Bài 1 bị lỗi: khi dùng `localhost` trong container, nó trỏ về chính container đó, không phải service khác hay máy Host.

---

## docker-compose.yml

```yaml
version: '3.8'

services:
  ecommerce-api:
    image: your-dockerhub-username/ecommerce-api:latest
    # Không cần expose port ra ngoài - Prometheus scrape qua internal network
    networks:
      - monitoring-net

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"           # Chỉ Prometheus cần public port
    volumes:
      # ✅ Bind Mount: ánh xạ file config từ Host vào container
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--web.enable-lifecycle'    # Bật API reload
    networks:
      - monitoring-net

networks:
  monitoring-net:
    driver: bridge

volumes:
  prometheus_data:
```

---

## Giải thích Bẫy: Reload cấu hình Prometheus

**Câu hỏi: Nếu sửa `prometheus.yml` trên Host, Prometheus có tự động nhận cấu hình mới không?**

> **KHÔNG.** Prometheus **không tự động** watch file config. Phải kích hoạt reload thủ công.

### Hai cách reload cấu hình:

#### Cách 1: Gọi HTTP API (Không cần downtime - Khuyến nghị)
```bash
# Gửi POST request tới Prometheus reload endpoint
curl -X POST http://localhost:9090/-/reload
```
> Yêu cầu flag `--web.enable-lifecycle` phải được bật trong `command`

#### Cách 2: Restart container (Có downtime ngắn)
```bash
docker-compose restart prometheus
# Hoặc
docker compose restart prometheus
```

---

## Lệnh vận hành đầy đủ

```bash
# Khởi động toàn bộ stack
docker-compose up -d

# Xem logs
docker-compose logs -f prometheus
docker-compose logs -f ecommerce-api

# Sửa prometheus.yml rồi reload (không cần restart)
curl -X POST http://localhost:9090/-/reload

# Dừng toàn bộ stack
docker-compose down

# Dừng và xóa cả data volume
docker-compose down -v
```

---

## Kiểm tra kết quả

1. Mở `http://localhost:9090/targets` → kiểm tra `ecommerce-api` ở trạng thái **UP**
2. Mở `http://localhost:9090/graph` → thử query `jvm_memory_used_bytes`
3. Kiểm tra Bind Mount hoạt động:
   ```bash
   docker exec prometheus cat /etc/prometheus/prometheus.yml
   ```
