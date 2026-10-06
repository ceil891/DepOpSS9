# SS11 - Quản Trị Web Server Nginx: Reverse Proxy, Routing, SSL HTTPS & Performance Optimization

> **Môn học:** DevOps  
> **Chủ đề:** Nginx Reverse Proxy, Path-based Routing, Let's Encrypt SSL/TLS, Zero-Downtime Reload  
> **Tác giả:** Luu Hung  
> **Repository:** [ceil891/DepOpSS9](https://github.com/ceil891/DepOpSS9)  

---

## 📁 Cấu trúc thư mục dự án

```
ss11/
├── README.md                                  # Tài liệu tổng hợp toàn bộ 4 bài tập SS11
│
├── bai1/                                      # Bài 1: Cấu hình Nginx Reverse Proxy Cơ Bản
│   ├── default                                # File cấu hình Nginx proxy port 80 -> port 3000
│   └── README.md                              # Giải thích proxy_pass, cơ chế mã lỗi 502 Bad Gateway
│
├── bai2/                                      # Bài 2: Định tuyến Request đến API Gateway
│   ├── default                                # Cấu hình Path-based Routing (/api/ vs /) & Headers
│   └── README.md                              # Phân tích Header X-Forwarded-For, rủi ro mất IP Client
│
├── bai3/                                      # Bài 3: Bảo mật bằng HTTPS với Let's Encrypt
│   ├── api.my-ecommerce.com.conf              # Cấu hình Nginx HTTPS Port 443 + Redirect 301 Port 80
│   ├── setup-ssl.sh                           # Script tự động cài Certbot & cấp phát chứng chỉ SSL
│   └── README.md                              # Hướng dẫn Certbot, cấu hình viết tay, Auto-Renew 90 ngày
│
└── bai4/                                      # Bài 4: Tối ưu hóa và Reload cấu hình không gián đoạn
    ├── nginx.conf                             # Cấu hình client_max_body_size 10M và block Gzip
    └── README.md                              # So sánh chí mạng Reload vs Restart, lệnh an toàn nginx -t
```

---

## 📑 Tóm tắt nội dung & Đáp án từng bài tập

### 🔹 Bài 1: Cấu hình Nginx Reverse Proxy Cơ Bản
* **Tình huống:** Frontend React chạy tại `localhost:3000`. Cần trỏ request cổng `80` sang cổng `3000` để truy cập trực tiếp qua `http://domain.com`.
* **Cấu hình chính:**
  ```nginx
  server {
      listen 80;
      server_name domain.com;

      location / {
          proxy_pass http://127.0.0.1:3000;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
      }
  }
  ```
* **Ý nghĩa chỉ thị `proxy_pass`:** Thiết lập giao thức, địa chỉ và cổng của upstream server nội bộ mà Nginx sẽ chuyển tiếp request đến, đóng gói lại request và trả response về cho client một cách trong suốt.
* **Bẫy (Ứng dụng React bị sập):**
  * Nginx sẽ trả về mã HTTP: **`502 Bad Gateway`**.
  * **Cơ chế:** Nginx đóng vai trò Gateway/Proxy. Khi cố gắng tạo kết nối TCP tới `127.0.0.1:3000`, do tiến trình React đã chết, kernel OS từ chối kết nối (`TCP RST` / `Connection refused`). Nginx không nhận được phản hồi hợp lệ từ upstream nên sinh mã 502 gửi về client.

---

### 🔹 Bài 2: Định tuyến Request đến API Gateway (Path-based Routing)
* **Tình huống:** Frontend React (`localhost:3000`) và Backend API Gateway (`localhost:8080`) chạy chung trên một domain (Port 80).
* **Cấu hình chính:**
  ```nginx
  # Định tuyến API về Backend Gateway (Port 8080)
  location /api/ {
      proxy_pass http://127.0.0.1:8080;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
  }

  # Định tuyến các trang còn lại về Frontend (Port 3000)
  location / {
      proxy_pass http://127.0.0.1:3000;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
  }
  ```
* **Bẫy (Header `X-Forwarded-For`):**
  * **Nếu không truyền:** Backend chỉ nhìn thấy địa chỉ IP của chính Nginx (`127.0.0.1`).
  * **Hậu quả chí mạng:**
    1. Cơ chế Rate Limiting/Chống Brute-force trên Backend bị hỏng: Khóa nhầm IP `127.0.0.1` -> Chặn toàn bộ người dùng trên hệ thống.
    2. Vô hiệu hóa phát hiện gian lận (Fraud Detection / GeoIP).
    3. Log truy vết bảo mật (Audit Log) vô giá trị vì mọi request đều mang IP 127.0.0.1.

---

### 🔹 Bài 3: Bảo mật bằng HTTPS với Let's Encrypt
* **Lệnh cài đặt Certbot trên Ubuntu:**
  ```bash
  sudo apt update && sudo apt install snapd -y
  sudo snap install core && sudo snap refresh core
  sudo snap install --classic certbot
  sudo ln -sf /snap/bin/certbot /usr/bin/certbot
  ```
* **Lệnh Certbot tự động cấp chứng chỉ và cấu hình Nginx:**
  ```bash
  sudo certbot --nginx -d api.my-ecommerce.com
  ```
* **Cấu hình HTTPS viết tay (Port 443 & Redirect Port 80):**
  * Port 80: `return 301 https://$host$request_uri;`
  * Port 443:
    * `ssl_certificate /etc/letsencrypt/live/api.my-ecommerce.com/fullchain.pem;`
    * `ssl_certificate_key /etc/letsencrypt/live/api.my-ecommerce.com/privkey.pem;`
    * `ssl_protocols TLSv1.2 TLSv1.3;`
* **Bẫy (Chứng chỉ 90 ngày & Auto-Renew):**
  * Tự động renew qua **systemd timer** (`certbot.timer`) hoặc **cronjob**:
    ```cron
    0 3 * * * /usr/bin/certbot renew --quiet --deploy-hook "systemctl reload nginx"
    ```
  * **Điểm chí mạng:** Bắt buộc phải có `--deploy-hook "systemctl reload nginx"` để Nginx nạp chứng chỉ mới vào RAM. Nếu không reload, Nginx vẫn giữ chứng chỉ cũ và website sẽ bị báo lỗi hết hạn sau 90 ngày!

---

### 🔹 Bài 4: Tối ưu hóa và Reload cấu hình không gián đoạn
* **Khắc phục lỗi 413 (Upload ảnh 3MB):**
  * Cấu hình: `client_max_body_size 10M;`
* **Bật nén Gzip:**
  ```nginx
  gzip on;
  gzip_vary on;
  gzip_proxied any;
  gzip_comp_level 6;
  gzip_min_length 256;
  gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript image/svg+xml;
  ```
  *(Lưu ý: Không nén ảnh JPG, PNG, GIF, ZIP vì đã nén sẵn, tránh lãng phí CPU).*
* **Bẫy cực kỳ nguy hiểm trên Production (Restart vs Reload):**
  * **BẮT BUỘC DÙNG:** `systemctl reload nginx` (Graceful Reload - Zero Downtime).
  * **TUYỆT ĐỐI TRÁNH:** `systemctl restart nginx` vì làm ngắt ngang kết nối TCP đang mở (khách hàng đang checkout, đang upload dở bị rớt mạng), và nếu file cấu hình có lỗi cú pháp, Nginx sẽ chết hẳn làm sập toàn bộ hệ thống!
  * **Lệnh kiểm tra cú pháp bắt buộc gõ trước:** `sudo nginx -t`.
  * **Quy trình chuẩn DevOps:**
    ```bash
    sudo nginx -t && sudo systemctl reload nginx
    ```

---

## 🎯 Bảng đối chiếu các câu hỏi bẫy (Pitfalls & Gotchas)

| Bài tập | Câu hỏi bẫy | Đáp án trực diện & Điểm mấu chốt |
|---|---|---|
| **Bài 1** | React ở port 3000 bị sập thì Nginx trả về mã lỗi HTTP nào? | **`502 Bad Gateway`**. Do Nginx không thể kết nối tới upstream (OS phản hồi `Connection refused` / `TCP RST`). Phân biệt với 504 (timeout) và 500 (internal error). |
| **Bài 2** | Tại sao phải truyền Header `X-Forwarded-For`? Nếu không truyền thì Backend thấy IP của ai? | Backend chỉ thấy **IP của Nginx (`127.0.0.1`)**. Dẫn đến lỗi vỡ Rate Limiting (chặn nhầm localhost làm sập web cho toàn bộ khách hàng) và hỏng audit log. |
| **Bài 3** | Chứng chỉ Let's Encrypt chỉ có hạn 90 ngày. Thiết lập tự động gia hạn như thế nào? | Dùng systemd timer hoặc Cronjob có hook reload: `certbot renew --deploy-hook "systemctl reload nginx"`. Nếu thiếu reload, Nginx giữ cert cũ trong RAM gây lỗi hết hạn! |
| **Bài 4** | Trên Production dùng `restart` hay `reload`? Lệnh nào gõ trước tiên để kiểm tra cú pháp? | **Bắt buộc dùng `systemctl reload nginx`** (Zero downtime, an toàn khi có lỗi syntax). Lệnh gõ trước: **`sudo nginx -t`**. Luôn chạy: `sudo nginx -t && sudo systemctl reload nginx`. |

---

## 🚀 Hướng dẫn nộp bài lên GitHub

1. Kiểm tra trạng thái git:
   ```bash
   git status
   ```
2. Thêm các thư mục bài làm:
   ```bash
   git add ss11/
   ```
3. Commit bài làm với thông điệp rõ ràng:
   ```bash
   git commit -m "feat(ss11): Complete Nginx Reverse Proxy, Path Routing, SSL HTTPS and Optimization exercises (Bai 1-4)"
   ```
4. Đẩy mã nguồn lên GitHub:
   ```bash
   git push origin main
   ```
5. Sao chép liên kết thư mục `ss11` trên GitHub và dán vào phần nộp bài trên Portal.
