# Bài 4: Tối ưu hóa và Reload cấu hình không gián đoạn

> **Môn học:** DevOps  
> **Chủ đề:** Nginx Performance Tuning (Gzip, Upload Limit), Zero-Downtime Reload, Safe Deployment  

---

## 1. Tình huống nghiệp vụ & Mục tiêu

* **Tình huống nghiệp vụ:**
  * Người dùng upload avatar dung lượng 3MB bị lỗi **`413 Request Entity Too Large`** do giới hạn mặc định của Nginx chỉ là 1MB.
  * Tốc độ tải trang chậm do các file tài nguyên tĩnh JavaScript, CSS, HTML, JSON có kích thước lớn chưa được nén.
* **Mục tiêu:**
  * Sửa cấu hình Nginx cho phép upload file lên đến 10MB (`client_max_body_size`).
  * Bật và tinh chỉnh tính năng nén **Gzip** cho các định dạng văn bản để giảm băng thông và tăng tốc tải trang.
  * Giải quyết câu hỏi bẫy cực kỳ nguy hiểm trong môi trường Production: Phân biệt sự khác nhau chí mạng giữa `systemctl restart nginx` và `systemctl reload nginx`, cơ chế Zero-downtime và lệnh kiểm tra cú pháp an toàn.

---

## 2. Đoạn cấu hình bổ sung `client_max_body_size` và block `gzip`

File cấu hình tại: `/etc/nginx/nginx.conf` (hoặc đặt trong block `http` / `server` tương ứng):

```nginx
http {
    # ... Các cấu hình cơ bản khác ...

    # =========================================================================
    # 1. KHẮC PHỤC LỖI 413: CHO PHÉP UPLOAD LÊN ĐẾN 10MB
    # =========================================================================
    # Mặc định: client_max_body_size 1m; -> Gây lỗi 413 khi tải file 3MB
    client_max_body_size 10M;
    client_body_buffer_size 128k;

    # =========================================================================
    # 2. BẬT TÍNH NĂNG NÉN GZIP ĐỂ TĂNG TỐC ĐỘ TẢI TRANG
    # =========================================================================
    # Kích hoạt module Gzip
    gzip on;

    # Thêm header 'Vary: Accept-Encoding' giúp Proxy/CDN phục vụ đúng phiên bản nén
    gzip_vary on;

    # Cho phép nén đối với cả các request đi qua Proxy trung gian
    gzip_proxied any;

    # Mức độ nén từ 1 (nhanh nhất, nén ít) đến 9 (chậm nhất, nén tối đa):
    # Mức 6 là điểm cân bằng vàng (sweet spot) giữa tỉ lệ nén và hiệu năng CPU
    gzip_comp_level 6;

    # Kích thước file tối thiểu (bytes) để kích hoạt nén (dưới 256 bytes nén lại sẽ nặng hơn)
    gzip_min_length 256;

    # Số lượng và dung lượng bộ đệm nén
    gzip_buffers 16 8k;

    # Phiên bản HTTP hỗ trợ
    gzip_http_version 1.1;

    # Danh sách các định dạng MIME types cần nén (HTML được nén tự động theo mặc định)
    gzip_types
        text/plain
        text/css
        application/json
        application/javascript
        text/xml
        application/xml
        application/xml+rss
        text/javascript
        image/svg+xml;

    # ...
}
```

> **Lưu ý chuyên môn về phạm vi đặt `client_max_body_size`:**
> * Đặt trong `http { ... }`: Áp dụng cho toàn bộ các server/website trên VPS.
> * Đặt trong `server { ... }`: Áp dụng cho một website cụ thể.
> * Đặt trong `location /api/upload { ... }`: Chỉ cho phép upload 10MB tại API tải file/ảnh, các endpoint khác vẫn giữ giới hạn 1MB để chống tấn công DoS/DDoS qua payload lớn.

> **Lưu ý về các định dạng KHÔNG nén Gzip:**
> * Tuyệt đối không thêm ảnh JPG, PNG, GIF, video MP4 hoặc file ZIP vào `gzip_types`. Bản thân các định dạng này đã được nén chặt chẽ bằng thuật toán chuyên dụng. Việc cố tình nén Gzip sẽ không làm giảm thêm byte nào mà làm lãng phí 100% CPU của VPS!

---

## 3. Phân tích câu hỏi bẫy cực kỳ nguy hiểm trên Production

### ❓ Câu hỏi: Trên Production, bạn dùng lệnh `systemctl restart nginx` hay `systemctl reload nginx`? Giải thích sự khác biệt chí mạng đối với trải nghiệm khách hàng đang online. Lệnh nào nên gõ trước tiên để kiểm tra lỗi cú pháp file config?

---

