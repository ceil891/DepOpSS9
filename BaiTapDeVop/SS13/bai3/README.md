# Bài 3: Khám sức khỏe máy chủ với Node Exporter

## Node Exporter là gì?

Node Exporter là một công cụ của Prometheus dùng để thu thập metrics **hệ điều hành Linux**:
- CPU usage (user, system, iowait)
- RAM / Memory (available, used, cached)
- Disk I/O và Disk Space
- Network traffic (bytes in/out per interface)
- Load average, open file descriptors, v.v.

---

## Giải thích: Volumes đặc biệt cần mount

| Volume | Mount Point | Mục đích |
|--------|-------------|----------|
| `/proc` | `/host/proc:ro` | Thông tin processes, CPU, memory, network của **Host OS** |
| `/sys` | `/host/sys:ro` | Thông tin hardware, kernel, network interfaces của **Host** |
| `/` | `/rootfs:ro` | Filesystem gốc để tính **disk usage thật** của Host |

> **Tại sao cần mount?**
> Nếu không mount, Node Exporter chỉ đọc `/proc` và `/sys` **bên trong container** - đây là namespace riêng của container, bị ảo hóa và không phản ánh tài nguyên thật của máy chủ VPS.

---

## Giải thích Bẫy: Port và Bảo mật

**Node Exporter mặc định chạy ở port `9100`**

**Rủi ro khi public port 9100 ra Internet:**
- Bất kỳ ai trên Internet đều có thể xem thông tin hệ thống: hostname, filesystem paths, CPU/memory usage
- Thông tin này giúp attacker **reconnaissance** (trinh thám) trước khi tấn công
- Node Exporter **không có tính năng xác thực** (authentication) mặc định

**Giải pháp bảo mật:**
```yaml
ports:
  - "127.0.0.1:9100:9100"   # ✅ Chỉ bind localhost
  # Thay vì:
  # - "9100:9100"            # ❌ Bind 0.0.0.0 - public ra Internet
```

---

## docker-compose.yml

```yaml
version: '3.8'

services:
  node-exporter:
    image: prom/node-exporter:latest
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - "127.0.0.1:9100:9100"   # Chỉ nội bộ
    networks:
      - monitoring

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    networks:
      - monitoring

networks:
  monitoring:
    driver: bridge
```

---

## prometheus.yml - Block job_name 'node'

```yaml
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          instance: 'vps-production'
          env: 'production'
```

> Node Exporter dùng endpoint `/metrics` mặc định → **không cần thêm `metrics_path`**

---

## Kiểm tra hoạt động

```bash
# Chạy stack
docker-compose up -d

# Kiểm tra Node Exporter (từ trong cùng Docker network)
curl http://localhost:9100/metrics | head -20

# Vào Prometheus UI và kiểm tra query
# http://localhost:9090
# Query: node_memory_MemAvailable_bytes
# Query: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)
```
