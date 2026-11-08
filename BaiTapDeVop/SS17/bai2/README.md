# Bài tập 2: Cấu hình Logstash nhận log từ Spring Boot - Sửa lỗi Codec JSON Stream

## 1. Mục tiêu kiến thức
- Hiểu rõ cơ chế xử lý luồng gói tin (Stream Processing) qua giao thức TCP trong **Logstash**.
- Phân biệt sự khác nhau giữa các Codec: **`plain`**, **`json`**, và **`json_lines`**.
- Hiểu cách thức hoạt động của thư viện **`logstash-logback-encoder`** trong ứng dụng Spring Boot khi truyền tải dữ liệu có cấu trúc qua mạng.
- Nắm vững cú pháp file cấu hình pipeline của Logstash (`input`, `filter`, `output`) để bóc tách JSON thành các trường dữ liệu có cấu trúc (Structured Fields) trên Elasticsearch.

---

## 2. Tình huống nghiệp vụ & Bẫy kỹ thuật

### 2.1. Tình huống
Hệ thống Backend **StoreX** (viết bằng Java Spring Boot) sử dụng thư viện `logstash-logback-encoder` với appender `LogstashTcpSocketAppender` để đẩy log trực tiếp qua TCP Socket tới Logstash ở cổng `5000`.

File cấu hình ban đầu của Logstash (`logstash.conf`):
```ruby
# CẤU HÌNH BAN ĐẦU BỊ LỖI
input {
  tcp {
    port => 5000
    # LỖI: Không khai báo codec, Logstash ngầm sử dụng codec "plain" mặc định
  }
}
output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
  }
}
```

### 2.2. Bẫy kỹ thuật: Tại sao Logstash không parse được JSON?

#### A. Hành vi của Codec `plain` mặc định
Khi không khai báo `codec`, plugin `tcp` của Logstash sử dụng codec mặc định là **`plain`**:
- Toàn bộ chuỗi JSON từ Spring Boot gửi sang sẽ bị coi như một chuỗi văn bản thô (raw text).
- Logstash gói toàn bộ nội dung đó vào trường duy nhất là `message`.
- **Hậu quả trên Elasticsearch:** Không thể thực hiện truy vấn, lọc hay tổng hợp (aggregation) theo các trường nghiệp vụ như `userId`, `level`, `traceId`, `orderId`, `status_code`... vì tất cả đã bị nhốt trong một chuỗi string vô nghĩa.

```json
// Dữ liệu bị biến dạng thành string thô khi dùng codec "plain"
{
  "@timestamp": "2026-11-08T15:20:00.000Z",
  "message": "{\"app_name\":\"storex\",\"level\":\"INFO\",\"userId\":1001,\"message\":\"Payment success\"}",
  "host": "172.18.0.1",
  "port": 54321
}
```

#### B. Tại sao dùng `codec => json` vẫn có thể phát sinh lỗi?
Nếu lập trình viên chỉ đổi thành `codec => json`:
- Giao thức TCP là một **luồng byte liên tục (Stream-oriented)**, không có ranh giới gói tin (No message framing).
- `codec => json` mong đợi một đối tượng JSON độc lập kết thúc khi đóng kết nối hoặc một JSON block hoàn chỉnh. Khi nhiều bản ghi log được gửi dồn dập qua cùng một kết nối TCP keep-alive, Logstash không xác định được điểm bắt đầu và kết thúc của từng document JSON, dẫn đến lỗi:
  ```text
  [WARN ][logstash.codecs.json] JSON parse error, original data now in message field {:error=>#<LogStash::Json::ParserError: Unexpected end-of-input>}
  ```

#### C. Bản chất của Spring Boot `LogstashTcpSocketAppender`
Thư viện `logstash-logback-encoder` trong Spring Boot hoạt động theo chuẩn **NDJSON (Newline Delimited JSON)**:
- Mỗi khi phát sinh một sự kiện log, nó tuần tự hóa (serialize) log event thành một chuỗi JSON trên **1 dòng duy nhất** và kết thúc bằng ký tự ngắt dòng `\n` (EOL - End Of Line).
- Do đó, codec tương thích chuẩn xác 100% cho TCP stream nhận từ Logback bắt buộc phải là **`json_lines`**.
- `json_lines` sẽ tách luồng TCP theo từng ký tự `\n`, sau đó giải mã (decode) từng dòng thành một Document JSON hoàn chỉnh với các trường riêng biệt.

---

## 3. Giải pháp kỹ thuật chuẩn hóa

### 3.1. File cấu hình `logstash.conf` đã sửa
Khai báo rõ ràng `codec => json_lines` bên trong khối `tcp` input:

