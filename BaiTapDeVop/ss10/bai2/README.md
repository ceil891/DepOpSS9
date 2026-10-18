# Bài 2: Tạo User Deploy Và Cài Đặt Docker (Vận Dụng Cơ Bản)

> **Môn học:** DevOps  
> **Chủ đề:** Linux User Management, Sudoers, Docker Engine Installation, Docker Group Non-root  

---

## 1. Tình huống nghiệp vụ & Lý do thực hiện

* **Rủi ro khi dùng user `root`:**
  * User `root` sở hữu toàn quyền cao nhất trên Linux (Superuser). Mọi sai sót cú pháp (ví dụ: `rm -rf /` thay vì `rm -rf ./`) hoặc các cuộc tấn công chiếm quyền ứng dụng chạy dưới root sẽ dẫn đến thảm họa phá hủy toàn bộ hệ thống hoặc đánh cắp dữ liệu máy chủ.
* **Giải pháp chuẩn:**
  * Tạo riêng một user giới hạn chuyên trách việc triển khai mang tên `deploy`.
  * Cấp quyền `sudo` để user này chỉ thực thi các thao tác nhạy cảm khi có chủ đích.
  * Cài đặt **Docker Engine & Docker Compose Plugin** từ nguồn chính thức của Docker.
  * Đưa user `deploy` vào group `docker` để có thể quản lý container mà không cần gõ `sudo docker`, giảm thiểu rủi ro bảo mật.

---

## 2. Danh sách câu lệnh thực thi từng bước (Manual Walkthrough)

### Bước 1: Đăng nhập vào VPS với quyền Root (hoặc user quản trị ban đầu)

```bash
# Trên máy cá nhân:
ssh ubuntu@<PUBLIC_IP_VPS>
# Hoặc ssh root@<PUBLIC_IP_VPS>

# Nếu đăng nhập bằng ubuntu, chuyển sang root (hoặc dùng sudo):
sudo -i
```

---

### Bước 2: Tạo User `deploy` và cấp quyền Sudo

```bash
# 1. Tạo user 'deploy' (hệ thống sẽ yêu cầu nhập password và thông tin)
adduser deploy

# 2. Cấp quyền sudo cho user 'deploy'
usermod -aG sudo deploy

# 3. Kiểm tra user đã vào group sudo chưa
id deploy
# Output sẽ có: uid=1001(deploy) gid=1001(deploy) groups=1001(deploy),27(sudo)
```

---

### Bước 3: Cài đặt Docker Engine & Docker Compose chính thức

* **Lưu ý quan trọng:** Không nên dùng gói `docker.io` cũ mặc định của Ubuntu mà nên thêm kho lưu trữ chính thức của Docker để nhận bản cập nhật mới nhất và bảo mật nhất.

```bash
# 1. Cập nhật apt package index và cài đặt các công cụ cần thiết
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

# 2. Thêm GPG Key chính thức của Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# 3. Thêm Docker Repository vào APT sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Cài đặt Docker Engine, Containerd, Docker CLI & Docker Compose Plugin
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Đảm bảo Docker daemon đang chạy
systemctl status docker --no-pager
```

---

### Bước 4: Thêm User `deploy` vào Group `docker`

Mặc định, Docker Daemon liên kết với Unix socket `/var/run/docker.sock` thuộc sở hữu của user `root` và group `docker`. Việc gán `deploy` vào group `docker` cho phép user này thao tác với docker socket mà không cần `sudo`:

```bash
# Thêm user deploy vào group docker
usermod -aG docker deploy

# Xác minh lại các nhóm của user deploy
id deploy
# Kết quả mong muốn: groups=...27(sudo),998(docker)
```

---

### Bước 5: Chuyển sang user `deploy` và kiểm tra kết quả

```bash
# Chuyển phiên làm việc sang user deploy
su - deploy

# Kiểm tra phiên bản Docker (không dùng sudo)
docker --version

# Kiểm tra phiên bản Docker Compose (không dùng sudo)
docker compose version

# Chạy thử container kiểm tra quyền giao tiếp với Docker Daemon
docker run hello-world
```

---

## 3. Checklist kết quả mong muốn nộp bài

1. 📄 **File văn bản chứa danh sách lệnh:**
   * File [commands.sh](file:///e:/BaiTapDeVop/ss10/bai2/commands.sh) đã được tạo đầy đủ.

2. 📸 **Ảnh chụp màn hình Terminal:**
   * Hiển thị dòng lệnh chạy dưới quyền user `deploy`:
     ```bash
     deploy@<hostname>:~$ docker --version
     Docker version 27.x.x, build ...
     deploy@<hostname>:~$ docker compose version
     Docker Compose version v2.x.x
     deploy@<hostname>:~$ docker run hello-world
     Hello from Docker!
     ```
   * Lưu ảnh vào: `ss10/bai2/screenshots/docker-version-deploy-user.png`.
