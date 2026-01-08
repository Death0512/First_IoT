#!/usr/bin/env python3
"""
Script đơn giản để FIX password cũ (251203) cho user 00002
"""
import psycopg2
import hashlib

# Database config
DB_CONFIG = {
    'host': '47.128.146.122',
    'port': 5432,
    'database': 'iot_database_rfid',
    'user': 'iot_user_rfid',
    'password': 'iot2003A'
}

# SALT - PHẢI GIỐNG ESP8266 (dòng 22 trong main.cpp)
PASSKEY_SALT = "passkey_01_salt_2025"

def hash_password(plaintext):
    """Hash password ĐÚNG với SALT"""
    salted = PASSKEY_SALT + plaintext
    return hashlib.sha256(salted.encode('utf-8')).hexdigest()

print("="*70)
print("SỬA PASSWORD CŨ CHO USER 00002 (Thao)")
print("="*70)

# Mật khẩu gốc của bạn
password_goc = "251203"  # ← THAY ĐỔI NẾU KHÁC

print(f"\nMật khẩu gốc: {password_goc}")
print(f"Hash CŨ (SAI - không có SALT): 9dc3bece812e7e35fcf534ea2191d969794e8a6c394613bf96c4a468eff062a7")

# Tính hash MỚI với SALT
hash_moi = hash_password(password_goc)
print(f"Hash MỚI (ĐÚNG - có SALT):      {hash_moi}")

print("\n" + "-"*70)

# Kết nối database
conn = psycopg2.connect(**DB_CONFIG)
cur = conn.cursor()

# Xóa password cũ
print("\n[1] Xóa password cũ (hash sai)...")
cur.execute("DELETE FROM passwords WHERE user_id = '00002';")
deleted = cur.rowcount
print(f"    ✅ Đã xóa {deleted} password cũ")

# Thêm password mới với hash đúng
print("\n[2] Thêm password mới với hash đúng...")
cur.execute("""
    INSERT INTO passwords (password_id, user_id, hash, active, description, created_at, updated_at)
    VALUES (%s, %s, %s, %s, %s, NOW(), NOW())
""", ('passwd_00002_001', '00002', hash_moi, True, 'Vuong Linh Thao PIN - 251203'))

conn.commit()
print(f"    ✅ Đã thêm password mới: passwd_00002_001")

# Verify
cur.execute("SELECT password_id, hash, description FROM passwords WHERE user_id = '00002';")
result = cur.fetchone()

print("\n" + "="*70)
print("KẾT QUẢ:")
print("="*70)
print(f"Password ID:  {result[0]}")
print(f"Hash:         {result[1]}")
print(f"Description:  {result[2]}")
print(f"\nHash khớp với ESP8266: {'✅ ĐÚNG' if result[1] == hash_moi else '❌ SAI'}")

cur.close()
conn.close()

print("\n" + "="*70)
print("📱 BÂY GIỜ BẠN CÓ THỂ NHẬP '251203' TỪ THIẾT BỊ!")
print("="*70)
