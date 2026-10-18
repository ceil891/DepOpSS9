#!/bin/bash
# ==============================================================================
# Script: setup-ssh-security.sh
# Mục đích: Tăng cường bảo mật SSH trên VPS Ubuntu 22.04 LTS
#           1. Thiết lập thư mục và quyền cho ~/.ssh/authorized_keys của user 'deploy'
#           2. Cấu hình SSHD: Tắt Root Login, Tắt xác thực bằng Password
#           3. Khởi động lại ssh service an toàn
# ==============================================================================

set -e

echo "=== [1] KIỂM TRA THƯ MỤC .ssh CHO USER 'deploy' ==="
TARGET_USER="deploy"
USER_HOME=$(eval echo "~$TARGET_USER")

# Tạo thư mục .ssh nếu chưa có và phân quyền chuẩn 700
sudo -u "$TARGET_USER" mkdir -p "$USER_HOME/.ssh"
sudo chmod 700 "$USER_HOME/.ssh"

# Tạo file authorized_keys nếu chưa có và phân quyền chuẩn 600
sudo -u "$TARGET_USER" touch "$USER_HOME/.ssh/authorized_keys"
sudo chmod 600 "$USER_HOME/.ssh/authorized_keys"
sudo chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.ssh"

echo "Thư mục ~/.ssh và authorized_keys đã được phân quyền bảo mật (700/600)."

echo "=== [2] SAO LƯU FILE CẤU HÌNH SSHD ==="
SSHD_CONFIG="/etc/ssh/sshd_config"
sudo cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup_$(date +%F_%T)"
echo "Đã backup cấu hình SSHD sang: ${SSHD_CONFIG}.backup_*"

echo "=== [3] CẤU HÌNH HARDENING TRONG SSHD_CONFIG ==="
# Cấu hình PermitRootLogin no
if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
    sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
elif grep -q "^#PermitRootLogin" "$SSHD_CONFIG"; then
    sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
else
    echo "PermitRootLogin no" | sudo tee -a "$SSHD_CONFIG"
fi

# Cấu hình PasswordAuthentication no
if grep -q "^PasswordAuthentication" "$SSHD_CONFIG"; then
    sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
elif grep -q "^#PasswordAuthentication" "$SSHD_CONFIG"; then
    sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
else
    echo "PasswordAuthentication no" | sudo tee -a "$SSHD_CONFIG"
fi

# Đảm bảo bật PubkeyAuthentication yes
if grep -q "^PubkeyAuthentication" "$SSHD_CONFIG"; then
    sudo sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
elif grep -q "^#PubkeyAuthentication" "$SSHD_CONFIG"; then
    sudo sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
else
    echo "PubkeyAuthentication yes" | sudo tee -a "$SSHD_CONFIG"
fi

# Đảm bảo tắt KbdInteractiveAuthentication nếu có trên Ubuntu 22.04
if grep -q "^KbdInteractiveAuthentication" "$SSHD_CONFIG"; then
    sudo sed -i 's/^KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$SSHD_CONFIG"
fi

# Đồng thời cấu hình trong sshd_config.d/ (nếu Ubuntu 22.04 include sshd_config.d/*.conf)
sudo mkdir -p /etc/ssh/sshd_config.d
echo -e "# Custom Hardening\nPermitRootLogin no\nPasswordAuthentication no\nPubkeyAuthentication yes" | sudo tee /etc/ssh/sshd_config.d/50-cloud-init.conf > /dev/null

echo "=== [4] KIỂM TRA CÚ PHÁP CẤU HÌNH SSHD ==="
sudo sshd -t
echo "Cú pháp cấu hình SSHD hợp lệ!"

echo "=== [5] KHỞI ĐỘNG LẠI DỊCH VỤ SSH ==="
sudo systemctl restart ssh || sudo systemctl restart sshd

echo "=============================================================================="
echo "BẢO MẬT SSH HOÀN TẤT!"
echo "LƯU Ý CỰC KỲ QUAN TRỌNG:"
echo "1. KHÔNG đóng cửa sổ Terminal này vội!"
echo "2. Mở một cửa sổ Terminal MỚI trên máy cá nhân và thử kết nối:"
echo "   ssh -i <private_key> deploy@<IP_VPS>"
echo "3. Kiểm tra user root bị từ chối:"
echo "   ssh root@<IP_VPS>"
echo "=============================================================================="
