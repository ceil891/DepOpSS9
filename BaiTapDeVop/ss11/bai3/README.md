# Bài 3: Bảo mật bằng HTTPS với Let's Encrypt

> **Môn học:** DevOps  
> **Chủ đề:** SSL/TLS Certificate, Certbot Automation, Nginx HTTPS Reverse Proxy, Auto-Renewal  

---

## 1. Tình huống nghiệp vụ & Mục tiêu

* **Tình huống:** Google và các trình duyệt hiện đại gắn cảnh báo nguy hiểm "Not Secure" đối với các website không sử dụng HTTPS, gây ảnh hưởng nghiêm trọng tới uy tín thương hiệu và SEO của sàn thương mại điện tử. Bạn cần tích hợp chứng chỉ SSL miễn phí từ Let's Encrypt cho domain `api.my-ecommerce.com`.
* **Mục tiêu:**
  * Nắm vững chuỗi lệnh cài đặt Certbot trên hệ điều hành Ubuntu Linux.
  * Sử dụng lệnh Certbot để cấp phát SSL tự động và cấu hình Nginx.
  * Tự tay viết file cấu hình Nginx cho HTTPS (Port 443) chuẩn chỉnh theo tiêu chuẩn ngành, hiểu rõ các file chứng chỉ (`fullchain.pem`, `privkey.pem`).
  * Giải quyết câu hỏi bẫy về việc gia hạn tự động chứng chỉ 90 ngày (Auto-renew) và tầm quan trọng sống còn của việc reload Nginx sau khi gia hạn.

---

## 2. Chuỗi lệnh cài đặt `certbot` và `python3-certbot-nginx` trên Ubuntu

### Cách 1: Sử dụng Snapd (Khuyến nghị chính thức từ EFF & Certbot)
EFF (Electronic Frontier Foundation) khuyến cáo cài đặt Certbot thông qua Snap để luôn nhận được phiên bản mới nhất, sửa lỗi bảo mật và tự động tích hợp systemd timer:
```bash
# 1. Cập nhật chỉ mục gói phần mềm
sudo apt update -y

# 2. Cài đặt môi trường Snapd (nếu chưa có)
sudo apt install snapd -y

# 3. Đảm bảo lõi snap core ở phiên bản mới nhất
sudo snap install core
sudo snap refresh core

# 4. Cài đặt Certbot ở chế độ classic
sudo snap install --classic certbot

# 5. Tạo liên kết biểu tượng (symlink) để gọi lệnh certbot trực tiếp
sudo ln -sf /snap/bin/certbot /usr/bin/certbot
```

### Cách 2: Cài đặt thông qua APT Repository (Truyền thống)
```bash
sudo apt update -y
sudo apt install -y certbot python3-certbot-nginx
```

---

## 3. Lệnh Certbot tự động cấp phát SSL và cấu hình Nginx

Sau khi đảm bảo domain `api.my-ecommerce.com` đã được trỏ bản ghi DNS (Record A) về địa chỉ IP của VPS và Port 80 đang mở, chạy lệnh:

```bash
sudo certbot --nginx -d api.my-ecommerce.com
```

### 💡 Lệnh tối ưu cho kịch bản CI/CD Automation (Không yêu cầu tương tác thủ công):
```bash
sudo certbot --nginx \
    -d api.my-ecommerce.com \
    --agree-tos \
    --email admin@my-ecommerce.com \
    --non-interactive \
    --redirect
```
* **Giải thích các tham số:**
  * `--nginx`: Sử dụng Nginx plugin để xác thực quyền sở hữu tên miền (HTTP-01 challenge) và tự động ghi cấu hình SSL vào block server của Nginx.
  * `-d api.my-ecommerce.com`: Chỉ định domain cần cấp chứng chỉ.
  * `--agree-tos`: Tự động đồng ý với điều khoản dịch vụ của Let's Encrypt.
  * `--email admin@my-ecommerce.com`: Email nhận thông báo kỹ thuật và cảnh báo khi chứng chỉ sắp hết hạn.
  * `--non-interactive`: Chạy không tương tác (thích hợp cho script).
  * `--redirect`: Tự động cấu hình chuyển hướng HTTP (port 80) sang HTTPS (port 443).

---

## 4. File cấu hình Nginx viết tay chuẩn cho HTTPS (Port 443)

File đặt tại: `/etc/nginx/sites-available/api.my-ecommerce.com`

