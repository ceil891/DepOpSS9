#!/bin/bash
# ==============================================================================
# Script: setup-deploy-user-docker.sh
# Mục đích: Tạo user 'deploy' với quyền sudo, cài đặt Docker Engine & Compose plugin,
#           và thêm user 'deploy' vào group 'docker'.
# Hệ điều hành: Ubuntu 22.04 LTS
# ==============================================================================

# Dừng script ngay khi gặp lỗi
set -e

echo "=== [BƯỚC 1] CẬP NHẬT HỆ THỐNG VÀ CÀI ĐẶT GÓI PHỤ THUỘC ==="
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release

echo "=== [BƯỚC 2] TẠO USER 'deploy' VÀ CẤP QUYỀN SUDO ==="
# Kiểm tra nếu user deploy chưa tồn tại thì tạo mới
if id "deploy" &>/dev/null; then
    echo "User 'deploy' đã tồn tại. Bỏ qua bước tạo."
else
    # Tạo user deploy có thư mục home và shell bash mặc định
    sudo adduser --gecos "" deploy
    echo "Thiết lập mật khẩu cho user 'deploy' hoàn tất."
fi

# Cấp quyền sudo cho user deploy
sudo usermod -aG sudo deploy
echo "Đã thêm user 'deploy' vào nhóm sudo."

echo "=== [BƯỚC 3] CÀI ĐẶT DOCKER ENGINE VÀ DOCKER COMPOSE TỪ OFFICIAL REPO ==="
# 1. Tạo thư mục chứa keyrings của APT
sudo install -m 0755 -d /etc/apt/keyrings

# 2. Tải GPG Key chính thức của Docker
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 3. Thêm Docker Repository vào nguồn APT Sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Cập nhật APT và cài đặt Docker CE, Docker Compose Plugin
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Khởi động và kích hoạt Docker chạy cùng hệ thống
sudo systemctl start docker
sudo systemctl enable docker

echo "=== [BƯỚC 4] THÊM USER 'deploy' VÀO NHÓM DOCKER ==="
sudo usermod -aG docker deploy
echo "Đã thêm user 'deploy' vào nhóm docker thành công."

echo "=== [BƯỚC 5] KIỂM TRA PHIÊN BẢN VÀ DỊCH VỤ ==="
echo "Kiểm tra phiên bản Docker chạy dưới quyền hệ thống:"
docker --version
docker compose version

echo "=============================================================================="
echo "HOÀN TẤT CÀI ĐẶT!"
echo "Để kiểm tra dưới quyền user deploy mà không cần sudo, hãy chạy lệnh:"
echo "  su - deploy"
echo "  docker --version"
echo "  docker run hello-world"
echo "=============================================================================="
