#!/usr/bin/env python3
"""
Test script để kiểm tra flow thêm passkey và sync
"""
import requests
import time
import json

print("="*70)
print("TEST: THÊM PASSKEY VÀ KIỂM TRA SYNC")
print("="*70)

# Config
WEB_APP_URL = "http://localhost:5000"  # Flask web app
FASTAPI_URL = "http://47.128.146.122:3000"  # FastAPI server
USER_ID = "00002"
GATEWAY_ID = "Gateway2"

# Step 1: Kiểm tra database hiện tại của Gateway
print("\n[STEP 1] Kiểm tra database hiện tại của Gateway2...")
try:
    response = requests.get(f"{FASTAPI_URL}/api/sync/database/{GATEWAY_ID}")
    if response.status_code == 200:
        data = response.json()
        current_passwords = len(data.get('database', {}).get('passwords', {}))
        print(f"✅ Số passkey hiện tại: {current_passwords}")
        print(f"   Version: {data.get('version')}")
    else:
        print(f"❌ Lỗi: {response.status_code}")
except Exception as e:
    print(f"❌ Lỗi: {e}")

# Step 2: Thêm passkey mới qua web app
print("\n[STEP 2] Thêm passkey mới qua web app...")
new_passcode = f"TEST{int(time.time())}"
print(f"   Passcode: {new_passcode}")

try:
    response = requests.post(
        f"{WEB_APP_URL}/access/manage_passkey",
        json={
            "action": "add",
            "owner": USER_ID,
            "passcode": new_passcode,
            "description": f"Test passkey - {time.strftime('%Y-%m-%d %H:%M:%S')}",
            "active": True
        }
    )
    if response.status_code == 200:
        print("✅ Passkey đã được thêm vào database VPS")
        print("   Web app đã gọi trigger_sync_safe()")
    else:
        print(f"❌ Lỗi thêm passkey: {response.status_code}")
        print(response.text)
        exit(1)
except Exception as e:
    print(f"❌ Lỗi: {e}")
    exit(1)

# Step 3: Chờ sync (Gateway sync mỗi 5s, hoặc ngay lập tức khi nhận MQTT trigger)
print("\n[STEP 3] Chờ Gateway sync (sẽ mất 1-5 giây)...")
print("   (Gateway sẽ hiển thị log '✅ DATABASE SYNC COMPLETED SUCCESSFULLY!')")
time.sleep(6)

# Step 4: Kiểm tra database sau khi sync
print("\n[STEP 4] Kiểm tra database sau khi sync...")
try:
    response = requests.get(f"{FASTAPI_URL}/api/sync/database/{GATEWAY_ID}")
    if response.status_code == 200:
        data = response.json()
        new_passwords = len(data.get('database', {}).get('passwords', {}))
        print(f"✅ Số passkey sau sync: {new_passwords}")
        print(f"   Version mới: {data.get('version')}")
        
        if new_passwords > current_passwords:
            print(f"\n🎉 THÀNH CÔNG! Passkey mới đã được sync xuống Gateway")
            print(f"   Bạn có thể nhập passkey '{new_passcode}' từ thiết bị ngay bây giờ!")
        else:
            print("\n⚠️ Passkey chưa được sync. Hãy chờ thêm 5 giây...")
    else:
        print(f"❌ Lỗi: {response.status_code}")
except Exception as e:
    print(f"❌ Lỗi: {e}")

print("\n" + "="*70)
print("KẾT THÚC TEST")
print("="*70)
