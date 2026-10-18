# Bài 3: Tăng Cường Bảo Mật SSH (Vận Dụng Chuyên Sâu)

> **Môn học:** DevOps  
> **Chủ đề:** SSH Hardening, Key-based Authentication, Disable Root Login, Disable Password Auth  

---

## 1. Tình huống nghiệp vụ & Kiến thức cốt lõi

* **Vấn đề an ninh:**
  * Cổng SSH (mặc định Port 22) khi phơi ra Internet sẽ phải đối mặt với hàng chục ngàn lượt rà quét tự động mỗi ngày từ các botnet. Các cuộc tấn công Brute-force / Dictionary Attack liên tục nhắm vào tài khoản `root`. Nếu sử dụng xác thực bằng mật khẩu (Password Authentication), nguy cơ bị dò trúng mật khẩu là rất lớn.
* **Giải pháp chuẩn:**
  1. **Chuyển sang xác thực khóa bất đối xứng (SSH Key-based Authentication):** Sử dụng thuật toán hiện đại **Ed25519** (nhanh và an toàn hơn RSA truyền thống). Máy cá nhân giữ Private Key, máy chủ VPS chỉ lưu Public Key.
  2. **Vô hiệu hóa đăng nhập bằng mật khẩu (`PasswordAuthentication no`):** Loại bỏ hoàn toàn nguy cơ Brute-force mật khẩu.
  3. **Vô hiệu hóa đăng nhập trực tiếp tài khoản Root (`PermitRootLogin no`):** Buộc mọi truy cập phải qua user `deploy`, sau đó nếu cần thực hiện lệnh quản trị thì dùng `sudo` (có audit log).

---

## 2. Hướng dẫn thực hành chi tiết từng bước

### Bước 1: Tạo cặp SSH Key trên máy cá nhân (Local Machine)

Mở **PowerShell** hoặc **Terminal** trên máy tính cá nhân của bạn:

```powershell
# Tạo SSH key thuật toán ed25519 (Khuyến nghị hiện nay)
ssh-keygen -t ed25519 -C "deploy@staging-vps"

# Hoặc nếu muốn dùng thuật toán RSA chuẩn 4096 bit:
# ssh-keygen -t rsa -b 4096 -C "deploy@staging-vps"
```

* Hệ thống sẽ hỏi vị trí lưu file: Nhấn **Enter** để chọn mặc định (lưu tại `~/.ssh/id_ed25519`).
* Hệ thống hỏi nhập Passphrase (mật khẩu bảo vệ key): Có thể nhập mật khẩu hoặc nhấn **Enter** 2 lần để bỏ qua.

