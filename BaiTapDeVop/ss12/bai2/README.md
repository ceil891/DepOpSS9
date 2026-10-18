# Bài tập 2: Tối ưu Timeout cho Proxy (Vận dụng cơ bản)

> **Môn học:** DevOps  
> **Chủ đề:** Nginx Reverse Proxy Timeout Optimization, Xử lý lỗi 504 Gateway Time-out  
> **Tác giả:** Luu Hung  
> **Repository:** [ceil891/DepOpSS9](https://github.com/ceil891/DepOpSS9)  

---

## 1. Tình huống nghiệp vụ & Vấn đề thực tế

* **Bối cảnh:** Hệ thống Backend viết bằng **Spring Boot** cung cấp endpoint `/api/export/` để người dùng xuất các báo cáo tài chính/thống kê lớn dưới dạng Excel/PDF. Quá trình truy vấn cơ sở dữ liệu lớn và render file mất khoảng **90 giây**.
* **Hiện tượng lỗi:**
  * Khi người dùng kích hoạt tác vụ xuất báo cáo, trình duyệt gửi request qua Nginx Reverse Proxy.
  * Sau chính xác **60 giây**, Nginx ngắt kết nối và trả về mã lỗi HTTP:
    ```text
    504 Gateway Time-out
    ```
  * Mặc dù ứng dụng Spring Boot bên dưới vẫn đang xử lý hoặc xử lý thành công, người dùng không thể nhận được file báo cáo.

* **Cấu hình Nginx ban đầu:**
  ```nginx
  server {
      listen 80;
      server_name api.example.com;

      location /api/export/ {
          proxy_pass http://localhost:8080;
          # Chưa có cấu hình timeout
      }
  }
  ```

---

## 2. Phân tích nguyên nhân phát sinh lỗi `504 Gateway Time-out`

### 2.1. Bản chất của lỗi 504 trong mô hình Reverse Proxy
```
[Client / Browser]
        │
   (1)  │ Gửi request POST /api/export/
        ▼
   [ NGINX Reverse Proxy ]
        │
   (2)  │ Forward request tới http://localhost:8080
        ▼
   [ Spring Boot Backend ] ─── (3) Đang truy vấn DB & tạo báo cáo (tốn 90s)
        │
        │ ... Sau 60s (vượt quá proxy_read_timeout mặc định của Nginx) ...
        │
   [ NGINX Reverse Proxy ] ─── (4) Hết kiên nhẫn! Tự động ngắt kết nối với Spring Boot
        │
   (5)  │ Trả về mã lỗi: 504 Gateway Time-out
        ▼
[Client / Browser]
```

* Trong Nginx, các chỉ thị timeout liên quan đến proxy đều có giá trị mặc định là **`60 giây`** (`60s`):
  * `proxy_connect_timeout 60s;`
  * `proxy_send_timeout 60s;`
  * **`proxy_read_timeout 60s;`** (Thông số quyết định thời gian chờ phản hồi từ Upstream)
* Khi Spring Boot thực hiện tác vụ nặng mất **90 giây**, trong suốt khoảng thời gian từ giây thứ 0 đến giây thứ 60, Spring Boot chưa gửi bất kỳ byte dữ liệu nào về cho Nginx.
* Khi bộ đếm thời gian chạm mốc 60 giây mà Nginx không nhận được tín hiệu đọc dữ liệu nào từ socket của Spring Boot, Nginx chủ động đóng kết nối với upstream và phản hồi cho client mã lỗi `504 Gateway Time-out`.

---

## 3. Cấu hình Nginx sau khi tối ưu Timeout

File đã cấu hình: [`api.example.com.conf`](file:///e:/BaiTapDeVop/ss12/bai2/api.example.com.conf)

```nginx
server {
    listen 80;
    server_name api.example.com;

    # ========================================================
    # 1. Cấu hình chuyên biệt cho tác vụ xuất báo cáo nặng (90s)
    # ========================================================
    location /api/export/ {
        proxy_pass http://localhost:8080;

        # Thiết lập các HTTP Headers chuẩn hóa
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # ----------------------------------------------------
        # TĂNG TIMEOUT LÊN 120 GIÂY (ĐÁP ỨNG TÁC VỤ 90 GIÂY)
        # ----------------------------------------------------
        # Thời gian tối đa để bắt tay kết nối TCP với Backend
        proxy_connect_timeout 120s;

        # Thời gian tối đa để Nginx gửi request data sang Backend
        proxy_send_timeout 120s;

        # Thời gian tối đa Nginx chờ Backend xử lý và gửi phản hồi về (GIẢI QUYẾT LỖI 504)
        proxy_read_timeout 120s;

        # Thời gian tối đa Nginx truyền tải dữ liệu response về phía Client
        send_timeout 120s;

        # Tối ưu hóa bộ nhớ đệm khi truyền file lớn
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    # ========================================================
    # 2. Cấu hình cho các API thông thường (giữ timeout mặc định)
    # ========================================================
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Các API thông thường chỉ nên chờ tối đa 60s
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

---

## 4. Giải thích chi tiết ý nghĩa các thông số Timeout

| Chỉ thị (Directive) | Cú pháp áp dụng | Giá trị mặc định | Ý nghĩa & Vai trò |
| :--- | :--- | :--- | :--- |
| **`proxy_read_timeout`** | `proxy_read_timeout 120s;` | `60s` | **CHỈ THỊ CỐT LÕI KHẮC PHỤC LỖI 504.** Xác định khoảng thời gian tối đa giữa **hai thao tác đọc liên tiếp** từ Upstream server. Khi đặt `120s`, Nginx sẽ kiên nhẫn chờ Spring Boot tính toán và phản hồi dữ liệu trong tối đa 120 giây (vượt qua mốc 90 giây của tác vụ export). |
| **`proxy_connect_timeout`** | `proxy_connect_timeout 120s;` | `60s` | Xác định thời gian tối đa để thiết lập kết nối TCP (TCP 3-way handshake) giữa Nginx và Upstream Backend. Nếu Backend bị quá tải hoặc treo cổng không chấp nhận socket mới trong thời gian này, Nginx sẽ trả về mã lỗi `502 Bad Gateway`. |
| **`proxy_send_timeout`** | `proxy_send_timeout 120s;` | `60s` | Xác định thời gian tối đa giữa **hai thao tác ghi liên tiếp** khi Nginx đẩy dữ liệu request (body, multipart payload lớn) sang Backend. Chỉ tính giữa hai sự kiện write liên tiếp, không phải toàn bộ request. |
| **`send_timeout`** | `send_timeout 120s;` | `60s` | Thiết lập thời gian chờ tối đa giữa **hai thao tác truyền dữ liệu** từ Nginx về cho Client (trình duyệt). Rất hữu ích khi người dùng tải file export nặng qua đường truyền mạng di động hoặc Wi-Fi yếu, tránh việc Nginx tự ngắt giữa chừng. |

> [!NOTE]
> **Điểm mấu chốt:** Các giá trị timeout này **không phải** là thời gian tổng để truyền toàn bộ file hay toàn bộ request, mà là khoảng thời gian tối đa giữa **hai thao tác I/O (đọc/ghi) liên tiếp**. Nếu trong 120 giây mà socket hoàn toàn "im lặng" không có thêm byte dữ liệu nào, Nginx mới kích hoạt ngắt kết nối.

---

## 5. Quy trình kiểm tra và áp dụng cấu hình trên VPS

```bash
# 1. Kiểm tra tính hợp lệ của file cấu hình
sudo nginx -t

# 2. Nạp lại cấu hình vào Nginx không gây downtime
sudo systemctl reload nginx

# 3. Sử dụng curl để giả lập kiểm tra thời gian phản hồi
time curl -i -X POST http://api.example.com/api/export/
```

---

## 6. Kiến trúc DevOps nâng cao: Giải pháp cho tác vụ chạy lâu (Long-Running Tasks)

Mặc dù việc tăng `proxy_read_timeout` lên 120s giải quyết được ngay sự cố tức thời, nhưng trong môi trường Enterprise, việc giữ một HTTP connection đồng bộ (synchronous) kéo dài 90–120 giây tiềm ẩn nhiều rủi ro:
1. **Cạn kiệt Connection Pool:** Mỗi request chờ 90s sẽ chiếm dụng 1 worker connection của Nginx và 1 thread trong Tomcat/Spring Boot, dễ dẫn đến nghẽn cổ chai khi có nhiều người cùng bấm Export.
2. **Trải nghiệm người dùng:** Trình duyệt quay vòng chờ đợi quá lâu, dễ bị người dùng bấm F5 liên tục gây quá tải kép (Cascading Failure).

### 💡 Giải pháp chuẩn Production: Kiến trúc Xử lý Bất Đồng Bộ (Asynchronous Processing)
```
[Client] ── (1) POST /api/export ──> [Spring Boot API]
                                            │
                                      (2) Đẩy Task vào Message Queue (RabbitMQ / Kafka)
                                            │
[Client] <── (3) Trả về HTTP 202 Accepted ──┘ (Kèm Task ID, phản hồi trong 50ms)
    │
    ├── (4) Định kỳ Polling: GET /api/export/status/{taskId}
    │       (Hoặc lắng nghe qua WebSocket / Server-Sent Events)
    │
[Worker Service] ── Lấy Task từ Queue ──> Xử lý 90s ──> Lưu file lên MinIO / AWS S3
                                                                   │
[Client] <── (5) Nhận đường dẫn tải file (Presigned S3 URL) ───────┘
```
