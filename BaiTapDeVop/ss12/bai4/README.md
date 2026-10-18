# Bài tập 4: Tích hợp UFW và Docker (Vận dụng chuyên sâu)

> **Môn học:** DevOps  
> **Chủ đề:** Linux Firewall, UFW vs Docker iptables Bypass, Port Binding Security  
> **Tác giả:** Luu Hung  
> **Repository:** [ceil891/DepOpSS9](https://github.com/ceil891/DepOpSS9)  

---

## 1. Tình huống nghiệp vụ & Lỗ hổng bảo mật nghiêm trọng

* **Bối cảnh:** Quản trị viên hệ thống đã thiết lập tường lửa UFW (Uncomplicated Firewall) trên máy chủ Ubuntu:
  * Cho phép cổng `22` (SSH), cổng `80` (HTTP) và cổng `443` (HTTPS).
  * Chặn tường minh cổng `8080` (`sudo ufw deny 8080/tcp`).
  * Mục tiêu là: Chỉ cho phép người dùng bên ngoài đi qua cổng `80`/`443` của Nginx Reverse Proxy, còn ứng dụng Backend chạy trong Docker ở cổng `8080` phải được giấu kín hoàn toàn.
* **Hiện tượng nguy hiểm:**
  * Kỹ sư triển khai file `docker-compose.yml`:
    ```yaml
    version: '3'
    services:
      backend:
        image: my-spring-boot-app:latest
        ports:
          - "8080:8080"
    ```
  * Mặc dù UFW hiển thị trạng thái đã chặn cổng 8080 (`Status: active, 8080/tcp DENY`), bất kỳ ai từ Internet gõ `http://<PUBLIC_IP_VPS>:8080` vẫn truy cập thẳng vào ứng dụng Spring Boot!
  * **Hậu quả:** Kẻ tấn công có thể bypass toàn bộ tầng bảo mật, rate limiting, authentication và SSL/TLS của Nginx để tấn công trực diện vào API nội bộ của Spring Boot.

---

## 2. Phân tích nguyên nhân gốc rễ: Tại sao Docker Bypass được UFW?

Đây là một trong những đặc tính "tai tiếng" nhất của Docker trên nền tảng Linux: **Docker tự động thao túng iptables và vô hiệu hóa UFW**.

### 2.1. Kiến trúc xử lý gói tin trong Linux Kernel (Netfilter / iptables)
Trong Linux Kernel, các gói tin mạng đi qua các bảng (**tables**) và các chuỗi (**chains**) theo thứ tự nghiêm ngặt:

```
[ Gói tin từ Internet tới cổng 8080 ]
                  │
                  ▼
       [ Table NAT: PREROUTING ] ──> DOCKER chèn rule DNAT tại đây!
                  │                  (Dịch IP đích thành 172.18.0.2:8080 của Container)
                  ▼
       [ Routing Decision ]
                  │
       ┌──────────┴──────────┐
       │ (Gói tin cho Host)  │ (Gói tin chuyển tiếp cho Container)
       ▼                     ▼
[ Table Filter: INPUT ]   [ Table Filter: FORWARD ]
       │                             │
 UFW đặt luật ở ĐÂY!                 ├──> Chuỗi DOCKER-USER
 (UFW DENY 8080)                     └──> Chuỗi DOCKER (Docker chèn luật ACCEPT tại đây!)
       │                                     │
(Bị bỏ qua hoàn toàn!)                       ▼
                                   [ Container Backend ]
```

### 2.2. Chi tiết cơ chế Bypass:
1. **Vị trí của UFW:** Các quy tắc tạo bởi lệnh `sudo ufw deny ...` được UFW đưa vào chuỗi **`INPUT`** của bảng `filter`. Chuỗi `INPUT` chỉ có hiệu lực với các gói tin có địa chỉ IP đích là chính máy chủ chủ (Host OS).
2. **Hành vi của Docker Daemon:**
   * Khi khởi động container với tham số `-p 8080:8080`, Docker tự động thêm quy tắc DNAT (Destination NAT) vào chuỗi **`PREROUTING`** của bảng `nat`.
   * Quy tắc này dịch địa chỉ đích của gói tin từ `<PUBLIC_IP>:8080` thành `<CONTAINER_IP>:8080` (ví dụ `172.18.0.2:8080`).
3. **Phân luồng gói tin:**
   * Sau bước `PREROUTING`, kernel Linux nhận thấy gói tin này không còn thuộc về Host nữa mà thuộc về một mạng con khác (Docker Bridge Network `docker0` / `br-xxxx`).
   * Do đó, gói tin được chuyển hướng sang chuỗi **`FORWARD`**, hoàn toàn **KHÔNG BAO GIỜ ĐI QUA CHUỖI `INPUT`**.
   * Trong chuỗi `FORWARD`, Docker đã tự động đặt quy tắc `ACCEPT` trong chuỗi con `DOCKER`.
   * **Kết luận:** Quy tắc chặn của UFW trong chuỗi `INPUT` hoàn toàn bị phớt lờ, cổng 8080 vẫn mở toang ra thế giới.

---

## 3. Cấu hình `docker-compose.yml` mới đã khắc phục

File đã sửa: [`docker-compose.yml`](file:///e:/BaiTapDeVop/ss12/bai4/docker-compose.yml)

```yaml
version: '3.8'

services:
  backend:
    image: my-spring-boot-app:latest
    container_name: spring_boot_backend
    restart: unless-stopped
    ports:
      # SỬA ĐỔI QUAN TRỌNG:
      # Ràng buộc tường minh vào địa chỉ IP Loopback nội bộ 127.0.0.1
      - "127.0.0.1:8080:8080"
    environment:
      - SPRING_PROFILES_ACTIVE=prod
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
```

### So sánh trực quan (Diff):
```diff
     services:
       backend:
         image: my-spring-boot-app:latest
         ports:
-          - "8080:8080"
+          - "127.0.0.1:8080:8080"
```

---

## 4. Giải thích cách thức Port Mapping `127.0.0.1` ngăn chặn truy cập trái phép

Cú pháp đầy đủ của directive `ports` trong Docker là:
```text
[HOST_IP:]HOST_PORT:CONTAINER_PORT
```

| Cấu hình | Ý nghĩa & Bản chất kết nối mạng | Mức độ an toàn |
| :--- | :--- | :--- |
| `ports: - "8080:8080"` | Mặc định Docker hiểu là `"0.0.0.0:8080:8080"` (và `[::]:8080:8080` trên IPv6). Docker bind socket trên **tất cả các network interface** của máy chủ (bao gồm `eth0` / `ens3` là card mạng internet công cộng). Bất kỳ ai từ Internet cũng vào được. | 🔴 **Cực kỳ nguy hiểm (Lỗ hổng)** |
| `ports: - "127.0.0.1:8080:8080"` | Docker chỉ bind socket vào **duy nhất giao diện mạng cục bộ Loopback (`lo` - 127.0.0.1)**. Quy tắc iptables do Docker tạo ra lúc này chỉ áp dụng cho các gói tin có địa chỉ đích là `127.0.0.1`. | 🟢 **Tuyệt đối an toàn (Best Practice)** |

### Cơ chế hoạt động thực tế:
1. **Truy cập từ bên ngoài Internet (`http://<PUBLIC_IP>:8080`):**
   * Gói tin đi vào máy chủ qua card mạng công cộng (ví dụ `eth0` có IP `203.0.113.10`).
   * Địa chỉ đích của gói tin là `203.0.113.10:8080`, **hoàn toàn không khớp** với rule của Docker (chỉ áp dụng cho `127.0.0.1`).
   * Máy chủ không có tiến trình nào lắng nghe cổng 8080 trên card mạng `eth0` -> Kết nối bị từ chối ngay lập tức (`Connection Refused` hoặc bị UFW chặn ở chuỗi INPUT).
2. **Truy cập từ Nginx Reverse Proxy trên cùng máy chủ:**
   * Nginx cấu hình: `proxy_pass http://localhost:8080;` (hoặc `http://127.0.0.1:8080;`).
   * Nginx nằm trên cùng máy chủ nội bộ nên giao tiếp qua giao diện loopback `lo` (`127.0.0.1`). Kết nối được thiết lập mượt mà và thành công 100%.

---

## 5. Các bước kiểm chứng thực tế trên Server

### Bước 1: Khởi động lại container với cấu hình mới
```bash
docker-compose down
docker-compose up -d
```

### Bước 2: Kiểm tra các cổng đang lắng nghe (Listening Sockets)
Sử dụng lệnh `ss` hoặc `netstat`:
```bash
sudo ss -tulpn | grep 8080
# Hoặc
sudo netstat -tuln | grep 8080
```
* **Khi bị lỗi (chưa fix):**
  ```text
  tcp  LISTEN  0  4096  0.0.0.0:8080  0.0.0.0:*  users:(("docker-proxy",pid=1234,fd=4))
  tcp  LISTEN  0  4096     [::]:8080     [::]:*  users:(("docker-proxy",pid=1239,fd=4))
  ```
  *(0.0.0.0 nghĩa là công khai toàn cầu).*

* **Sau khi đã fix chuẩn (`127.0.0.1`):**
  ```text
  tcp  LISTEN  0  4096  127.0.0.1:8080  0.0.0.0:*  users:(("docker-proxy",pid=5678,fd=4))
  ```
  *(Chỉ lắng nghe duy nhất trên 127.0.0.1).*

### Bước 3: Kiểm chứng kết nối từ bên ngoài vs nội bộ
1. **Từ máy tính cá nhân ở nhà (ngoài Internet):**
   ```bash
   curl -I --connect-timeout 5 http://<PUBLIC_IP_VPS>:8080
   ```
   * **Kết quả:** `curl: (7) Failed to connect to <PUBLIC_IP_VPS> port 8080: Connection refused` (Thành công chặn đứng kẻ lạ!).
2. **Từ terminal của chính VPS (Localhost):**
   ```bash
   curl -I http://127.0.0.1:8080
   ```
   * **Kết quả:** `HTTP/1.1 200 OK` (Nội bộ kết nối hoàn toàn bình thường!).
3. **Từ trình duyệt qua Nginx:**
   * Truy cập `http://example.com` -> Nginx nhận request, proxy vào `127.0.0.1:8080` và trả về trang web chính xác.

---

## 6. Các giải pháp DevOps chuyên nghiệp khác trong thực tế

Ngoài giải pháp bind `127.0.0.1`, trong môi trường doanh nghiệp có 2 giải pháp kiến trúc nâng cao thường được áp dụng:

### Cách 1: Đưa cả Nginx và Backend vào chung Docker Bridge Network (Không publish port ra Host)
Nếu Nginx cũng được chạy dưới dạng Docker container, ta hoàn toàn **không cần mở cổng 8080 ra máy chủ**:
```yaml
version: '3.8'
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    networks:
      - internal-net

  backend:
    image: my-spring-boot-app:latest
    # Không dùng "ports:", chỉ dùng "expose:" cho mạng nội bộ docker
    expose:
      - "8080"
    networks:
      - internal-net

networks:
  internal-net:
    driver: bridge
```
Trong cấu hình Nginx, trỏ trực tiếp bằng tên service: `proxy_pass http://backend:8080;`. Cổng 8080 hoàn toàn không tồn tại trên Host OS!

### Cách 2: Sử dụng công cụ `ufw-docker`
Docker cung cấp chuỗi `DOCKER-USER` để người dùng chèn luật tùy chỉnh trước khi Docker xử lý. Bạn có thể cài đặt tiện ích `ufw-docker` (một tiện ích mã nguồn mở phổ biến) để đồng bộ toàn bộ quy tắc UFW vào chuỗi `DOCKER-USER`, giải quyết triệt để vấn đề Docker bypass UFW trên toàn server.