```ruby
input {
  tcp {
    port => 5000
    # SỬA LỖI: Nhận từng dòng JSON phân tách bằng ký tự xuống dòng (\n)
    codec => json_lines
  }
}

output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    index => "storex-logs-%{+YYYY.MM.dd}"
  }
  # Bổ sung stdout để theo dõi trực tiếp quá trình parse trên terminal
  stdout {
    codec => rubydebug
  }
}
```

### 3.2. Cấu trúc thư mục & File `docker-compose.yml`

```text
SS17/bai2/
├── docker-compose.yml
├── logstash/
│   └── pipeline/
│       └── logstash.conf
└── README.md
```

Nội dung file `docker-compose.yml`:
```yaml
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.0
    container_name: elasticsearch-b2
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ports:
      - "9200:9200"
    networks:
      - efk-net

  logstash:
    image: docker.elastic.co/logstash/logstash:7.17.0
    container_name: logstash-b2
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
    container_name: kibana-b2
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

### Bước 1: Khởi động hệ thống
```bash
docker-compose up -d
```

### Bước 2: Theo dõi log của Logstash
Mở một cửa sổ terminal để quan sát output:
```bash
docker-compose logs -f logstash
```
Đợi đến khi thấy thông báo:
```text
[INFO ][logstash.inputs.tcp     ] Starting tcp listener {:address=>"0.0.0.0:5000"}
[INFO ][logstash.agent          ] Pipelines running {:count=>1, :running_pipelines=>[:main]}
```

### Bước 3: Mô phỏng Spring Boot gửi Log JSON qua cổng TCP 5000

#### Cách A: Dùng PowerShell (Windows)
```powershell
$client = New-Object System.Net.Sockets.TcpClient('localhost', 5000)
$stream = $client.GetStream()
$writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)

# Log event 1
$writer.WriteLine('{"app_name":"storex-backend","level":"INFO","logger_name":"c.s.controller.OrderController","message":"Order #9876 created successfully","userId":1001,"totalAmount":150.5}')

# Log event 2
$writer.WriteLine('{"app_name":"storex-backend","level":"WARN","logger_name":"c.s.service.PaymentService","message":"Payment gateway response delayed 1200ms","userId":1001,"retryCount":1}')

$writer.Flush()
$client.Close()
```

#### Cách B: Dùng Bash / Netcat (Linux / Mac / Git Bash)
```bash
echo '{"app_name":"storex-backend","level":"INFO","logger_name":"c.s.controller.OrderController","message":"Order #9876 created successfully","userId":1001,"totalAmount":150.5}' | nc localhost 5000
```

### Bước 4: Kiểm tra kết quả parse trong Logstash (`rubydebug`)
Trên cửa sổ `docker-compose logs -f logstash`, sự kiện log hiển thị dạng cấu trúc phân rã từng trường:
```ruby
{
      "app_name" => "storex-backend",
         "level" => "INFO",
   "logger_name" => "c.s.controller.OrderController",
       "message" => "Order #9876 created successfully",
        "userId" => 1001,
   "totalAmount" => 150.5,
    "@timestamp" => 2026-11-08T15:25:00.123Z,
      "@version" => "1",
          "host" => "172.18.0.1",
          "port" => 51234
}
```

### Bước 5: Truy vấn kiểm tra trên Elasticsearch
Gọi HTTP REST API tới Elasticsearch:
```bash
curl -X GET "http://localhost:9200/storex-logs-*/_search?pretty"
```

**Kết quả trả về:**
```json
{
  "took" : 2,
  "timed_out" : false,
  "_shards" : { "total" : 1, "successful" : 1, "skipped" : 0, "failed" : 0 },
  "hits" : {
    "total" : { "value" : 1, "relation" : "eq" },
    "hits" : [
      {
        "_index" : "storex-logs-2026.11.08",
        "_type" : "_doc",
        "_id" : "abc123xyz",
        "_score" : 1.0,
        "_source" : {
          "app_name" : "storex-backend",
          "level" : "INFO",
          "logger_name" : "c.s.controller.OrderController",
          "message" : "Order #9876 created successfully",
          "userId" : 1001,
          "totalAmount" : 150.5,
          "@timestamp" : "2026-11-08T15:25:00.123Z",
          "@version" : "1"
        }
      }
    ]
  }
}
```

---

## 5. Kết luận rút ra
- Dùng `codec => json_lines` là cấu hình chuẩn bắt buộc cho mọi luồng nhận log qua TCP socket từ thư viện Spring Boot `logstash-logback-encoder`.
- Dữ liệu được bóc tách hoàn toàn thành các trường số (`userId: 1001`), float (`totalAmount: 150.5`), string (`level: INFO`), cho phép Kibana xây dựng biểu đồ thống kê, lọc lỗi và cảnh báo tức thời.