Kết quả sẽ sinh ra 2 file trong thư mục `~/.ssh/` (trên Windows là `C:\Users\<Tên_User>\.ssh\`):
* `id_ed25519` : **Private Key** (TUYỆT ĐỐI GIỮ BÍ MẬT, không chia sẻ cho bất kỳ ai).
* `id_ed25519.pub` : **Public Key** (Được dùng để đưa lên server).

---

### Bước 2: Đẩy Public Key lên VPS cho user `deploy`

Chọn **1 trong 2 cách** sau:

#### 👉 Cách 2A: Tự động qua lệnh trên PowerShell (Máy Windows)
```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh deploy@<PUBLIC_IP_VPS> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```
*(Nếu bạn dùng Git Bash hoặc Linux máy cá nhân, chỉ cần: `ssh-copy-id deploy@<PUBLIC_IP_VPS>`)*.

#### 👉 Cách 2B: Thao tác thủ công trên VPS
1. Trên máy cá nhân, xem nội dung Public Key và copy:
   ```powershell
   Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub
   # Nội dung có dạng: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... deploy@staging-vps
   ```
2. Đăng nhập vào VPS với user `deploy`:
   ```bash
   ssh deploy@<PUBLIC_IP_VPS>
   ```
3. Tạo thư mục `.ssh` và dán public key:
   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   nano ~/.ssh/authorized_keys
   # Dán toàn bộ nội dung public key vào đây, sau đó nhấn Ctrl + O -> Enter -> Ctrl + X để lưu
   chmod 600 ~/.ssh/authorized_keys
   ```

* **Lưu ý quan trọng về Permission trên Linux:**
  * Thư mục `~/.ssh` **BẮT BUỘC** là `700` (`drwx------`).
  * File `~/.ssh/authorized_keys` **BẮT BUỘC** là `600` (`-rw-------`).
  * Nếu cấp sai quyền (ví dụ `777`), SSH Daemon sẽ từ chối nhận key vì lý do an toàn!

---

### Bước 3: Cấu hình tắt mật khẩu và tắt Root Login trên VPS

Đăng nhập vào VPS, chỉnh sửa file cấu hình của SSH Daemon:

```bash
sudo nano /etc/ssh/sshd_config
```

Tìm và điều chỉnh (hoặc thêm vào cuối file) các chỉ thị sau:

```ini
# Vô hiệu hóa đăng nhập trực tiếp tài khoản root
PermitRootLogin no

# Vô hiệu hóa đăng nhập bằng mật khẩu thông thường
PasswordAuthentication no

# Cho phép đăng nhập bằng SSH Key
PubkeyAuthentication yes

# Tắt xác thực tương tác bàn phím
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
```

*(Lưu ý: Trên Ubuntu 22.04 LTS, hãy kiểm tra thêm thư mục `/etc/ssh/sshd_config.d/`. Nếu có file cấu hình ghi đè như `50-cloud-init.conf`, cần đảm bảo trong đó cũng đặt `PasswordAuthentication no`)*:
```bash
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
```

---

### Bước 4: Kiểm tra cú pháp và khởi động lại SSH Service

> ⚠️ **QUY TẮC AN TOÀN SỐNG CÒN CỦA DEVOPS:**
> Không bao giờ tắt phiên SSH hiện tại trước khi kiểm tra file cấu hình và test thành công trên một cửa sổ mới. Nếu cấu hình sai và bạn tắt phiên hiện tại, bạn có thể bị khóa vĩnh viễn khỏi VPS!

1. Kiểm tra cú pháp file cấu hình:
   ```bash
   sudo sshd -t
   # Nếu không có thông báo lỗi nào xuất hiện, cấu hình là chính xác!
   ```

2. Khởi động lại dịch vụ SSH để áp dụng cấu hình:
   ```bash
   sudo systemctl restart ssh
   # Trên một số bản Linux khác là: sudo systemctl restart sshd
   ```

---

### Bước 5: Kiểm tra và xác nhận kết quả (Verification)

Mở một cửa sổ **PowerShell/Terminal MỚI** trên máy cá nhân để kiểm tra:

1. **Test 1: Đăng nhập bằng user `deploy` qua SSH Key (Thành công)**
   ```powershell
   ssh -i $env:USERPROFILE\.ssh\id_ed25519 deploy@<PUBLIC_IP_VPS>
   ```
   👉 **Kết quả:** Đăng nhập thành công ngay lập tức mà không yêu cầu nhập mật khẩu tài khoản Linux.

2. **Test 2: Thử đăng nhập bằng tài khoản `root` (Bị từ chối)**
   ```powershell
   ssh root@<PUBLIC_IP_VPS>
   ```
   👉 **Kết quả:** Bị máy chủ từ chối ngay lập tức:
   ```text
   root@<PUBLIC_IP_VPS>: Permission denied (publickey).
   ```

3. **Test 3: Thử đăng nhập không có SSH Key (Bị từ chối)**
   ```powershell
   ssh -o PubkeyAuthentication=no deploy@<PUBLIC_IP_VPS>
   ```
   👉 **Kết quả:** Báo lỗi `Permission denied`, chứng minh Password Authentication đã bị vô hiệu hóa hoàn toàn.

---

## 3. Checklist kết quả mong muốn nộp bài

1. 📄 **File cấu hình & Lệnh:**
   * Script tự động: [setup-ssh-security.sh](file:///e:/BaiTapDeVop/ss10/bai3/setup-ssh-security.sh).
2. 📸 **Ảnh chụp màn hình Terminal:**
   * Ảnh 1: Đăng nhập user `deploy` bằng SSH Key thành công (`deploy@staging:~$`).
   * Ảnh 2: Thử đăng nhập user `root` (`ssh root@<IP>`) và nhận kết quả **`Permission denied (publickey)`**.
   * Lưu ảnh vào: `ss10/bai3/screenshots/root-login-denied.png`.
