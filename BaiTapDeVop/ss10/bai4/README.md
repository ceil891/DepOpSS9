# Bài 4: Cấu Hình Firewall UFW (Vận Dụng Chuyên Sâu)

> **Môn học:** DevOps  
> **Chủ đề:** Linux Firewall, Uncomplicated Firewall (UFW), Port Security, Docker Networking & Firewall Bypass  

---

## 1. Tình huống nghiệp vụ & Nguyên lý Firewall

* **Tình huống nghiệp vụ:**
  * Mặc định nhiều máy chủ VPS có thể mở tất cả cổng hoặc chưa được kích hoạt tường lửa nội bộ (Host-based Firewall). Nếu kẻ tấn công phát hiện một ứng dụng nội bộ hoặc cơ sở dữ liệu (vd: Redis không đặt mật khẩu, MySQL cổng 3306, MongoDB 27017) đang mở ra ngoài, chúng có thể xâm nhập ngay lập tức.
* **Nguyên lý Least Privilege trong quản trị mạng:**
  * **Default Deny Incoming:** Chặn toàn bộ kết nối đi vào máy chủ trừ khi được cho phép tường minh.
  * **Default Allow Outgoing:** Cho phép máy chủ gửi request ra ngoài (tải gói tin, gọi API thứ ba).
  * **Chỉ mở các Port dịch vụ công khai:** Trong bài này là **Port 22 (SSH)** để quản trị và **Port 8080 (Web App)** để người dùng truy cập. Tất cả các port khác (ví dụ 8081) phải bị chặn triệt để.

---

## 2. Các bước triển khai thực hành từng bước

### Bước 1: Thiết lập chính sách mặc định (Default Policies)

Đăng nhập vào VPS với quyền `sudo`:

```bash
# 1. Chặn toàn bộ lưu lượng truy cập từ ngoài vào máy chủ
sudo ufw default deny incoming

# 2. Cho phép toàn bộ lưu lượng đi ra từ máy chủ
sudo ufw default allow outgoing
```

---

### Bước 2: Mở Port 22 (SSH) và Port 8080 (Web App)

> ⚠️ **CẢNH BÁO QUAN TRỌNG NHẤT:**
> Bạn **BẮT BUỘC** phải chạy lệnh mở cổng 22 (`sudo ufw allow 22/tcp`) **TRƯỚC KHI** chạy lệnh bật UFW (`sudo ufw enable`). Nếu bật UFW trước khi mở SSH, bạn sẽ bị ngắt kết nối và bị khóa khỏi máy chủ ngay lập tức!

```bash
# Cho phép kết nối SSH (Port 22/tcp)
sudo ufw allow 22/tcp comment 'Allow SSH Management'

# Cho phép ứng dụng Web chạy trên Port 8080/tcp
sudo ufw allow 8080/tcp comment 'Allow Staging Web App'

# (Tùy chọn) Khai báo rõ ràng cấm port 8081
sudo ufw deny 8081/tcp comment 'Block Port 8081'
```

---

### Bước 3: Kích hoạt Tường lửa UFW

```bash
# Bật UFW
sudo ufw enable
```

* Hệ thống sẽ hiển thị cảnh báo:
  ```text
  Command may disrupt existing ssh connections. Proceed with operation (y|n)?
  ```
* Nhấn `y` rồi nhấn **Enter**. Do chúng ta đã mở Port 22 ở Bước 2, kết nối SSH sẽ được duy trì bình thường.

---

### Bước 4: Kiểm tra trạng thái Firewall chi tiết

```bash
sudo ufw status verbose
```

* **Kết quả hiển thị mong muốn:**
  ```text
  Status: active
  Logging: on (low)
  Default: deny (incoming), allow (outgoing), disabled (routed)
  New profiles: skip

  To                         Action      From
  --                         ------      ----
  22/tcp                     ALLOW IN    Anywhere                   # Allow SSH Management
  8080/tcp                   ALLOW IN    Anywhere                   # Allow Staging Web App
  8081/tcp                   DENY IN     Anywhere                   # Block Port 8081
  22/tcp (v6)                ALLOW IN    Anywhere (v6)              # Allow SSH Management
  8080/tcp (v6)              ALLOW IN    Anywhere (v6)              # Allow Staging Web App
  8081/tcp (v6)              DENY IN     Anywhere (v6)              # Block Port 8081
  ```

---

