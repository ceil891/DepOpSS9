# Bài tập 1: Khởi tạo môi trường EFK Stack với Docker Compose - Sửa lỗi kết nối Kibana và Elasticsearch

## 1. Mục tiêu kiến thức
- Hiểu rõ kiến trúc phân tầng cổng kết nối trong **Elasticsearch**: phân biệt giữa **Cổng giao tiếp HTTP REST API (9200)** và **Cổng truyền tải nhị phân nội bộ Transport Protocol (9300)**.
- Phân tích cơ chế kết nối client giữa **Kibana** và **Elasticsearch** thông qua biến môi trường `ELASTICSEARCH_HOSTS`.
- Nắm vững cách thiết lập cụm dịch vụ tối thiểu của **EFK/ELK Stack** (Elasticsearch, Kibana) bằng **Docker Compose** với cấu hình tài nguyên (JVM Heap Options) và cơ chế phụ thuộc sức khỏe dịch vụ (Service Healthcheck).
- Khắc phục triệt để lỗi kinh điển `Elasticsearch is unreachable` và trạng thái `Kibana server is not ready yet`.

---

## 2. Tình huống nghiệp vụ & Phân tích nguyên nhân lỗi

### 2.1. Tình huống
Một lập trình viên trong nhóm triển khai cụm EFK Stack để gom log ứng dụng. File `docker-compose.yml` ban đầu được viết như sau:

```yaml
# CẤU HÌNH BAN ĐẦU BỊ LỖI
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.0
    environment:
      - discovery.type=single-node
  kibana:
    image: docker.elastic.co/kibana/kibana:7.17.0
    environment:
      # LỖI: Kibana giao tiếp qua HTTP nhưng lại trỏ vào cổng 9300 (Transport Port)
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9300
```

Khi chạy lệnh `docker-compose up -d`, container Kibana liên tục khởi động thất bại hoặc log ra lỗi kết nối, người dùng mở trình duyệt vào `http://localhost:5601` thì chỉ nhận được thông báo lỗi:
> **"Kibana server is not ready yet"** (HTTP Status 503 Service Unavailable).

### 2.2. Bẫy kỹ thuật: So sánh Port 9200 vs Port 9300 trong Elasticsearch

Elasticsearch mở mặc định 2 cổng mạng với hai mục đích kiến trúc hoàn toàn khác nhau:

| Tiêu chí | Cổng 9200 (HTTP REST API) | Cổng 9300 (Transport Protocol) |
|---|---|---|
| **Giao thức** | **HTTP / HTTPS (JSON)** chuẩn RESTful | **TCP Socket Nhị phân (Binary Transport)** độc quyền của Elasticsearch |
| **Đối tượng sử dụng** | **Dành cho External Clients:**<br>- **Kibana** (giao diện UI, truy vấn status, index pattern)<br>- **Logstash / Fluentd / Beats** (đẩy log)<br>- **Ứng dụng Web / Microservices** (Spring Boot, Node.js, Python qua REST Client)<br>- **DevOps / Sysadmin** (cURL, Postman) | **Dành riêng cho Internal Cluster Communication:**<br>- Giao tiếp giữa các Node trong cùng một cụm Elasticsearch<br>- Node Discovery (Zen Discovery)<br>- Đồng bộ trạng thái cụm (Cluster State Replication)<br>- Data Re-routing / Shard Allocation giữa các Node |
| **Định dạng dữ liệu** | Bản tin HTTP Request / Response (Headers, JSON Body) | Luồng nhị phân tuần tự hóa của Java (Java Object Serialization) |
| **Tương thích với Kibana** | **Tương thích 100%** (Kibana là một ứng dụng Node.js gọi HTTP API) | **Hoàn toàn KHÔNG tương thích** (Kibana gửi HTTP packet sẽ bị Elasticsearch từ chối ngay lập tức) |

### 2.3. Log lỗi thực tế trên Kibana
Khi Kibana cố gắng gửi bản tin HTTP GET tới cổng 9300 (`http://elasticsearch:9300`):

```text
[2026-11-08T15:00:10.123+00:00][ERROR][elasticsearch-service] Unable to retrieve version information from Elasticsearch nodes: Connection error: connect ECONNREFUSED / invalid HTTP response
[2026-11-08T15:00:12.456+00:00][WARN ][elasticsearch-service] Elasticsearch is unreachable: http://elasticsearch:9300
[2026-11-08T15:00:15.789+00:00][INFO ][status] [server] Kibana status change from yellow to red - Elasticsearch is unreachable
```

