# Bài tập 3: Cấu hình Header Security (Vận dụng chuyên sâu)

> **Môn học:** DevOps  
> **Chủ đề:** Web Application Security, Nginx HTTP Security Headers, OWASP Hardening  
> **Tác giả:** Luu Hung  
> **Repository:** [ceil891/DepOpSS9](https://github.com/ceil891/DepOpSS9)  

---

## 1. Tình huống nghiệp vụ & Yêu cầu từ Đội An Ninh Thông Tin (Security Team)

* **Bối cảnh:** Trong đợt rà quét bảo mật định kỳ (Security Assessment / Pentest), đội ngũ an ninh phát hiện hệ thống web `secure.example.com` chạy trên nền tảng HTTPS nhưng máy chủ Nginx chưa trả về các **HTTP Security Headers**.
* **Nguy cơ tiềm ẩn:**
  1. Trang web có thể bị các website độc hại nhúng vào trong thẻ `<iframe>` để thực hiện tấn công **Clickjacking** (đánh cắp thao tác nhấp chuột của người dùng nhằm chuyển tiền hoặc đổi mật khẩu).
  2. Trình duyệt tự động suy đoán sai định dạng file (MIME-sniffing), dẫn đến việc thực thi các đoạn mã độc JavaScript trá hình dưới dạng file ảnh đại diện (`.png`, `.jpg`).
  3. Người dùng truy cập lần đầu qua giao thức không mã hóa HTTP có thể bị tấn công bẻ khóa chứng chỉ (**SSL Stripping / Man-In-The-Middle**).
* **Yêu cầu:** Cấu hình Nginx trả về tối thiểu 3 header bảo mật cốt lõi:
  * `X-Frame-Options: SAMEORIGIN`
  * `X-Content-Type-Options: nosniff`
  * `Strict-Transport-Security: max-age=31536000; includeSubDomains`

---

## 2. File cấu hình Nginx hoàn chỉnh

File cấu hình: [`secure.example.com.conf`](file:///e:/BaiTapDeVop/ss12/bai3/secure.example.com.conf)

```nginx
server {
    listen 443 ssl http2;
    server_name secure.example.com;

    # Chứng chỉ SSL/TLS
    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    # Tiêu chuẩn mã hóa TLS an toàn
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # ========================================================
    # CẤU HÌNH HTTP SECURITY HEADERS (THEO YÊU CẦU CỦA BÀI TẬP)
    # Lưu ý sống còn: Phải luôn có cờ 'always' ở cuối mỗi chỉ thị!
    # ========================================================

    # 1. Chống tấn công Clickjacking / UI Redressing
    add_header X-Frame-Options "SAMEORIGIN" always;

    # 2. Chống tấn công MIME-Type Sniffing
    add_header X-Content-Type-Options "nosniff" always;

    # 3. HTTP Strict Transport Security (HSTS) - Bắt buộc HTTPS 1 năm
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # [Khuyến nghị mở rộng] Các header bảo mật nâng cao
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

    location / {
        proxy_pass http://localhost:8080;

        # Thiết lập các HTTP headers định danh client
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

# Tự động điều hướng toàn bộ request HTTP (Port 80) sang HTTPS (Port 443)
server {
    listen 80;
    server_name secure.example.com;
    return 301 https://$host$request_uri;
}
```

---

## 3. Phân tích chi tiết ý nghĩa và cơ chế phòng thủ của từng Header

### 3.1. `X-Frame-Options: SAMEORIGIN`
* **Hiểm họa (Tấn công Clickjacking / UI Redressing):**  
  Kẻ tấn công tạo một website lừa đảo và nhúng website ngân hàng/thương mại điện tử của bạn vào một thẻ `<iframe src="https://secure.example.com/checkout">` trong suốt (độ mờ `opacity: 0`). Sau đó chúng đặt một nút bấm giả mạo (ví dụ: *"Bấm vào đây để nhận 1 tỷ đồng"*) nằm đè ngay vị trí nút *"Xác nhận chuyển khoản"* của website bị nhúng. Khi người dùng bấm nút, thực chất họ đang click vào nút thanh toán mà không hề hay biết.
* **Cơ chế phòng thủ:**
  * Giá trị `SAMEORIGIN` chỉ thị cho trình duyệt: **Chỉ cho phép** nhúng trang web này vào thẻ `<iframe>`, `<frame>`, `<embed>`, `<object>` nếu trang web nhúng có **cùng domain, protocol và port** với website hiện tại.
  * Mọi trang web bên ngoài cố tình nhúng qua iframe đều sẽ bị trình duyệt từ chối hiển thị (hiển thị khung trống).
  * *(Các giá trị khác: `DENY` - Cấm hoàn toàn mọi iframe kể cả cùng domain; hoặc hiện đại hơn dùng chỉ thị `frame-ancestors 'self'` trong CSP).*

---

### 3.2. `X-Content-Type-Options: nosniff`
* **Hiểm họa (MIME Confusion / MIME-Sniffing Attack):**  
  Nhiều trình duyệt có tính năng tự động "đoán" (sniffing) định dạng nội dung của một file bất kể server trả về `Content-Type` là gì. Giả sử hacker upload một file ảnh đại diện tên `avatar.jpg`, nhưng bên trong file thực chất chứa mã độc JavaScript độc hại (`<script>alert(document.cookie)</script>`). Nếu không có cờ này, khi trình duyệt tải file `avatar.jpg`, nó nhận thấy có mã script bên trong và tự ý thực thi đoạn mã đó như một file JavaScript (gây ra lỗ hổng XSS).
* **Cơ chế phòng thủ:**
  * Giá trị `nosniff` bắt buộc trình duyệt phải tuân thủ nghiêm ngặt theo đúng định dạng được chỉ định trong header `Content-Type` do máy chủ trả về.
  * Trình duyệt sẽ **tuyệt đối không tự ý đoán (sniff)** kiểu MIME của file. Nếu server báo file là `image/jpeg` hoặc `text/plain`, trình duyệt sẽ chỉ xem nó là ảnh hoặc văn bản thô, cấm ngặt việc thực thi nó như mã lệnh JavaScript hay CSS.

---

### 3.3. `Strict-Transport-Security: max-age=31536000; includeSubDomains` (HSTS)
* **Hiểm họa (Tấn công SSL Stripping / Man-In-The-Middle):**  
  Người dùng thường chỉ gõ `example.com` thay vì `https://example.com`. Request đầu tiên sẽ gửi qua cổng `80` (HTTP thô). Kẻ tấn công trên cùng mạng Wi-Fi công cộng (quán cà phê, sân bay) có thể can thiệp gói tin, đóng vai trò Proxy chặn kết nối HTTPS với máy chủ thật và trả về HTTP không mã hóa cho người dùng (SSL Stripping), từ đó xem trộm toàn bộ mật khẩu, cookie và thông tin thẻ tín dụng.
* **Cơ chế phòng thủ:**
  * **HSTS (HTTP Strict Transport Security)** là cơ chế bắt buộc trình duyệt ghi nhớ rằng: Tên miền này **CHỈ ĐƯỢC PHÉP TRUY CẬP BẰNG HTTPS**.
  * `max-age=31536000`: Thời gian hiệu lực là 1 năm (31.536.000 giây). Trong suốt 1 năm tiếp theo, mỗi khi người dùng gõ `http://secure.example.com`, trình duyệt sẽ **tự động chuyển hướng nội bộ (Internal 307 Redirect)** sang `https://secure.example.com` trước khi gửi request ra khỏi máy tính. Không có bất kỳ gói tin không mã hóa nào bị rò rỉ ra mạng.
  * `includeSubDomains`: Áp dụng quy tắc bảo vệ nghiêm ngặt này cho tất cả các subdomain con (ví dụ: `api.secure.example.com`, `admin.secure.example.com`).
  * `preload`: Cho phép đưa tên miền vào danh sách HSTS Preload List nhúng sẵn trong mã nguồn của Google Chrome, Firefox, Safari. Ngay cả lần truy cập đầu tiên của người dùng mới tinh cũng tự động dùng HTTPS.

---

## 4. Tầm quan trọng chí mạng của từ khóa `always` trong Nginx

> [!WARNING]
> **Cạm bẫy kinh điển trong cấu hình Nginx:**
> Theo tài liệu chính thức của module `ngx_http_headers_module`, nếu bạn viết:
> ```nginx
> add_header X-Frame-Options "SAMEORIGIN";
> ```
> Nginx **CHỈ** gắn header này khi mã trạng thái HTTP là thành công hoặc chuyển hướng: `200, 201, 204, 206, 301, 302, 303, 304, 307, 308`.
>
> Khi hệ thống gặp sự cố và trả về các mã lỗi (`400 Bad Request`, `401 Unauthorized`, `403 Forbidden`, `404 Not Found`, `500 Internal Error`, `502 Bad Gateway`, `504 Gateway Timeout`), Nginx sẽ **TỰ ĐỘNG LOẠI BỎ** header này!
> Kẻ tấn công có thể cố tình kích hoạt các trang lỗi để khai thác Clickjacking hoặc tấn công vào các trang lỗi không được bảo vệ.
>
> **Giải pháp:** Luôn luôn thêm cờ **`always`** ở cuối directive:
> ```nginx
> add_header X-Frame-Options "SAMEORIGIN" always;
> add_header X-Content-Type-Options "nosniff" always;
> add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
> ```
> Cờ `always` ép buộc Nginx phải gắn các security headers vào **MỌI response**, bất kể mã trạng thái là 200 hay 500.

---

## 5. Kiểm chứng cấu hình bằng lệnh `curl -I`

Để kiểm tra xem máy chủ đã trả về đầy đủ các header bảo mật chưa, chạy lệnh `curl -I` (hoặc `curl -IL`) từ terminal:

### Câu lệnh kiểm tra:
```bash
# Kiểm tra headers trả về từ endpoint HTTPS
curl -I https://secure.example.com

# Nếu đang test trên máy nội bộ dùng Self-Signed Certificate:
curl -I -k https://secure.example.com

# Nếu test trực tiếp qua localhost chỉ định Host header:
curl -I -k -H "Host: secure.example.com" https://127.0.0.1
```

### Kết quả mẫu trả về đạt chuẩn (Response Headers):
```http
HTTP/2 200 
server: nginx/1.24.0 (Ubuntu)
date: Sun, 18 Oct 2026 12:00:00 GMT
content-type: text/html; charset=UTF-8
connection: keep-alive
x-frame-options: SAMEORIGIN
x-content-type-options: nosniff
strict-transport-security: max-age=31536000; includeSubDomains; preload
x-xss-protection: 1; mode=block
referrer-policy: strict-origin-when-cross-origin
permissions-policy: camera=(), microphone=(), geolocation=()
```

---

## 6. Công cụ đánh giá bảo mật trực tuyến (Security Audit)

Sau khi deploy lên môi trường Production với domain công khai, kỹ sư DevOps có thể sử dụng các công cụ đánh giá uy tín để lấy chứng chỉ bảo mật:
1. **[SecurityHeaders.com](https://securityheaders.com/):** Chấm điểm cấu hình HTTP Security Header từ điểm `F` lên điểm `A+`.
2. **[SSL Labs Qualys](https://www.ssllabs.com/ssltest/):** Kiểm tra độ an toàn của cấu hình SSL/TLS và HSTS (Mục tiêu đạt điểm `A+`).
