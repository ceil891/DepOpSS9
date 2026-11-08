# Bài tập 3: Phân loại Log theo Index trên Elasticsearch - Dynamic Index Routing

## 1. Mục tiêu kiến thức
- Hiểu rõ cơ chế **Event Field Reference** (`%{[field_name]}`) trong Logstash để định tuyến dữ liệu động (Dynamic Routing).
- Nắm vững các quy tắc đặt tên Index của **Elasticsearch (Index Naming Conventions)** và cách phòng tránh lỗi xung đột `InvalidIndexNameException`.
- Hiểu lợi ích kiến trúc của việc phân tách Index theo Microservice: phân quyền bảo mật (RBAC), quản lý vòng đời dữ liệu (Index Lifecycle Management - ILM), và tránh xung đột sơ đồ dữ liệu (Mapping Collision).

---

## 2. Tình huống nghiệp vụ & Bẫy kỹ thuật

### 2.1. Tình huống
Hệ thống **StoreX** có nhiều dịch vụ microservice chạy độc lập, tiêu biểu là `user-service` và `order-service`. Tuy nhiên, file cấu hình Logstash hiện tại đang gom tất cả log của mọi dịch vụ vào chung một index cố định:

```ruby
# CẤU HÌNH BAN ĐẦU BỊ LỖI
output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    # LỖI: Tất cả dịch vụ bị tống chung vào một index tĩnh
    index => "logstash-%{+YYYY.MM.dd}"
  }
}
```

### 2.2. Hậu quả khi gộp chung Index trong môi trường Microservices
1. **Xung đột kiểu dữ liệu (Field Mapping Conflict / Collision):**
   - Giả sử `user-service` gửi trường `payload: "active"` (kiểu dữ liệu `text` hoặc `keyword`).
   - Sau đó `order-service` gửi trường `payload: {"order_id": 123, "price": 99.0}` (kiểu dữ liệu `object`).
   - Elasticsearch đã khóa kiểu dữ liệu của `payload` ở lần đầu tiên. Khi log thứ hai tới, Elasticsearch sẽ từ chối ghi và báo lỗi `mapper_parsing_exception` $\rightarrow$ **Mất log nghiệp vụ quan trọng**.
2. **Không thể phân quyền bảo mật (RBAC):**
   - Đội ngũ bảo mật muốn cấp quyền cho nhân viên Chăm sóc khách hàng chỉ được xem log của `user-service`, nhưng vì dùng chung 1 index nên nhân viên đó có thể xem toàn bộ doanh thu, thanh toán trong log của `order-service`.
3. **Không thể tối ưu vòng đời dữ liệu (ILM - Index Lifecycle Management):**
   - Log giao dịch tài chính của `order-service` cần lưu trữ 365 ngày theo luật kế toán.
   - Log truy vết của `user-service` chỉ cần lưu 14 ngày để tiết kiệm dung lượng ổ đĩa.
   - Khi gộp chung index, toàn bộ log buộc phải cùng áp dụng chung một thời hạn lưu trữ.
4. **Hiệu năng truy vấn suy giảm:**
   - Khi dev muốn tìm lỗi của `order-service`, Elasticsearch phải quét qua hàng triệu bản ghi của toàn bộ các service khác.

### 2.3. Hai bẫy kỹ thuật khi cấu hình Dynamic Index trong Logstash

#### Bẫy 1: Quy tắc đặt tên Index của Elasticsearch (Chữ thường - Lowercase)
Elasticsearch quy định nghiêm ngặt: **Tên Index bắt buộc phải viết thường toàn bộ (lowercase)**.
- Nếu ứng dụng gửi `app_name: "Order-Service"` hoặc `app_name: "user_Service"`, Elasticsearch sẽ từ chối document và ném lỗi:
  ```text
  [WARN ][logstash.outputs.elasticsearch] Could not index event to Elasticsearch.
  status: 400, error: {"type":"invalid_index_name_exception","reason":"Invalid index name [Order-Service-2026.11.08], must be lowercase"}
  ```
- **Giải pháp:** Phải có bước chuẩn hóa `mutate { lowercase => [ "app_name" ] }` trước khi xuất ra Elasticsearch.

#### Bẫy 2: Log thiếu trường `app_name` (Missing Field / Null Value)
- Nếu có một ứng dụng legacy hoặc script kiểm thử gửi log không chứa trường `app_name`, Logstash sẽ không thể thay thế biến và tạo ra index mang tên theo chuỗi ký tự nguyên bản: `%{[app_name]}-2026.11.08`.
- **Giải pháp:** Cần có cơ chế kiểm tra điều kiện `if ![app_name]` để gán giá trị mặc định (Fallback).

---

## 3. Giải pháp kỹ thuật chuẩn hóa

