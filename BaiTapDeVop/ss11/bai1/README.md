# Bài 1: Cấu hình Nginx Reverse Proxy Cơ Bản

> **Môn học:** DevOps  
> **Chủ đề:** Nginx Reverse Proxy, Port Forwarding, Xử lý mã lỗi HTTP Gateway  

---

## 1. Tình huống nghiệp vụ & Mục tiêu

* **Tình huống:** Ứng dụng E-commerce Frontend (React) đang chạy ở Port `3000` trên VPS (`localhost:3000`). Trải nghiệm người dùng sẽ rất tệ nếu bắt họ gõ `http://domain.com:3000`. Cần ẩn cổng `3000` và cho phép truy cập qua cổng mặc định `80` bằng địa chỉ `http://domain.com`.
* **Mục tiêu:**
  * Hiểu rõ cơ chế hoạt động của **Reverse Proxy**.
  * Cấu hình Nginx nhận request tại Port `80` và chuyển tiếp ngầm (proxy) sang Port `3000`.
  * Hiểu sâu chỉ thị `proxy_pass` và các header đi kèm.
  * Nhận diện và giải thích bản chất mã lỗi HTTP trả về khi ứng dụng React phía sau bị sập.

---

## 2. File cấu hình Nginx chuẩn xác

File đặt tại: `/etc/nginx/sites-available/default` (kích hoạt bằng symlink tới `/etc/nginx/sites-enabled/default`).

```nginx
server {
    # 1. Lắng nghe trên cổng 80 (cổng HTTP tiêu chuẩn)
    listen 80 default_server;
    listen [::]:80 default_server;

    # 2. Tên miền truy cập (thay thế bằng domain thật hoặc IP của máy chủ)
    server_name domain.com www.domain.com;

    # 3. Chuyển tiếp toàn bộ request tới ứng dụng React
    location / {
        # Chỉ thị chuyển tiếp request tới port nội bộ 3000
        proxy_pass http://127.0.0.1:3000;

        # Bảo toàn thông tin định danh của client và domain
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Hỗ trợ WebSockets (Cần thiết cho React Hot Module Replacement / Socket.io)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Thiết lập thời gian timeout
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Trang báo lỗi tùy chỉnh (tùy chọn)
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
```

---

## 3. Giải thích ý nghĩa của chỉ thị `proxy_pass`

* **`proxy_pass` là gì?**  
  Là directive cốt lõi thuộc module `ngx_http_proxy_module` của Nginx. Nó thiết lập giao thức (`http://` hoặc `https://`), địa chỉ máy chủ nội bộ (IP hoặc domain) và cổng dịch vụ (port) mà Nginx sẽ chuyển tiếp request của client tới.

* **Cơ chế hoạt động:**
  1. **Tiếp nhận:** Nginx nhận HTTP Request từ trình duyệt người dùng tại cổng công khai `80`.
  2. **Tái đóng gói:** Nginx phân tích request, gắn thêm các header bổ sung (`Host`, `X-Real-IP`,...) và tạo một kết nối mạng mới từ Nginx đến ứng dụng React tại `http://127.0.0.1:3000`.
  3. **Truyền nhận dữ liệu:** Ứng dụng React xử lý logic và trả về HTTP Response cho Nginx.
  4. **Phản hồi:** Nginx nhận response đó và chuyển tiếp trở lại cho trình duyệt của người dùng.

* **Lợi ích kiến trúc:**
  * **Che giấu hạ tầng (Information Hiding):** Người dùng bên ngoài chỉ nhìn thấy Nginx ở cổng 80, hoàn toàn không biết ứng dụng thực chất đang chạy bằng React, Node.js trên cổng 3000 nội bộ.
  * **Bảo mật:** Không cần mở Port 3000 trên tường lửa (Firewall/UFW), giảm thiểu bề mặt tấn công (attack surface).
  * **Dễ dàng mở rộng:** Nginx trở thành điểm tập trung để cấu hình SSL/TLS (HTTPS), Caching, Load Balancing, Rate Limiting mà không cần can thiệp vào mã nguồn React.

---

## 4. Phân tích câu hỏi bẫy: Khi React App ở port 3000 bị sập, Nginx trả về lỗi HTTP Code nào?

### 👉 Đáp án: **`502 Bad Gateway`**

### 🔍 Giải thích chi tiết cơ chế hoạt động:
1. **Nginx đóng vai trò là một "Gateway" (Cổng trung gian / Reverse Proxy):**
   - Khi client gửi request tới port 80, tiến trình Nginx vẫn đang hoạt động khỏe mạnh và sẵn sàng tiếp nhận kết nối.
2. **Nỗ lực kết nối tới Upstream Server:**
   - Theo cấu hình `proxy_pass http://127.0.0.1:3000;`, Nginx cố gắng mở kết nối mạng TCP (thực hiện cú bắt tay 3 bước TCP Handshake) tới địa chỉ `127.0.0.1` trên cổng `3000`.
3. **Ứng dụng React bị sập (Crash / Terminated):**
   - Do ứng dụng React đã ngừng hoạt động, không có bất kỳ tiến trình nào (process) đang lắng nghe (listen) trên port 3000.
   - Hệ điều hành (Linux Kernel Network Stack) ngay lập tức phản hồi lại cho Nginx gói tin TCP với cờ **`RST` (Connection Refused)** hoặc trả về mã lỗi hệ thống Linux `111: Connection refused`.
4. **Phát sinh lỗi 502:**
   - Nginx không nhận được kết nối hợp lệ hoặc nhận phản hồi bất thường từ server cấp trên (upstream server).
   - Nginx nhận định "cổng phía sau (gateway) có vấn đề / hỏng" và tự động sinh ra mã lỗi HTTP **`502 Bad Gateway`** gửi ngược về cho người dùng.

### 📌 Phân biệt để không bị nhầm lẫn trong phỏng vấn DevOps:
| Mã lỗi | Tên gọi | Nguyên nhân thực tế |
|---|---|---|
| **`502 Bad Gateway`** | Cổng giao tiếp hỏng | Upstream server **bị tắt/sập**, từ chối kết nối (`Connection refused`), hoặc gửi response rác. |
| **`504 Gateway Timeout`** | Hết thời gian chờ cổng | Upstream server **vẫn đang chạy** nhưng bị treo/nghẽn, xử lý quá lâu vượt quá thời gian `proxy_read_timeout` (mặc định 60s). |
| **`500 Internal Server Error`** | Lỗi nội bộ máy chủ | File cấu hình Nginx bị lỗi directive, hoặc chính ứng dụng React trả về mã 500 do bug code. |
| **`503 Service Unavailable`** | Dịch vụ tạm ngưng | Nginx bị quá tải kết nối (`limit_conn`), hoặc cố tình trả về để bảo trì hệ thống. |

---

## 5. Hướng dẫn triển khai và kiểm tra thực tế trên Linux VPS

```bash
# 1. Đưa file cấu hình vào thư mục của Nginx
sudo cp default /etc/nginx/sites-available/default

# 2. Tạo symlink sang sites-enabled (nếu chưa có)
sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

# 3. Kiểm tra cú pháp cấu hình Nginx
sudo nginx -t

# 4. Reload Nginx để áp dụng cấu hình
sudo systemctl reload nginx

# 5. Kiểm thử khi ứng dụng React đang chạy (Mong đợi: HTTP 200)
curl -I http://localhost

# 6. Kiểm thử câu hỏi bẫy: Dừng ứng dụng React và gửi request lại (Mong đợi: HTTP 502)
# curl -I http://localhost
# HTTP/1.1 502 Bad Gateway
# Server: nginx
```
