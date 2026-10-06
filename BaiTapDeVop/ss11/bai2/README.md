# Bài 2: Định tuyến Request đến API Gateway (Path-based Routing)

> **Môn học:** DevOps  
> **Chủ đề:** Nginx Path-based Routing, Proxy Headers, X-Forwarded-For Analysis  

---

## 1. Tình huống nghiệp vụ & Mục tiêu

* **Tình huống:** Hệ thống E-commerce gồm 2 dịch vụ nội bộ chạy trên cùng một VPS:
  * **Frontend (React):** Lắng nghe tại `localhost:3000`.
  * **Backend API Gateway:** Lắng nghe tại `localhost:8080`.
  * Yêu cầu phục vụ cả hai dịch vụ trên cùng 1 domain duy nhất tại cổng `80` (HTTP).
* **Mục tiêu:**
  * Cấu hình Nginx thực hiện định tuyến dựa trên đường dẫn URL (**Path-based routing**):
    * Mọi request có tiền tố `/api/` (ví dụ `/api/v1/auth`, `/api/products`) được định tuyến tới Backend Gateway (`localhost:8080`).
    * Các request còn lại (ví dụ `/`, `/about`, `/checkout`) được định tuyến tới Frontend React (`localhost:3000`).
  * Giữ nguyên các Header nhận diện (`Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`).
  * Giải thích chi tiết câu hỏi bẫy về việc nếu không truyền `X-Forwarded-For`, Backend sẽ nhận IP của ai và hậu quả ra sao.

---

## 2. File cấu hình Nginx chi tiết