### 3.1. File cấu hình `logstash.conf` hoàn chỉnh

```ruby
input {
  tcp {
    port => 5000
    codec => json_lines
  }
}

filter {
  # PHÒNG CHỐNG BẪY 2: Fallback nếu log gửi lên thiếu trường app_name
  if ![app_name] or [app_name] == "" {
    mutate {
      add_field => { "app_name" => "storex-default" }
    }
  }

  # PHÒNG CHỐNG BẪY 1: Chuyển tên app_name thành chữ thường (lowercase)
  # Đảm bảo tuân thủ nghiêm ngặt chuẩn đặt tên Index của Elasticsearch
  mutate {
    lowercase => [ "app_name" ]
  }
}

output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    # ĐÃ SỬA: Biến động theo app_name và ngày tháng năm
    index => "%{[app_name]}-%{+YYYY.MM.dd}"
  }
  stdout {
    codec => rubydebug
  }
}
```

### 3.2. File `docker-compose.yml`

```yaml
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.0
    container_name: elasticsearch-b3
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ports:
      - "9200:9200"
    networks:
      - efk-net

  logstash:
    image: docker.elastic.co/logstash/logstash:7.17.0
    container_name: logstash-b3
    volumes:
      - ./logstash/pipeline/logstash.conf:/usr/share/logstash/pipeline/logstash.conf:ro
    ports:
      - "5000:5000"
    environment:
      - "LS_JAVA_OPTS=-Xms256m -Xmx512m"
    depends_on:
      - elasticsearch
    networks:
      - efk-net

  kibana:
    image: docker.elastic.co/kibana/kibana:7.17.0
    container_name: kibana-b3
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch
    networks:
      - efk-net

networks:
  efk-net:
    driver: bridge
```

---

## 4. Hướng dẫn kiểm thử & Xác thực kết quả

### Bước 1: Khởi động cụm dịch vụ
```bash
docker-compose up -d
```

### Bước 2: Bắn log thử nghiệm từ các Microservices khác nhau

Sử dụng PowerShell để gửi đồng thời log của `user-service`, `order-service` và một trường hợp có chữ hoa `Order-Service`:

```powershell
$client = New-Object System.Net.Sockets.TcpClient('localhost', 5000)
$stream = $client.GetStream()
$writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)

# Log từ user-service
$writer.WriteLine('{"app_name":"user-service","level":"INFO","message":"User ID 2005 profile updated","userId":2005}')

# Log từ order-service (chứa chữ hoa để kiểm tra filter lowercase)
$writer.WriteLine('{"app_name":"Order-Service","level":"INFO","message":"Order #8888 placed successfully","orderId":8888,"amount":250.0}')

# Log từ dịch vụ lạ không kèm app_name (kiểm tra fallback)
$writer.WriteLine('{"level":"WARN","message":"Heartbeat timeout from gateway"}')

$writer.Flush()
$client.Close()
```

### Bước 3: Kiểm tra danh sách Index trên Elasticsearch bằng `_cat/indices`

Gửi truy vấn HTTP REST:
```bash
curl -X GET "http://localhost:9200/_cat/indices?v&s=index"
```

**Kết quả hiển thị trên terminal:**
```text
health status index                       uuid                   pri rep docs.count docs.deleted store.size pri.store.size
yellow open   order-service-2026.11.08    aBcDeFg1234567890       1   1          1            0      4.5kb          4.5kb
yellow open   storex-default-2026.11.08   kLmNoPq1234567890       1   1          1            0      4.2kb          4.2kb
yellow open   user-service-2026.11.08     xYzAbCd1234567890       1   1          1            0      4.4kb          4.4kb
```

### Bước 4: Kiểm tra dữ liệu bên trong từng Index
- **Index `user-service-2026.11.08`**:
  ```bash
  curl -X GET "http://localhost:9200/user-service-*/_search?pretty"
  ```
  Chỉ chứa các log có `app_name: user-service`.

- **Index `order-service-2026.11.08`**:
  ```bash
  curl -X GET "http://localhost:9200/order-service-*/_search?pretty"
  ```
  Chỉ chứa các log của `order-service`, trường `amount` được index dạng số độc lập.

---

## 5. Kết luận rút ra
- Cú pháp dynamic index `%{[app_name]}-%{+YYYY.MM.dd}` giúp hệ thống tự động co giãn và phân loại log linh hoạt cho hàng trăm microservice mà không cần viết lại cấu hình Logstash.
- Luôn luôn kết hợp bộ lọc `lowercase` để triệt tiêu nguy cơ crash do lỗi đặt tên index của Elasticsearch.
- Tách index là điều kiện tiên quyết để xây dựng hệ thống phân quyền dữ liệu và dọn dẹp log tự động theo chu kỳ (ILM Policy).
