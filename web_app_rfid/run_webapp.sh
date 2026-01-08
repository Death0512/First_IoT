#!/bin/bash
# Wrapper script để chạy web app với code mới (đã sửa SALT)

cd /run/media/mtu/Thao/Lap_trinh_iot/First_IoT/web_app_rfid

# Xóa cache Python để đảm bảo load code mới
echo "🧹 Xóa Python cache..."
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
find . -name "*.pyc" -delete 2>/dev/null

echo "🚀 Đang khởi động web app với code MỚI (có SALT)..."
echo "   SALT = 'passkey_01_salt_2025'"
echo ""

# Chạy web app
python run.py
