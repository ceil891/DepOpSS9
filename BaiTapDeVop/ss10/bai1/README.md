# Bài 1: Khởi Tạo Và Kết Nối VPS (Vận Dụng Cơ Bản)

> **Môn học:** DevOps  
> **Chủ đề:** Cloud VPS, Instance Provisioning, SSH Connection  

---

## 1. Mục tiêu & Tình huống nghiệp vụ

* **Mục tiêu:**
  * Hiểu khái niệm Virtual Private Server (VPS) và kiến trúc máy ảo trên nền tảng Cloud.
  * Nắm vững quy trình khởi tạo máy chủ chạy hệ điều hành **Ubuntu 22.04 LTS**.
  * Cấu hình tường lửa mạng (Security Group / Cloud Firewall) mở cổng SSH (Port 22).
  * Thực hiện kết nối an toàn từ máy cá nhân (Windows PowerShell / Linux Terminal) bằng giao thức SSH.
* **Tình huống nghiệp vụ:**
  * Công ty chuẩn bị môi trường thử nghiệm (Staging). Là DevOps Engineer, bạn cần tạo máy chủ VPS mới, cấu hình IP Public và kết nối thành công để bàn giao cho các công đoạn cài đặt môi trường tiếp theo.

---

## 2. Các bước triển khai thực tế

### Bước 1: Chọn Cloud Provider & Khởi tạo VPS

Bạn có thể lựa chọn 1 trong các Cloud Provider phổ biến hoặc Local VM:
* **AWS EC2 (Khuyến nghị):**
  * Đăng nhập [AWS Console](https://console.aws.amazon.com/) -> Vào dịch vụ **EC2** -> Chọn **Launch Instance**.
  * **Name:** `staging-server`
  * **AMI:** Ubuntu Server 22.04 LTS (HVM), SSD Volume Type (Free tier eligible).
  * **Architecture:** 64-bit (x86).
  * **Instance type:** `t2.micro` (hoặc `t3.micro` tùy vùng).
  * **Key pair:** Chọn "Create new key pair", định dạng `.pem` (hoặc `.ppk` nếu dùng PuTTY cũ), tải file `my-vps-key.pem` về máy cá nhân lưu tại thư mục an toàn (vd: `C:\Users\<user>\.ssh\`).
  * **Network Settings (Firewall / Security Group):**
    * Tích chọn **Allow SSH traffic from**: chọn `Anywhere (0.0.0.0/0)` hoặc `My IP`.
    * Tích chọn **Allow HTTP / HTTPS traffic from the internet** (để chuẩn bị cho bài sau).
  * Nhấn **Launch Instance**.

* **Google Cloud Platform (GCP Compute Engine):**
  * Vào **Compute Engine** -> **VM instances** -> **Create Instance**.
  * Chọn vùng (Region/Zone), Machine type: `e2-micro`.
  * Boot disk: Chọn Ubuntu 22.04 LTS.
  * Tích chọn "Allow HTTP traffic" và "Allow HTTPS traffic".

* **DigitalOcean / Vultr / Linode:**
  * Chọn Droplet / Compute Instance -> Ubuntu 22.04 LTS x64 -> Basic plan.
  * Authentication: Chọn SSH Key hoặc root password.

*(Lưu ý: Nếu không có thẻ thanh toán quốc tế để dùng Cloud, bạn có thể dùng **Multipass** hoặc **Oracle VirtualBox** tạo máy ảo Ubuntu 22.04 và dùng mạng Bridged Adapter để có IP mạng nội bộ).*

---

### Bước 2: Lấy địa chỉ Public IP của VPS

Sau khi Instance chuyển sang trạng thái `Running`:
* Tìm thông số **Public IPv4 address** (ví dụ: `54.214.88.120`).
* Đảm bảo trạng thái **Status check**: `2/2 checks passed`.

---

### Bước 3: Phân quyền khóa bí mật (Chỉ áp dụng với AWS key .pem)

Trên máy cá nhân (Windows PowerShell):
```powershell
# Chuyển đến thư mục chứa file key đã tải về
cd C:\Users\<Username>\.ssh

# Thiết lập quyền đọc cho file key (tránh lỗi Unprotected private key file trên SSH client)
icacls .\my-vps-key.pem /inheritance:r
icacls .\my-vps-key.pem /grant:r "$($env:USERNAME):(R)"
```
*(Trên Linux/macOS: `chmod 400 my-vps-key.pem`)*

---

### Bước 4: Mở Terminal/PowerShell và kết nối SSH

* **Trường hợp dùng SSH Key (AWS / GCP / Cloud có key):**
  ```powershell
  ssh -i "C:\Users\<Username>\.ssh\my-vps-key.pem" ubuntu@<PUBLIC_IP_VPS>
  ```
  *(Khi được hỏi `Are you sure you want to continue connecting (yes/no/[fingerprint])?`, gõ `yes` và nhấn Enter).*

* **Trường hợp dùng Mật khẩu (VPS DigitalOcean / Vultr / Linode / Local VM):**
  ```powershell
  ssh root@<PUBLIC_IP_VPS>
  # Nhập mật khẩu khi được yêu cầu
  ```

---

## 3. Checklist kết quả mong muốn nộp bài

1. 📸 **Ảnh chụp màn hình cấu hình thông số VPS trên giao diện Cloud:**
   * Hiển thị rõ: **Instance ID / Name**, **Status: Running**, **Public IPv4 address**, **AMI: Ubuntu 22.04 LTS**, **Instance type**.
   * Lưu ảnh vào thư mục: `ss10/bai1/screenshots/vps-cloud-config.png`.

2. 📸 **Ảnh chụp màn hình Terminal / PowerShell:**
   * Hiển thị câu lệnh `ssh ...` và banner chào mừng của Ubuntu:
     ```
     Welcome to Ubuntu 22.04.x LTS (GNU/Linux 5.15.0-xxx-generic x86_64)
     ...
     ubuntu@ip-172-31-xx-xx:~$
     ```
   * Lưu ảnh vào thư mục: `ss10/bai1/screenshots/ssh-connection-success.png`.