```nginx
# =============================================================================
# BLOCK 1: HTTP (PORT 80) -> TỰ ĐỘNG CHUYỂN HƯỚNG VĨNH VIỄN SANG HTTPS
# =============================================================================
server {
    listen 80;
    listen [::]:80;
    server_name api.my-ecommerce.com;

    # Mã HTTP 301 Permanent Redirect giữ nguyên path và query string
    return 301 https://$host$request_uri;
}

# =============================================================================
# BLOCK 2: HTTPS (PORT 443) -> XỬ LÝ SSL/TLS & REVERSE PROXY VÀO BACKEND
# =============================================================================
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.my-ecommerce.com;

    # -------------------------------------------------------------------------
    # CHỨNG CHỈ SSL VÀ PRIVATE KEY TỪ LET'S ENCRYPT
    # -------------------------------------------------------------------------
    # 1. ssl_certificate: File fullchain.pem chứa cả Server Cert và Intermediate CA Cert
    ssl_certificate /etc/letsencrypt/live/api.my-ecommerce.com/fullchain.pem;

    # 2. ssl_certificate_key: File privkey.pem chứa Private Key bí mật tuyệt đối
    ssl_certificate_key /etc/letsencrypt/live/api.my-ecommerce.com/privkey.pem;

    # -------------------------------------------------------------------------
    # THIẾT LẬP BẢO MẬT SSL/TLS NÂNG CAO (Theo chuẩn Mozilla Intermediate)
    # -------------------------------------------------------------------------
    # Chỉ cho phép TLS 1.2 và TLS 1.3
    ssl_protocols TLSv1.2 TLSv1.3;

    # Các thuật toán mã hóa (Ciphers) mạnh, chống tấn công POODLE, BEAST
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Tối ưu hóa bộ đệm phiên TLS để tăng tốc kết nối lặp lại
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    # OCSP Stapling: Tăng tốc độ kiểm tra tính hợp lệ của chứng chỉ
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # HSTS: Yêu cầu trình duyệt luôn luôn dùng HTTPS trong 2 năm
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;

    # -------------------------------------------------------------------------
    # REVERSE PROXY SANG BACKEND API GATEWAY (PORT 8080)
    # -------------------------------------------------------------------------
    location / {
        proxy_pass http://127.0.0.1:8080;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_http_version 1.1;
    }
}
```

---

## 5. Phân tích câu hỏi bẫy: Chứng chỉ Let's Encrypt chỉ có hạn 90 ngày. Thiết lập tự động gia hạn (Renew) như thế nào trên Linux?

### 👉 Bản chất của thời hạn 90 ngày:
Let's Encrypt áp dụng thời hạn 90 ngày nhằm:
1. Giảm thiểu rủi ro bị lộ khóa bí mật (Private Key compromise).
2. Thúc đẩy các kỹ sư DevOps tự động hóa hoàn toàn quy trình quản trị hạ tầng (Automation-first mindset).
Certbot sẽ bắt đầu tự động gia hạn khi chứng chỉ còn **dưới 30 ngày** trước khi hết hạn.

---

### ⚙️ Cách 1: Tận dụng Systemd Timer (Mặc định khi cài đặt Certbot)
Khi cài Certbot qua Snap hoặc APT, Linux đã tự động tạo một `systemd.timer` chạy định kỳ 2 lần mỗi ngày:
* **Kiểm tra trạng thái timer:**
  ```bash
  systemctl status certbot.timer
  # hoặc liệt kê các timer đang chạy:
  systemctl list-timers | grep certbot
  ```
* **Timer này làm gì?** Nó chạy lệnh `certbot -q renew` ngầm. Nếu chứng chỉ chưa đến hạn dưới 30 ngày, lệnh sẽ không làm gì. Nếu còn dưới 30 ngày, nó sẽ tự động liên hệ máy chủ Let's Encrypt để xin cấp mới.

---

### ⚙️ Cách 2: Thiết lập Cronjob thủ công chuẩn DevOps Production (Khuyên dùng)
Để chủ động kiểm soát thời điểm gia hạn và tích hợp reload web server, ta thiết lập Cronjob:

1. Mở trình soạn thảo cronjob của quyền `root`:
   ```bash
   sudo crontab -e
   ```
2. Thêm dòng sau vào cuối file (chạy vào 03:00 sáng hàng ngày):
   ```cron
   0 3 * * * /usr/bin/certbot renew --quiet --deploy-hook "systemctl reload nginx"
   ```

---

### ⚠️ Bẫy chí mạng: Tại sao bắt buộc phải có `--deploy-hook "systemctl reload nginx"`?
* Khi Certbot gia hạn thành công, nó sẽ tải file chứng chỉ mới và ghi đè vào thư mục `/etc/letsencrypt/live/...`.
* Tuy nhiên, tiến trình Nginx đang chạy **vẫn đang nạp chứng chỉ cũ trong bộ nhớ RAM**.
* **Hậu quả nếu KHÔNG reload Nginx:** Khi chứng chỉ cũ hết hạn (sau ngày thứ 90), mặc dù trên ổ đĩa file đã mới, người dùng truy cập web vẫn bị trình duyệt chặn đứng với lỗi đỏ chót: **`NET::ERR_CERT_DATE_INVALID` (Chứng chỉ đã hết hạn)**!
* Tham số `--deploy-hook "systemctl reload nginx"` đảm bảo: **Chỉ khi nào gia hạn thành công**, Certbot mới kích hoạt lệnh reload Nginx để nạp chứng chỉ mới vào RAM mà không gây gián đoạn bất kỳ kết nối nào của khách hàng (Zero-downtime).

---

### 🧪 Lệnh kiểm tra thử nghiệm (Dry-Run Test):
Để đảm bảo toàn bộ cơ chế renew và web server hoạt động hoàn hảo mà không cần đợi đến 60 ngày sau:
```bash
sudo certbot renew --dry-run
```
Nếu màn hình thông báo `Congratulations, all simulated renewals succeeded`, hệ thống đã sẵn sàng vận hành tự động trọn đời.