File đặt tại: `/etc/nginx/sites-available/default`

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name my-ecommerce.com www.my-ecommerce.com;

    # 1. Định tuyến các API Request sang Backend API Gateway (Port 8080)
    location /api/ {
        proxy_pass http://127.0.0.1:8080;

        # Thiết lập các Header nhận diện quan trọng
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_http_version 1.1;
    }

    # 2. Định tuyến các Request còn lại sang Frontend React (Port 3000)
    location / {
        proxy_pass http://127.0.0.1:3000;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Hỗ trợ WebSockets (HMR cho React / Realtime messaging)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

---

## 3. Kiến thức chuyên sâu: Phân tích đường dẫn và dấu gạch chéo (`/`) trong `proxy_pass`

Một trong những vấn đề hay gặp lỗi nhất khi cấu hình Nginx Path-based routing là việc có hay không có dấu gạch chéo (`/`) ở đuôi URL upstream:

| Cấu hình `proxy_pass` | Request từ Client | URL thực tế Backend nhận được | Mục đích sử dụng |
|---|---|---|---|
| `proxy_pass http://127.0.0.1:8080;` *(Không có `/`)* | `GET /api/products` | `GET /api/products` | Khi Backend API Gateway được thiết kế có sẵn tiền tố `/api` trong route controller. |
| `proxy_pass http://127.0.0.1:8080/;` *(Có `/` ở cuối)* | `GET /api/products` | `GET /products` | Khi Backend Gateway chỉ xử lý route gốc `/products` (Nginx tự động cắt bỏ prefix `/api/`). |

---

## 4. Phân tích câu hỏi bẫy: Tại sao phải truyền Header `X-Forwarded-For`? Nếu không truyền, Backend sẽ thấy IP của ai?

### 👉 Đáp án trực diện:
Nếu **KHÔNG truyền** header `X-Forwarded-For` (hoặc `X-Real-IP`), Backend sẽ chỉ nhìn thấy địa chỉ IP của **chính Nginx** — cụ thể là **`127.0.0.1`** (IP Loopback nội bộ) hoặc IP card mạng nội bộ của máy chủ Nginx.

---

### 🔍 Giải thích bản chất kỹ thuật:
1. **Kiến trúc phân tách kết nối TCP:**
   * Trình duyệt của Client kết nối mạng tới Nginx. Tại đây, Nginx ghi nhận socket TCP từ Client (`$remote_addr` = IP thực của client, ví dụ `14.161.x.x`).
   * Khi Nginx thực hiện `proxy_pass`, Nginx khởi tạo một kết nối mạng TCP **hoàn toàn mới** từ chính nó tới cổng `8080` của Backend.
   * Ở tầng Network Socket của Backend, địa chỉ IP nguồn (Source IP) của gói tin TCP truyền đến chính là Nginx (`127.0.0.1`).
2. **Nếu Backend gọi hàm lấy IP thông thường:**
   * Trong Java/Spring Boot: `request.getRemoteAddr()` -> Trả về `127.0.0.1`.
   * Trong Node.js/Express: `req.socket.remoteAddress` -> Trả về `127.0.0.1`.
   * Trong Python/Flask/Django: `request.META['REMOTE_ADDR']` -> Trả về `127.0.0.1`.

---

### ⚠️ Hậu quả chí mạng nếu không truyền `X-Forwarded-For` trên Production:

1. **Vỡ cơ chế Giới hạn tần suất (Rate Limiting) & Chống Brute-Force:**
   * Giả sử Backend cấu hình giới hạn 100 requests/phút trên mỗi IP để chống spam và tấn công vét cạn mật khẩu.
   * Nếu tất cả khách hàng truy cập đều có IP là `127.0.0.1`, chỉ cần 1 khách hàng hoặc kẻ tấn công gửi vượt quá 100 request, Backend sẽ **khóa luôn IP `127.0.0.1`**!
   * **Hậu quả:** Toàn bộ người dùng trên khắp thế giới bị chặn truy cập đồng loạt!
2. **Hỏng tính năng Giám sát & Phát hiện gian lận (Fraud Detection / Geo-IP):**
   * Hệ thống thanh toán E-commerce cần kiểm tra vị trí địa lý của người dùng (GeoIP) để phát hiện giao dịch bất thường từ quốc gia khác.
   * Tất cả IP đều là `127.0.0.1` (Localhost) khiến hệ thống bảo mật không thể phân tích và bỏ lọt gian lận.
3. **Mất dấu vết kiểm toán (Audit Trail & Logging):**
   * Khi xảy ra sự cố bảo mật (SQL Injection, rò rỉ dữ liệu), bảng log truy vết của database và server chỉ lưu toàn bộ `127.0.0.1`. Đội ngũ an ninh mạng hoàn toàn không thể xác định được IP của tin tặc.
4. **Vô hiệu hóa Blacklist / Whitelist IP:**
   * Không thể chặn các IP có hành vi tấn công (Blacklist), cũng không thể thiết lập quyền ưu tiên cho IP quản trị nội bộ (Whitelist).

---

### 💡 Ý nghĩa của biến `$proxy_add_x_forwarded_for`:
* `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`
* Biến này tự động kiểm tra xem request gửi đến từ client đã có header `X-Forwarded-For` hay chưa (ví dụ client đi qua CDN Cloudflare). Nếu đã có, nó sẽ giữ nguyên chuỗi cũ và nối thêm IP `$remote_addr` vào cuối theo định dạng chuẩn:
  ```http
  X-Forwarded-For: <client-ip>, <proxy1-ip>, <proxy2-ip>
  ```
  Nhờ đó, Backend có thể duyệt qua toàn bộ chuỗi để lấy ra IP thực sự của người dùng đầu cuối.

---

## 5. Hướng dẫn kiểm thử

```bash
# 1. Kiểm tra cú pháp file cấu hình
sudo nginx -t

# 2. Reload Nginx
sudo systemctl reload nginx

# 3. Test định tuyến Frontend (Port 3000)
curl -I http://localhost/
# Trả về trang React

# 4. Test định tuyến Backend (Port 8080)
curl -I http://localhost/api/health
# Trả về kết quả từ Backend API Gateway
```
