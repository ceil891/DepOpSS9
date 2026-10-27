# Bài 2: Bật Radar cho Spring Boot (Actuator)

## Dependency bị thiếu - Giải thích Bẫy

| Dependency | Tác dụng | Nếu thiếu |
|-----------|----------|-----------|
| `spring-boot-starter-actuator` | Tạo ra các management endpoints | Không có `/actuator/*` |
| `micrometer-registry-prometheus` | **Chuyển đổi metrics sang định dạng text Prometheus** | `/actuator/prometheus` không tồn tại hoặc trả về JSON |

> **Bẫy:** Chỉ thêm `spring-boot-starter-actuator` mà **quên** `micrometer-registry-prometheus` →
> Endpoint `/actuator/prometheus` sẽ **không được tạo ra** hoặc trả về `404`.
> Prometheus yêu cầu định dạng `text/plain` theo chuẩn OpenMetrics, không phải JSON.

---

## build.gradle

```gradle
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-web'

    // Dependency 1: Actuator
    implementation 'org.springframework.boot:spring-boot-starter-actuator'

    // Dependency 2 (hay bị quên): Micrometer Prometheus Registry
    implementation 'io.micrometer:micrometer-registry-prometheus'
}
```

---

## application.yml

```yaml
management:
  endpoints:
    web:
      exposure:
        # Chỉ mở endpoint cần thiết - KHÔNG mở "shutdown", "env", "heapdump"
        include: "prometheus,health,info"
  endpoint:
    health:
      show-details: when-authorized
    prometheus:
      enabled: true
  metrics:
    tags:
      application: ${spring.application.name}
```

---

## Kiểm tra kết quả

Sau khi chạy Spring Boot, truy cập:
```
GET http://localhost:8080/actuator/prometheus
```

**Response đúng** (định dạng text Prometheus):
```
# HELP jvm_memory_used_bytes The amount of used memory
# TYPE jvm_memory_used_bytes gauge
jvm_memory_used_bytes{area="heap",id="G1 Eden Space",} 2.097152E7
...
```

**Response sai** (thiếu micrometer-registry-prometheus):
```json
{"timestamp":"...","status":404,"error":"Not Found"}
```