### 👉 Đáp án khẳng định:
* Trên môi trường Production, **TUYỆT ĐỐI KHÔNG DÙNG `systemctl restart nginx`**.
* **BẮT BUỘC DÙNG `systemctl reload nginx`** (hoặc `nginx -s reload`).
* Lệnh **BẮT BUỘC** phải gõ trước tiên trước khi áp dụng cấu hình là: **`sudo nginx -t`**.

---

### 🔍 So sánh chi tiết sự khác biệt chí mạng giữa `restart` và `reload`:

| Tiêu chí so sánh | `systemctl restart nginx` ❌ | `systemctl reload nginx` ✅ (Zero Downtime) |
|---|---|---|
| **Cơ chế hoạt động** | **Kill & Re-spawn:** Tắt đột ngột tiến trình Master và toàn bộ Worker Processes hiện tại, giải phóng socket, sau đó khởi động lại tiến trình mới từ đầu. | **Graceful Reload:** Master process đọc file config mới. Nếu hợp lệ, nó sinh ra (spawn) các Worker Processes MỚI để nhận request mới. Các Worker Processes CŨ tiếp tục xử lý nốt các request đang dang dở rồi mới kết thúc (graceful shutdown). |
| **Downtime** | **Có Downtime:** Hệ thống tạm dừng phục vụ trong khoảng từ vài trăm mili-giây đến vài giây. | **Zero Downtime (0s):** Không có bất kỳ khoảng gián đoạn nào, dịch vụ liên tục 100%. |
| **Trải nghiệm khách hàng đang Online** | **GIÁN ĐOẠN NGHIÊM TRỌNG:**<br>- Khách hàng đang trong quá trình thanh toán VNPay/Momo bị rớt kết nối (`Connection reset by peer`).<br>- Khách hàng đang upload file 9MB gần xong bị đứt mạng giữa chừng và báo lỗi hỏng đơn.<br>- Mất toàn bộ giỏ hàng hoặc session đang xử lý. | **HOÀN HẢO & LIỀN MẠCH:**<br>- Khách hàng đang kết nối tiếp tục được phục vụ bởi worker cũ cho tới khi hoàn tất phiên làm việc.<br>- Khách hàng mới gửi request lập tức được worker mới phục vụ với cấu hình mới. |
| **Rủi ro khi file config bị lỗi cú pháp (Syntax Error)** | **THẢM HỌA PRODUCTION (SYSTEM OUTAGE):**<br>- Nginx tắt toàn bộ worker cũ.<br>- Sau đó đọc config mới thấy lỗi cú pháp -> Nginx **sập hoàn toàn (Dead)** và không thể bật lại!<br>- Toàn bộ hệ thống downtime kéo dài cho tới khi kỹ sư vào sửa lỗi. | **AN TOÀN TUYỆT ĐỐI:**<br>- Master process kiểm tra config mới thấy lỗi -> Nginx ghi log lỗi và **từ chối áp dụng config mới**.<br>- Master process **giữ nguyên toàn bộ Worker cũ** tiếp tục chạy với config cũ ổn định -> Website không hề bị sập! |

---

### 🛡️ Lệnh kiểm tra bắt buộc trước tiên: `sudo nginx -t`

Lệnh `nginx -t` có nhiệm vụ:
1. Đọc và kiểm tra cú pháp (syntax) của toàn bộ các file cấu hình Nginx trong hệ thống.
2. Kiểm tra tính hợp lệ và quyền truy cập vào các file cấu hình phụ, file chứng chỉ SSL và file log.
3. Không làm ảnh hưởng hay thay đổi bất kỳ tiến trình đang chạy nào.

```bash
$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

---

### 🚀 Quy trình chuẩn DevOps triển khai cấu hình an toàn trên Production:

Luôn kết hợp lệnh kiểm tra cú pháp và reload an toàn trên một dòng lệnh bằng toán tử điều kiện `&&`:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

> **Nguyên lý hoạt động của lệnh trên:**
> Nhờ toán tử logic `&&`, nếu `sudo nginx -t` phát hiện bất kỳ lỗi cú pháp nào (exit code khác 0), lệnh `sudo systemctl reload nginx` phía sau **sẽ bị chặn lại ngay lập tức và không bao giờ được thực thi**, bảo vệ hệ thống tuyệt đối an toàn 100%!

---

## 4. Kiểm tra thực tế

```bash
# 1. Kiểm tra header nén Gzip của response
curl -H "Accept-Encoding: gzip" -I http://domain.com/static/js/bundle.js

# Kết quả mong đợi có chứa dòng header:
# Content-Encoding: gzip

# 2. Kiểm tra upload file dung lượng 5MB (lớn hơn 1MB nhưng nhỏ hơn 10MB)
curl -F "file=@large-avatar-5mb.jpg" http://domain.com/api/upload
# Kết quả mong đợi: HTTP 200 OK (không còn bị lỗi 413)
```