### Bước 5: Chạy thử nghiệm 2 Nginx Container đối chứng (Port 8080 vs Port 8081)

Chạy 2 container Nginx trên 2 cổng khác nhau:

```bash
# Container 1 chạy tại port 8080 (cổng được phép qua Firewall)
docker run -d --name nginx-8080 -p 8080:80 nginx:alpine

# Container 2 chạy tại port 8081 (cổng bị Firewall chặn)
docker run -d --name nginx-8081 -p 8081:80 nginx:alpine

# Kiểm tra danh sách container đang chạy
docker ps
```

---

### 💡 Lưu ý chuyên sâu DevOps: Hiện tượng "Docker Bypass UFW" & Cách giải quyết

> **Vấn đề thực tế trong Production:**
> Mặc định, khi bạn chạy Docker với cờ `-p <host_port>:<container_port>`, Docker Daemon sẽ tự động chèn các quy tắc `iptables` vào chuỗi `PREROUTING` và `DOCKER` trước khi các gói tin đi qua chuỗi lọc của UFW. Điều này có thể khiến port `8081` vẫn truy cập được từ bên ngoài dù UFW đã chặn!

**Các giải pháp chuẩn chỉnh:**
1. **Giải pháp 1 (Khuyến nghị chuẩn Production):** Cấu hình thêm rule forward cho UFW chặn port ở mức định tuyến:
   ```bash
   sudo ufw route deny proto tcp to any port 8081
   sudo ufw reload
   ```
2. **Giải pháp 2:** Dùng tiện ích `ufw-docker` (dự án mã nguồn mở phổ biến của cộng đồng) để đồng bộ hóa iptables Docker với UFW:
   ```bash
   sudo wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
   sudo chmod +x /usr/local/bin/ufw-docker
   sudo ufw-docker install
   sudo ufw-docker allow nginx-8080 80
   # Không cấp phép cho nginx-8081
   sudo ufw reload
   ```
3. **Giải pháp 3 (Kiểm tra Cloud Security Group):** Nếu trên Cloud (AWS/GCP), đảm bảo Security Group chỉ mở inbound port `22` và `8080`, tuyệt đối không mở `8081`.

---

### Bước 6: Kiểm tra kết quả từ máy cá nhân

Trên **máy tính cá nhân** (mở trình duyệt hoặc PowerShell):

1. **Kiểm tra Port 8080 (Thành công):**
   * Bằng trình duyệt: Truy cập `http://<PUBLIC_IP_VPS>:8080`  
     👉 **Kết quả:** Hiển thị trang chào mừng **"Welcome to nginx!"**.
   * Bằng lệnh PowerShell / curl:
     ```powershell
     curl.exe -I http://<PUBLIC_IP_VPS>:8080
     ```
     👉 **Kết quả:** Trả về `HTTP/1.1 200 OK`.

2. **Kiểm tra Port 8081 (Thất bại / Bị chặn):**
   * Bằng trình duyệt: Truy cập `http://<PUBLIC_IP_VPS>:8081`  
     👉 **Kết quả:** Trình duyệt quay chờ và báo lỗi **"This site can’t be reached" (ERR_CONNECTION_TIMED_OUT)**.
   * Bằng lệnh PowerShell / curl:
     ```powershell
     curl.exe --connect-timeout 5 http://<PUBLIC_IP_VPS>:8081
     ```
     👉 **Kết quả:** Báo lỗi `Connection timed out` hoặc `Failed to connect`.

---

## 3. Checklist kết quả mong muốn nộp bài

1. 📄 **Script cài đặt:**
   * Script tự động hóa: [setup-ufw.sh](file:///e:/BaiTapDeVop/ss10/bai4/setup-ufw.sh).
2. 📸 **Ảnh chụp màn hình Terminal:**
   * Lệnh `sudo ufw status verbose` hiển thị rõ trạng thái `Status: active` và danh sách Port 22 ALLOW, Port 8080 ALLOW.
   * Lưu ảnh vào: `ss10/bai4/screenshots/ufw-status-verbose.png`.
3. 📸 **Ảnh chụp màn hình Trình duyệt / Curl:**
   * Ảnh 1: Truy cập thành công cổng 8080 (ra trang Nginx Welcome).
   * Ảnh 2: Truy cập thất bại ở cổng 8081 (quay vòng rồi báo Timeout).
   * Lưu ảnh vào: `ss10/bai4/screenshots/port-8080-success-and-8081-failed.png`.
