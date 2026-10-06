#!/usr/bin/env bash
# =============================================================================
# SCRIPT CÀI ĐẶT CERTBOT, CẤP PHÁT SSL LET'S ENCRYPT VÀ THIẾT LẬP AUTO-RENEW
# Mục tiêu domain: api.my-ecommerce.com
# Hệ điều hành: Ubuntu 20.04 / 22.04 / 24.04 LTS
# =============================================================================

set -e

DOMAIN="api.my-ecommerce.com"
EMAIL="admin@my-ecommerce.com"

echo "=================================================================="
echo "BƯỚC 1: CẬP NHẬT HỆ THỐNG VÀ CÀI ĐẶT CERTBOT TRÊN UBUNTU"
echo "=================================================================="
sudo apt update -y

# Phương pháp 1: Khuyến nghị chính thức từ EFF/Certbot (qua Snapd)
if command -v snap &> /dev/null; then
    echo ">> Cài đặt Certbot thông qua Snap..."
    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot
else
    # Phương pháp 2: Cài đặt thông qua APT repository
    echo ">> Cài đặt Certbot và python3-certbot-nginx thông qua APT..."
    sudo apt install -y certbot python3-certbot-nginx
fi

echo ">> Phiên bản Certbot đã cài đặt:"
certbot --version

echo ""
echo "=================================================================="
echo "BƯỚC 2: CẤP PHÁT CHỨNG CHỈ SSL VÀ TỰ ĐỘNG CẤU HÌNH NGINX"
echo "=================================================================="
# Lệnh Certbot chạy plugin Nginx để xác thực HTTP-01 challenge và tự chèn cấu hình SSL
sudo certbot --nginx \
    -d "$DOMAIN" \
    --agree-tos \
    --email "$EMAIL" \
    --non-interactive \
    --redirect

echo ""
echo "=================================================================="
echo "BƯỚC 3: KIỂM TRA THỬ NGHIỆM GIA HẠN TỰ ĐỘNG (DRY-RUN)"
echo "=================================================================="
# Dry-run kiểm tra khả năng renew mà không làm thay đổi hay hao tốn quota chứng chỉ
sudo certbot renew --dry-run

echo ""
echo "=================================================================="
echo "BƯỚC 4: THIẾT LẬP / KIỂM TRA TỰ ĐỘNG GIA HẠN (AUTO-RENEW)"
echo "=================================================================="
# 1. Kiểm tra systemd timer mặc định của Certbot
echo ">> Kiểm tra trạng thái Certbot systemd timer:"
sudo systemctl status certbot.timer --no-pager || true

# 2. Tạo bổ sung Cronjob dự phòng có kèm hook reload Nginx
CRON_JOB="0 3 * * * /usr/bin/certbot renew --quiet --deploy-hook 'systemctl reload nginx'"
(sudo crontab -l 2>/dev/null | grep -v "certbot renew" ; echo "$CRON_JOB") | sudo crontab -

echo ">> Đã thiết lập Cronjob tự động gia hạn thành công:"
sudo crontab -l | grep certbot

echo ""
echo "=================================================================="
echo "HOÀN TẤT CẤU HÌNH SSL HTTPS CHO DOMAIN: $DOMAIN"
echo "=================================================================="
