"""
Quick script để fix password hash cho user 00002
Chạy từ thư mục web_app_rfid
"""
from app.db_connect import get_db
from app.utils.helpers import sha256_hex
import time

print("="*70)
print("SỬA PASSWORD CŨ CHO USER 00002 (Thao)")
print("="*70)

# Mật khẩu gốc của bạn
password_goc = "251203"  # ← Password thật của bạn

print(f"\nMật khẩu gốc: {password_goc}")
print(f"Tính hash MỚI với SALT...")

# Tính hash mới (helpers.py đã được sửa để dùng SALT)
hash_moi = sha256_hex(password_goc)
print(f"Hash MỚI (có SALT): {hash_moi}")

# Connect database
conn = get_db()
cur = conn.cursor()

# Xem password cũ
print("\n[CHECK] Password hiện tại:")
cur.execute("SELECT password_id, hash, description FROM passwords WHERE user_id = '00002';")
old_passwords = cur.fetchall()
for p in old_passwords:
    print(f"  - {p['password_id']}: {p['description']}")
    print(f"    Hash cũ: {p['hash'][:32]}...")

# Xóa password cũ
print("\n[1] Đang xóa password cũ...")
cur.execute("DELETE FROM passwords WHERE user_id = '00002';")
conn.commit()
print(f"    ✅ Đã xóa {cur.rowcount} password")

# Thêm password mới
print("\n[2] Đang thêm password mới với hash đúng...")
new_id = f"passwd_00002_{int(time.time())}"
cur.execute("""
    INSERT INTO passwords (password_id, user_id, hash, active, description, created_at, updated_at)
    VALUES (%s, %s, %s, %s, %s, NOW(), NOW())
""", (new_id, '00002', hash_moi, True, 'Vuong Linh Thao PIN - 251203'))
conn.commit()
print(f"    ✅ Password ID: {new_id}")

# Verify
cur.execute("SELECT password_id, hash, description FROM passwords WHERE user_id = '00002';")
result = cur.fetchone()

print("\n" + "="*70)
print("✅ HOÀN TẤT!")
print("="*70)
print(f"Password ID:  {result['password_id']}")
print(f"Description:  {result['description']}")
print(f"Hash:         {result['hash']}")

cur.close()
conn.close()

print("\n" + "="*70)
print("📱 BÂY GIỜ BẠN CÓ THỂ NHẬP '251203' TỪ THIẾT BỊ ESP8266!")
print("   Gateway sẽ sync trong 1-5 giây")
print("="*70)
