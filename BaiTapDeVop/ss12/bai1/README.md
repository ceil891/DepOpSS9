# Bài tập 1: Xử lý sự cố sập Nginx (Vận dụng cơ bản)

> **Môn học:** DevOps  
> **Chủ đề:** Nginx Troubleshooting, Syntax Parsing Error, Zero-Downtime Reload  
> **Tác giả:** Luu Hung  
> **Repository:** [ceil891/DepOpSS9](https://github.com/ceil891/DepOpSS9)  

---

## 1. Tình huống nghiệp vụ & Thông báo lỗi

* **Tình huống:** Đội ngũ phát triển vừa cập nhật cấu hình mới cho server block của ứng dụng web tại file `/etc/nginx/sites-enabled/app.conf`. Tuy nhiên, khi thực hiện nạp lại cấu hình, Nginx báo lỗi cú pháp và dịch vụ không thể khởi động lại, đe dọa trực tiếp đến tính liên tục của hệ thống (downtime).

* **Đoạn cấu hình ban đầu:**
  ```nginx
  server {
      listen 80;
      server_name example.com;

      location / {
          proxy_pass http://localhost:8080
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
      }
  }
  ```

* **Thông báo lỗi từ hệ thống:**
  ```text
  nginx: [emerg] unexpected "proxy_set_header" in /etc/nginx/sites-enabled/app.conf:7
  ```

---

## 2. Phân tích nguyên nhân gốc rễ (Root Cause Analysis)

### 2.1. Tại sao Nginx lại báo lỗi ở dòng 7 thay vì dòng 6?
* **Quy tắc phân tích cú pháp của Nginx (Lexer / Parser):**
  * Trong Nginx, mỗi chỉ thị (directive) bắt buộc phải kết thúc bằng dấu chấm phẩy (`;`). Dấu chấm phẩy đóng vai trò là ký tự kết thúc chỉ thị (statement terminator).
  * Chỉ thị `proxy_pass` có cú pháp chuẩn:
    ```nginx
    proxy_pass URL;
    ```
    Nó chỉ chấp nhận **một tham số duy nhất** là URL đích của Upstream server.
* **Cơ chế phát sinh lỗi:**
  * Tại **dòng 6**: `proxy_pass http://localhost:8080` bị **thiếu dấu chấm phẩy `;`**.
  * Khi bộ phân tích cú pháp (parser) của Nginx duyệt qua dòng 6, do không thấy ký tự `;`, nó tiếp tục đọc sang dòng tiếp theo (dòng 7) và hiểu rằng từ khóa `proxy_set_header` là **tham số thứ hai** của chỉ thị `proxy_pass`.
  * Do `proxy_pass` không chấp nhận tham số thứ hai, parser ngay lập tức dừng lại và ném ra lỗi cú pháp ở mức khẩn cấp:
    `[emerg] unexpected "proxy_set_header" in /etc/nginx/sites-enabled/app.conf:7`.
  * **Kết luận:** Lỗi hiển thị ở dòng 7 (`proxy_set_header`), nhưng nguyên nhân thực sự nằm ở **cuối dòng 6** (thiếu dấu `;` sau `http://localhost:8080`).

---

## 3. Đoạn cấu hình đã khắc phục

File đã sửa: [`app.conf`](file:///e:/BaiTapDeVop/ss12/bai1/app.conf)

```nginx
server {
    listen 80;
    server_name example.com;

    location / {
        # Đã khắc phục: Bổ sung dấu chấm phẩy (;) kết thúc chỉ thị proxy_pass
        proxy_pass http://localhost:8080;
        
        # Thiết lập các HTTP headers cần thiết cho Reverse Proxy
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### So sánh trực quan (Diff):
```diff
     location / {
-        proxy_pass http://localhost:8080
+        proxy_pass http://localhost:8080;
         proxy_set_header Host $host;
         proxy_set_header X-Real-IP $remote_addr;
     }
```

---

## 4. Quy trình kiểm tra cú pháp và kích hoạt dịch vụ

Trong môi trường Production, tuyệt đối không được khởi động lại dịch vụ ngay sau khi chỉnh sửa file cấu hình. Cần tuân thủ nghiêm ngặt quy trình chuẩn DevOps:

### Bước 1: Kiểm tra tính hợp lệ của cấu hình (Pre-flight Check)
Chạy lệnh kiểm tra cú pháp trước khi nạp vào tiến trình đang chạy:
```bash
sudo nginx -t
```
* **Khi cấu hình còn lỗi:**
  ```text
  nginx: [emerg] unexpected "proxy_set_header" in /etc/nginx/sites-enabled/app.conf:7
  nginx: configuration file /etc/nginx/nginx.conf test failed
  ```
* **Khi cấu hình đã được sửa đúng:**
  ```text
  nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
  nginx: configuration file /etc/nginx/nginx.conf test is successful
  ```
  > **Mã thoát (Exit Code):** Lệnh `nginx -t` trả về `0` nếu cấu hình hợp lệ và khác `0` nếu có lỗi. Điều này rất quan trọng khi viết script CI/CD Automation (`nginx -t && sudo systemctl reload nginx`).

---

### Bước 2: Nạp lại cấu hình không gây gián đoạn dịch vụ (Zero-Downtime Reload)
Sau khi `nginx -t` trả về kết quả thành công, thực hiện reload:
```bash
# Cách 1: Sử dụng systemd (Khuyến nghị trên Ubuntu/Debian/CentOS)
sudo systemctl reload nginx

# Cách 2: Gửi tín hiệu trực tiếp tới Master Process của Nginx
sudo nginx -s reload
```

---

### Bước 3: Khởi động lại dịch vụ (Chỉ dùng khi Nginx đã bị dừng hoàn toàn)
Nếu dịch vụ Nginx đã bị stop từ trước do cố tình restart khi file config còn lỗi:
```bash
sudo systemctl start nginx
# Hoặc
sudo systemctl restart nginx
```

Kiểm tra trạng thái hoạt động:
```bash
sudo systemctl status nginx
```

---

## 5. So sánh sống còn: `reload` vs `restart`

| Tiêu chí | `sudo systemctl reload nginx` | `sudo systemctl restart nginx` |
| :--- | :--- | :--- |
| **Cơ chế hoạt động** | Gửi tín hiệu `SIGHUP` tới Master process. Master kiểm tra config, sinh worker mới với config mới, sau đó gracefully shutdown các worker cũ sau khi chúng phục vụ xong request hiện tại. | Tắt toàn bộ tiến trình Nginx (`SIGTERM`/`SIGQUIT`), sau đó khởi động lại tiến trình từ đầu. |
| **Tác động đến Client** | **Không gián đoạn (Zero-Downtime).** Các kết nối đang truyền tải dữ liệu tiếp tục hoàn tất bình thường. | **Ngắt kết nối tức thì (Dropped Connections).** Client đang upload/download hoặc gửi API sẽ bị đứt kết nối (Lỗi `Connection Reset`). |
| **Xử lý khi config bị lỗi** | Master process từ chối cấu hình lỗi, ghi log cảnh báo và **tiếp tục chạy bình thường** với cấu hình cũ. Hệ thống **không bị sập**. | Nginx tắt dịch vụ cũ, cố gắng khởi động dịch vụ mới nhưng gặp lỗi cú pháp -> **Dịch vụ chết hoàn toàn (Down hệ thống)**. |
| **Ứng dụng thực tế** | Dùng cho 99% các trường hợp cập nhật domain, upstream, reverse proxy, SSL certs. | Chỉ dùng khi nâng cấp binary Nginx, thay đổi cấu hình lõi hệ thống cấp thấp hoặc khi Nginx bị treo socket. |

---

## 6. Bài học kinh nghiệm & Best Practice cho DevOps

1. **Nguyên tắc "Pre-flight Check First":**  
   Luôn luôn chạy `nginx -t` trước khi thực hiện bất kỳ lệnh nạp lại nào. Trong các pipeline CI/CD (GitHub Actions, GitLab CI, Ansible), lệnh triển khai luôn phải có cấu trúc:
   ```bash
   ssh deploy@vps "sudo nginx -t && sudo systemctl reload nginx"
   ```
2. **Quản lý cấu hình qua `sites-available` và `sites-enabled`:**  
   Chỉnh sửa file tại `/etc/nginx/sites-available/app.conf`, sau đó tạo symbolic link sang `/etc/nginx/sites-enabled/`:
   ```bash
   sudo ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/
   ```
   Nếu có sự cố, ta chỉ cần xóa symlink trong `sites-enabled/` mà không làm mất file cấu hình gốc.
