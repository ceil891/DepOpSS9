# SS10 - Quản Trị Linux Server, Cài Đặt Docker & Bảo Mật VPS

> **Môn học:** DevOps  
> **Chủ đề:** Khởi tạo VPS Ubuntu, Quản trị User Linux, Cài đặt Docker/Docker Compose, Hardening SSH & Cấu hình UFW Firewall  
> **Tác giả:** Luu Hung  
> **Repository:** [ceil891/DepOpSS9](https://github.com/ceil891/DepOpSS9)  

---

## 📁 Cấu trúc thư mục SS10

```
ss10/
├── README.md                                  # Tài liệu tổng hợp toàn bộ 4 bài tập SS10
│
├── bai1/                                      # Bài 1: Khởi tạo và kết nối VPS
│   └── README.md                              # Hướng dẫn tạo VPS, cấu hình Security Group, kết nối SSH
│
├── bai2/                                      # Bài 2: Tạo User Deploy và Cài đặt Docker
│   ├── commands.sh                            # Script các lệnh Linux thực thi tạo user & cài Docker
│   └── README.md                              # Hướng dẫn chi tiết, phân quyền sudo & docker group
│
├── bai3/                                      # Bài 3: Tăng cường bảo mật SSH
│   ├── setup-ssh-security.sh                  # Script cấu hình SSH Hardening (disable root, key-only)
│   └── README.md                              # Tạo SSH key Ed25519, cấu hình sshd_config & checklist test
│
└── bai4/                                      # Bài 4: Cấu hình Firewall UFW
    ├── setup-ufw.sh                           # Script thiết lập luật Firewall UFW (Port 22, 8080)
    └── README.md                              # Hướng dẫn UFW, xử lý Docker iptables bypass, test Nginx
```

---

## 📑 Tóm tắt nội dung & Đáp án từng bài tập

### 🔹 Bài 1: Khởi tạo và kết nối VPS (Vận dụng cơ bản)
* **Nền tảng Cloud đề xuất:** AWS EC2 (t2.micro - Free Tier), Google Cloud (e2-micro), Oracle Cloud (Free Tier) hoặc DigitalOcean ($200 credit) / Máy ảo Ubuntu 22.04 LTS (Multipass/VirtualBox/WSL2).
* **Hệ điều hành:** Ubuntu 22.04 LTS x86_64.
* **Cấu hình mạng:** Inbound cho phép cổng 22 (SSH) từ `0.0.0.0/0` hoặc `My IP`.
* **Lệnh kết nối từ Terminal / PowerShell:**
  ```bash
  ssh -i path/to/private-key.pem ubuntu@<PUBLIC_IP_VPS>
  # Hoặc nếu dùng mật khẩu:
  ssh root@<PUBLIC_IP_VPS>
  ```
* **Minh chứng nộp bài:**
  1. Ảnh chụp Dashboard Cloud hiển thị thông tin Instance: Name, Status (Running), Public IPv4, OS (Ubuntu 22.04), Instance Type.
  2. Ảnh chụp Terminal/PowerShell kết nối SSH thành công vào VPS (có banner Ubuntu và prompt `ubuntu@vps:~$` hoặc `root@vps:~#`).

---

### 🔹 Bài 2: Tạo User Deploy và Cài đặt Docker (Vận dụng cơ bản)
* **Mục tiêu an toàn:** Không bao giờ dùng tài khoản `root` trực tiếp để vận hành dịch vụ nhằm hạn chế rủi ro phá hủy hệ thống hoặc bị tấn công leo thang đặc quyền.
* **Các bước triển khai chính:**
  1. **Tạo user `deploy`:**
     ```bash
     sudo adduser deploy
     ```
  2. **Cấp đặc quyền `sudo`:**
     ```bash
     sudo usermod -aG sudo deploy
     ```
  3. **Cài đặt Docker Engine & Docker Compose (Plugin) chính thức từ Docker Repo:**
     ```bash
     sudo apt-get update
     sudo apt-get install -y ca-certificates curl gnupg
     sudo install -m 0755 -d /etc/apt/keyrings
     sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
     sudo chmod a+r /etc/apt/keyrings/docker.asc

     echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

     sudo apt-get update
     sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
     ```
  4. **Gán user `deploy` vào group `docker`:**
     ```bash
     sudo usermod -aG docker deploy
     ```
  5. **Kiểm tra quyền chạy Docker dưới user `deploy`:**
     ```bash
     su - deploy
     docker --version
     docker compose version
     docker run hello-world
     ```
* **Minh chứng nộp bài:**
  1. File `commands.sh` chứa đầy đủ lệnh đã thực thi.
  2. Ảnh chụp Terminal hiển thị prompt `deploy@<hostname>:~$` chạy thành công `docker --version` và `docker compose version` mà không cần tiền tố `sudo`.

---

### 🔹 Bài 3: Tăng cường bảo mật SSH (Vận dụng chuyên sâu)
* **Vấn đề bảo mật:** Port 22 mở ra Internet thường xuyên bị Botnet quét và Brute-force mật khẩu tài khoản `root`.
* **Giải pháp chuẩn DevOps:**
  1. **Sinh cặp SSH Key trên máy cá nhân:**
     ```powershell
     ssh-keygen -t ed25519 -C "deploy@vps-staging"
     # Khóa công khai: ~/.ssh/id_ed25519.pub
     # Khóa bí mật: ~/.ssh/id_ed25519
     ```
  2. **Đẩy Public Key lên VPS cho user `deploy`:**
     ```powershell
     # Trên PowerShell máy cá nhân:
     type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh deploy@<PUBLIC_IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
     ```
  3. **Cấu hình SSH Daemon (`/etc/ssh/sshd_config`):**
     ```ini
     PermitRootLogin no
     PasswordAuthentication no
     PubkeyAuthentication yes
     AuthorizedKeysFile .ssh/authorized_keys
     ```
  4. **Khởi động lại dịch vụ SSH:**
     ```bash
     sudo systemctl restart ssh
     ```
     *(Lưu ý vàng: Luôn giữ phiên SSH cũ, mở terminal mới kiểm tra kết nối SSH Key trước khi đóng phiên cũ).*
* **Minh chứng nộp bài:**
  1. Hướng dẫn và script cấu hình SSH Key.
  2. Ảnh chụp thử đăng nhập bằng user `root` (`ssh root@<PUBLIC_IP>`) bị từ chối với thông báo: `Permission denied (publickey)`.
  3. Ảnh chụp đăng nhập thành công bằng user `deploy` qua SSH Key: `ssh -i ~/.ssh/id_ed25519 deploy@<PUBLIC_IP>`.

---

### 🔹 Bài 4: Cấu hình Firewall UFW (Vận dụng chuyên sâu)
* **Chiến lược phòng thủ (Defense in Depth):** Mặc định từ chối toàn bộ traffic vào (`default deny incoming`), chỉ mở đúng cổng dịch vụ cần thiết (Port 22 SSH & Port 8080 TCP).
* **Các bước triển khai UFW:**
  1. **Đặt policy mặc định:**
     ```bash
     sudo ufw default deny incoming
     sudo ufw default allow outgoing
     ```
  2. **Mở cổng 22 SSH trước khi bật firewall:**
     ```bash
     sudo ufw allow 22/tcp comment 'Allow SSH'
     ```
  3. **Mở cổng 8080 TCP:**
     ```bash
     sudo ufw allow 8080/tcp comment 'Allow Web App'
     ```
  4. **Kích hoạt UFW:**
     ```bash
     sudo ufw enable
     ```
  5. **Kiểm tra trạng thái:**
     ```bash
     sudo ufw status verbose
     ```
* **Thử nghiệm đối chứng với Docker Container:**
  ```bash
  # Chạy Container 1 trên cổng 8080 (đã mở)
  docker run -d --name web-8080 -p 8080:80 nginx:alpine

  # Chạy Container 2 trên cổng 8081 (chưa mở / bị chặn)
  docker run -d --name web-8081 -p 8081:80 nginx:alpine
  ```
  *(Lưu ý chuyên sâu: Docker mặc định can thiệp trực tiếp vào `iptables` NAT table có thể bypass UFW. Để đảm bảo firewall hoạt động nghiêm ngặt trên production, cấu hình ufw-docker hoặc bind container vào `127.0.0.1` khi chạy sau Reverse Proxy).*
* **Minh chứng nộp bài:**
  1. Ảnh chụp Terminal lệnh `sudo ufw status verbose` hiển thị rõ Port 22 và 8080 ALLOW.
  2. Ảnh chụp trình duyệt / curl truy cập thành công `http://<PUBLIC_IP>:8080` (trang Nginx Welcome).
  3. Ảnh chụp truy cập thất bại `http://<PUBLIC_IP>:8081` (kết nối bị Timeout / Connection Refused).