Ở phía Elasticsearch, tiến trình Transport Service trên cổng 9300 nhận được header HTTP `GET / HTTP/1.1` và coi đây là gói tin nhị phân không hợp lệ, lập tức đóng socket.

---

## 3. Giải pháp kỹ thuật chuẩn hóa

### 3.1. Điểm sửa đổi cốt lõi
1. Sửa biến môi trường của Kibana:
   ```yaml
   - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
   ```
2. Mở cổng `9200:9200` để có thể kiểm tra trạng thái Elasticsearch từ máy Host qua cURL/Postman.
3. Mở cổng `5601:5601` để truy cập Dashboard quản trị Kibana từ máy Host.
4. Cấu hình giới hạn bộ nhớ JVM Heap cho Elasticsearch (`ES_JAVA_OPTS=-Xms512m -Xmx512m`) để tránh Elasticsearch chiếm dụng toàn bộ tài nguyên RAM của hệ thống thử nghiệm.
5. Thêm cấu hình **Docker Network Bridge (`efk-net`)** đảm bảo Kibana phân giải được DNS hostname `elasticsearch`.
6. Bổ sung **Healthcheck** để Kibana chỉ kết nối khi Elasticsearch đã sẵn sàng phục vụ.

### 3.2. File `docker-compose.yml` hoàn chỉnh

```yaml
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ports:
      - "9200:9200"
      - "9300:9300"
    networks:
      - efk-net
    healthcheck:
      test: ["CMD-SHELL", "curl -s http://localhost:9200/_cluster/health | grep -q '\"status\":\"green\"\\|\"status\":\"yellow\"'"]
      interval: 10s
      timeout: 5s
      retries: 5

  kibana:
    image: docker.elastic.co/kibana/kibana:7.17.0
    container_name: kibana
    environment:
      # ĐÃ SỬA: Thay cổng 9300 (Transport port) bằng 9200 (HTTP REST API port)
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    ports:
      - "5601:5601"
    depends_on:
      elasticsearch:
        condition: service_healthy
    networks:
      - efk-net

networks:
  efk-net:
    driver: bridge
```

---

## 4. Hướng dẫn khởi chạy & Kiểm thử

### Bước 1: Khởi động hệ thống
Đứng tại thư mục `SS17/bai1/` và thực thi:
```bash
docker-compose up -d
```

### Bước 2: Kiểm tra trạng thái của các Container
```bash
docker-compose ps
```
Cả 2 dịch vụ `elasticsearch` và `kibana` đều phải ở trạng thái `Up` (healthy).

### Bước 3: Kiểm tra trực tiếp cổng 9200 của Elasticsearch
```bash
curl -X GET http://localhost:9200
```
**Kết quả trả về hợp lệ (JSON):**
```json
{
  "name" : "elasticsearch",
  "cluster_name" : "docker-cluster",
  "cluster_uuid" : "abc123xyz...",
  "version" : {
    "number" : "7.17.0",
    "build_flavor" : "default",
    "build_type" : "docker",
    "lucene_version" : "8.11.1"
  },
  "tagline" : "You Know, for Search"
}
```

### Bước 4: Kiểm tra trạng thái kết nối của Kibana
```bash
curl -s http://localhost:5601/api/status | grep '"state":"green"'
```

### Bước 5: Truy cập giao diện người dùng
Mở trình duyệt web bất kỳ và truy cập:
```text
http://localhost:5601
```
Giao diện chào mừng của **Kibana Home** sẽ hiển thị ngay lập tức, không còn thông báo `Kibana server is not ready yet`.

---

## 5. Kết luận rút ra
- Không bao giờ trỏ client HTTP (Kibana, Web App, Logstash) vào cổng `9300`. Luôn luôn sử dụng cổng HTTP `9200`.
- Từ Elasticsearch phiên bản 7.x trở đi, Java High Level REST Client và các ứng dụng chính thức đều chuẩn hóa giao tiếp qua HTTP/RESTful cổng `9200`, chuẩn bị cho việc khai tử hoàn toàn Transport Client.
