# SS12 - Quản Trị Web Server Nginx Nâng Cao: Xử Lý Sự Cố, Tối Ưu Timeout, HTTP Security Headers & Tích Hợp UFW Firewall Docker

> **Môn học:** DevOps  
> **Chủ đề:** Nginx Troubleshooting, 504 Gateway Timeout Optimization, HTTP Security Headers (Clickjacking, MIME-Sniffing, HSTS), Docker & UFW Firewall Integration  
> **Tác giả:** Luu Hung  
> **Repository:** [ceil891/DepOpSS9](https://github.com/ceil891/DepOpSS9)  

---

## 📁 Cấu trúc thư mục dự án SS12

```text
ss12/
├── README.md                                  # Tài liệu tổng hợp toàn bộ 4 bài tập SS12
│
├── bai1/                                      # Bài 1: Xử lý sự cố sập Nginx (Vận dụng cơ bản)
│   ├── app.conf                               # Cấu hình Nginx đã sửa lỗi cú pháp chấm phẩy (;)
│   └── README.md                              # Phân tích nguyên nhân lỗi parser, lệnh nginx -t, reload vs restart
│
├── bai2/                                      # Bài 2: Tối ưu Timeout cho Proxy (Vận dụng cơ bản)
│   ├── api.example.com.conf                   # Cấu hình Nginx tối ưu timeout 120s cho /api/export/
│   └── README.md                              # Khắc phục lỗi 504 Gateway Timeout, phân tích 4 thông số timeout
│
├── bai3/                                      # Bài 3: Cấu hình Header Security (Vận dụng chuyên sâu)
│   ├── secure.example.com.conf                # Cấu hình Nginx HTTPS với đầy đủ Security Headers
│   └── README.md                              # Giải thích X-Frame-Options, nosniff, HSTS, cờ 'always' & curl -I
│
└── bai4/                                      # Bài 4: Tích hợp UFW và Docker (Vận dụng chuyên sâu)
    ├── docker-compose.yml                     # File compose binding port vào 127.0.0.1:8080:8080
    └── README.md                              # Phân tích Docker bypass UFW, kiến trúc iptables & loopback binding
```

---

## 📑 Tóm tắt nội dung & Đáp án từng bài tập

### 🔹 Bài 1: Xử lý sự cố sập Nginx (Vận dụng cơ bản)
* **Tình huống:** Đội phát triển sửa file `app.conf`, khi reload thì Nginx báo lỗi:
  ```text
  nginx: [emerg] unexpected "proxy_set_header" in /etc/nginx/sites-enabled/app.conf:7
  ```
* **Nguyên nhân gốc rễ:** Dòng số 6 (`proxy_pass http://localhost:8080`) bị **thiếu dấu chấm phẩy (`;`)**. Trong Nginx, dấu `;` là ký tự bắt buộc để kết thúc một chỉ thị. Do thiếu `;`, parser đọc tiếp sang dòng 7 và xem `proxy_set_header` là đối số thứ hai bất hợp lệ của `proxy_pass`.
* **Cấu hình sau khi sửa (`app.conf`):**
  ```nginx
  server {
      listen 80;
      server_name example.com;

      location / {
          proxy_pass http://localhost:8080; # Bổ sung dấu chấm phẩy tại đây
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
      }
  }
  ```
* **Lệnh kiểm tra cấu hình & khởi động an toàn:**
  ```bash
  # 1. Kiểm tra tính hợp lệ cú pháp (Pre-flight check)
  sudo nginx -t

  # 2. Nạp lại cấu hình không gây gián đoạn kết nối (Zero-downtime)
  sudo systemctl reload nginx

  # 3. Khởi động lại dịch vụ nếu đã bị tắt hoàn toàn
  sudo systemctl restart nginx
  ```
* **So sánh sống còn:** `reload` gửi tín hiệu `SIGHUP` sinh worker mới, worker cũ phục vụ xong request hiện tại mới thoát; nếu config lỗi, `reload` từ chối nạp và hệ thống vẫn chạy bình thường. Ngược lại, `restart` tắt phụt mọi tiến trình, nếu config lỗi sẽ làm sập toàn bộ web server (downtime).

---

### 🔹 Bài 2: Tối ưu Timeout cho Proxy (Vận dụng cơ bản)
* **Tình huống:** API xuất báo cáo `/api/export/` của ứng dụng Spring Boot chạy mất 90 giây. Nginx trả về lỗi `504 Gateway Time-out` sau 60 giây (timeout mặc định).
* **Nguyên nhân:** Chỉ thị `proxy_read_timeout` mặc định là `60s`. Trong 90s Spring Boot xử lý dữ liệu và chưa gửi phản hồi, sau 60s Nginx hết kiên nhẫn nên chủ động ngắt kết nối và trả về lỗi 504.
* **Cấu hình tối ưu (`api.example.com.conf`):**
  ```nginx
  server {
      listen 80;
      server_name api.example.com;

      location /api/export/ {
          proxy_pass http://localhost:8080;

          # Tối ưu hóa các thông số Timeout lên 120 giây
          proxy_connect_timeout 120s; # Thời gian chờ bắt tay TCP với backend
          proxy_send_timeout 120s;    # Thời gian chờ gửi request sang backend
          proxy_read_timeout 120s;    # Thời gian chờ backend xử lý và trả response (Khắc phục lỗi 504)
          send_timeout 120s;          # Thời gian chờ truyền response về client

          # Header chuẩn hóa
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
      }
  }
  ```
* **Ý nghĩa thông số:** `proxy_read_timeout` là thông số quan trọng nhất giải quyết trực tiếp lỗi 504. Nó đo khoảng thời gian tối đa giữa 2 thao tác đọc liên tiếp từ upstream server.

---

### 🔹 Bài 3: Cấu hình Header Security (Vận dụng chuyên sâu)
* **Tình huống:** Đội An Ninh Thông Tin yêu cầu trả về các HTTP Security Headers để phòng chống các cuộc tấn công web phổ biến: Clickjacking, MIME-sniffing, SSL Stripping.
* **Cấu hình hoàn chỉnh (`secure.example.com.conf`):**
  ```nginx
  server {
      listen 443 ssl http2;
      server_name secure.example.com;

      ssl_certificate /etc/nginx/ssl/server.crt;
      ssl_certificate_key /etc/nginx/ssl/server.key;

      # HTTP Security Headers (Cờ 'always' bắt buộc có để hoạt động cả trên trang lỗi 4xx/5xx)
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

      location / {
          proxy_pass http://localhost:8080;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
      }
  }
  ```
* **Phân tích cơ chế bảo mật:**
  * `X-Frame-Options: SAMEORIGIN`: Chống tấn công Clickjacking bằng cách chỉ cho phép nhúng website vào iframe nếu cùng tên miền.
  * `X-Content-Type-Options: nosniff`: Chống tấn công MIME Confusion / Sniffing, cấm trình duyệt tự tiện suy đoán kiểu file để thực thi mã độc.
  * `Strict-Transport-Security: max-age=31536000; includeSubDomains` (HSTS): Bắt buộc trình duyệt chỉ liên lạc qua HTTPS trong 1 năm, tự động chuyển đổi mọi kết nối HTTP sang HTTPS ở client để chống nghe lén và bẻ khóa SSL Stripping.
* **Lệnh kiểm chứng bằng `curl`:**
  ```bash
  curl -I https://secure.example.com
  # Hoặc kiểm tra bỏ qua kiểm định SSL self-signed:
  curl -I -k https://secure.example.com
  ```

---

### 🔹 Bài 4: Tích hợp UFW và Docker (Vận dụng chuyên sâu)
* **Tình huống:** UFW đã chặn cổng `8080`, nhưng Docker chạy `docker-compose.yml` với `- "8080:8080"` khiến cổng `8080` vẫn bị public trực tiếp ra Internet.
* **Nguyên nhân gốc rễ (Docker Bypass UFW):**
  * UFW đặt quy tắc lọc trong chuỗi **`INPUT`** của bảng `filter`.
  * Docker tự động can thiệp vào bảng `nat` (chuỗi **`PREROUTING`**) để thực hiện DNAT chuyển địa chỉ đích thành IP nội bộ của container.
  * Sau khi DNAT, gói tin được kernel chuyển hướng sang chuỗi **`FORWARD`** (chuỗi `DOCKER`), **hoàn toàn bỏ qua chuỗi `INPUT` của UFW**.
* **Cấu hình sửa đổi (`docker-compose.yml`):**
  ```yaml
  version: '3.8'
  services:
    backend:
      image: my-spring-boot-app:latest
      container_name: spring_boot_backend
      restart: unless-stopped
      ports:
        # Ràng buộc tường minh vào địa chỉ loopback 127.0.0.1
        - "127.0.0.1:8080:8080"
  ```
* **Cơ chế ngăn chặn truy cập trái phép:**
  * Khi cấu hình `"127.0.0.1:8080:8080"`, Docker chỉ bind cổng trên giao diện mạng Loopback (`lo`). Rule iptables chỉ chấp nhận các gói tin có IP đích là `127.0.0.1`.
  * Các gói tin từ bên ngoài Internet đi vào card mạng công cộng (`eth0` / `ens3`) sẽ không khớp quy tắc DNAT này và bị chặn đứng.
  * Nginx chạy trên cùng máy chủ kết nối qua `http://127.0.0.1:8080` hoàn toàn thành công.
* **Lệnh kiểm chứng:**
  ```bash
  # Kiểm tra socket chỉ lắng nghe trên 127.0.0.1
  sudo ss -tulpn | grep 8080
  # Kiểm tra kết nối từ ngoài (bị từ chối)
  curl -I --connect-timeout 5 http://<PUBLIC_IP_VPS>:8080
  # Kiểm tra kết nối nội bộ (thành công)
  curl -I http://127.0.0.1:8080
  ```

---

## 🚀 Hướng dẫn nộp bài lên GitHub & Portal

1. **Commit và đẩy mã nguồn lên GitHub:**
   ```bash
   git add ss12/
   git commit -m "feat(ss12): complete all 4 devops exercises on nginx troubleshooting, timeouts, security headers, ufw and docker"
   git push origin main
   ```
2. **Nộp bài lên Portal:**
   * Copy đường link thư mục bài tập trên GitHub:
     `https://github.com/ceil891/DepOpSS9/tree/main/ss12`
   * Hoặc đường link từng bài:
     * Bài 1: `https://github.com/ceil891/DepOpSS9/tree/main/ss12/bai1`
     * Bài 2: `https://github.com/ceil891/DepOpSS9/tree/main/ss12/bai2`
     * Bài 3: `https://github.com/ceil891/DepOpSS9/tree/main/ss12/bai3`
     * Bài 4: `https://github.com/ceil891/DepOpSS9/tree/main/ss12/bai4`
   * Dán liên kết vào ô nộp bài tập tương ứng trên Portal.
