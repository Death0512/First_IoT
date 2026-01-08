#!/usr/bin/env python3
"""
Script để fix password hash trong database PostgreSQL
Vì trước đây hash KHÔNG có SALT, giờ phải thêm SALT
"""
import psycopg2
import hashlib

# Database configuration
DB_CONFIG = {
    'host': '47.128.146.122',
    'port': 5432,
    'database': 'iot_database_rfid',
    'user': 'iot_user_rfid',
    'password': 'iot2003A'
}

# SALT phải giống ESP8266
PASSKEY_SALT = "passkey_01_salt_2025"

def sha256_hex_with_salt(password):
    """Hash password với SALT giống ESP8266"""
    salted = PASSKEY_SALT + password
    return hashlib.sha256(salted.encode('utf-8')).hexdigest()

def main():
    print("="*70)
    print("FIX PASSWORD HASH - THÊM SALT")
    print("="*70)
    
    # Kết nối database
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    print("\n[1] Kiểm tra passwords hiện tại...")
    cur.execute("SELECT password_id, user_id, hash, description FROM passwords;")
    passwords = cur.fetchall()
    
    print(f"\nTìm thấy {len(passwords)} passwords trong database:")
    for pwd in passwords:
        print(f"  - {pwd[0]}: {pwd[3]} (user: {pwd[1]})")
    
    print("\n" + "="*70)
    print("⚠️  CẢNH BÁO: Tất cả password cũ ĐỀU SAI vì thiếu SALT!")
    print("="*70)
    print("\nCó 2 lựa chọn:")
    print("  [1] XÓA TẤT CẢ password cũ (khuyến nghị)")
    print("  [2] Giữ lại (nhưng sẽ không hoạt động)")
    print("\nSau đó bạn phải:")
    print("  - Thêm lại password mới từ web app")
    print("  - Password mới sẽ được hash ĐÚNG với SALT")
    
    choice = input("\nChọn [1/2]: ").strip()
    
    if choice == "1":
        print("\n[ACTION] Đang xóa tất cả passwords cũ...")
        cur.execute("DELETE FROM passwords WHERE 1=1;")
        conn.commit()
        print("✅ Đã xóa tất cả passwords cũ")
        
        print("\n[INFO] Bạn có thể test bằng cách thêm password mới:")
        print("\n  Ví dụ: password = '123456'")
        print(f"  Hash mới (với SALT) = {sha256_hex_with_salt('123456')}")
        
        add_test = input("\nThêm password test '123456' cho user 00002? [y/n]: ").strip().lower()
        if add_test == 'y':
            test_hash = sha256_hex_with_salt('123456')
            cur.execute("""
                INSERT INTO passwords (password_id, user_id, hash, active, description, created_at, updated_at)
                VALUES (%s, %s, %s, %s, %s, NOW(), NOW())
            """, ('passwd_00002_test', '00002', test_hash, True, 'Test password - 123456'))
            conn.commit()
            print(f"✅ Đã thêm test password với hash: {test_hash}")
            print("\n📱 Bây giờ bạn có thể thử nhập '123456' từ thiết bị ESP8266!")
    else:
        print("\n⚠️  Không làm gì. Password cũ vẫn SAI và sẽ không hoạt động!")
    
    cur.close()
    conn.close()
    
    print("\n" + "="*70)
    print("HOÀN TẤT!")
    print("="*70)

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f"\n❌ Lỗi: {e}")
