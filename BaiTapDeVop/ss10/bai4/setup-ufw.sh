#!/bin/bash
# ==============================================================================
# Script: setup-ufw.sh
# Mục đích: Thiết lập tường lửa Uncomplicated Firewall (UFW) trên Ubuntu 22.04
#           - Chặn mặc định mọi kết nối đến (Deny Incoming)
#           - Cho phép mặc định mọi kết nối đi (Allow Outgoing)
#           - Mở Port 22/tcp (SSH) để không bị khóa kết nối
#           - Mở Port 8080/tcp (Ứng dụng Web)
#           - Chạy 2 Nginx container ở port 8080 và 8081 để thử nghiệm đối chứng
# ==============================================================================

set -e

echo "=== [1] THIẾT LẬP CHÍNH SÁCH MẶC ĐỊNH (DEFAULT POLICIES) ==="
sudo ufw default deny incoming
sudo ufw default allow outgoing
echo "Chính sách: Deny Incoming, Allow Outgoing."

echo "=== [2] MỞ CÁC CỔNG DỊCH VỤ CẦN THIẾT ==="
# BẮT BUỘC: Mở cổng 22 SSH trước khi kích hoạt UFW
sudo ufw allow 22/tcp comment 'SSH Access'

# Mở cổng 8080 cho ứng dụng Web
sudo ufw allow 8080/tcp comment 'Web App Staging'

# Đảm bảo cổng 8081 bị chặn (hoặc mặc định bị từ chối)
sudo ufw deny 8081/tcp comment 'Blocked Port'

echo "=== [3] KÍCH HOẠT UFW FIREWALL ==="
# Bật firewall tự động không cần prompt xác nhận
echo "y" | sudo ufw enable
sudo ufw reload

echo "=== [4] KIỂM TRA TRẠNG THÁI UFW (STATUS VERBOSE) ==="
sudo ufw status verbose

echo "=== [5] XỬ LÝ ĐẶC THÙ DOCKER & UFW (NÂNG CAO) ==="
# Ghi chú kỹ thuật: Docker mặc định can thiệp trực tiếp vào bảng NAT iptables.
# Để đảm bảo UFW quản lý được port của Docker container, cấu hình rule chặn port 8081 trong bảng forward/route nếu cần:
sudo ufw route deny proto tcp to any port 8081 || true

echo "=== [6] KHỞI CHẠY 2 NGINX CONTAINER THỬ NGHIỆM ĐỐI CHỨNG ==="
# Dọn dẹp container cũ nếu có
docker rm -f nginx-8080 nginx-8081 2>/dev/null || true

# Khởi chạy Nginx 1 tại Port 8080 (Đã mở trên Firewall)
docker run -d --name nginx-8080 -p 8080:80 nginx:alpine

# Khởi chạy Nginx 2 tại Port 8081 (Bị chặn trên Firewall)
docker run -d --name nginx-8081 -p 8081:80 nginx:alpine

echo "=============================================================================="
echo "CẤU HÌNH UFW VÀ DOCKER TEST CONTAINER HOÀN TẤT!"
echo "Kiểm tra:"
echo "1. Kiểm tra trạng thái Firewall: sudo ufw status verbose"
echo "2. Trên máy cá nhân hoặc trình duyệt:"
echo "   - Cổng 8080: http://<PUBLIC_IP_VPS>:8080  --> THÀNH CÔNG (HTTP 200 OK)"
echo "   - Cổng 8081: http://<PUBLIC_IP_VPS>:8081  --> THẤT BÀI (Connection Timed Out / Refused)"
echo "=============================================================================="
