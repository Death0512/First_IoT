# HƯỚNG DẪN: THÊM VÀ SỬ DỤNG PASSKEY MỚI

## ❗ VẤN ĐỀ TRƯỚC ĐÂY
- Khi thêm passkey mới từ web app → lưu vào database VPS
- Gateway User2 chưa kịp sync → nhập passkey ngay lập tức → báo sai mật khẩu

## ✅ GIẢI PHÁP ĐÃ THỰC HIỆN

### 1. Cơ chế Sync tự động:
- Gateway sync database **mỗi 5 giây** tự động
- Khi thêm/sửa/xóa passkey → Web app **tự động trigger sync ngay lập tức** qua MQTT
- Gateway nhận trigger → sync ngay không cần chờ 5s

### 2. Log rõ ràng hơn:
Khi sync thành công, Gateway sẽ hiển thị:
```
======================================================================
[SYNC] ✅ DATABASE SYNC COMPLETED SUCCESSFULLY!
[SYNC]    New passkeys are now ready to use
[SYNC]    Current data: 2 passkeys, 0 RFID cards
======================================================================
```

Khi nhận trigger từ web app:
```
======================================================================
[SYNC] 📢 IMMEDIATE SYNC TRIGGERED from web app!
[SYNC]    Fetching latest database updates...
======================================================================
```

## 📝 HƯỚNG DẪN SỬ DỤNG

### Cách 1: Thêm qua Web App (Khuyến nghị)

1. **Mở web app** tại `http://localhost:5000`

2. **Vào trang quản lý Passkey**

3. **Thêm passkey mới** với thông tin:
   - Owner: `00002`
   - Passcode: (nhập mã PIN của bạn, ví dụ: `123456`)
   - Description: Mô tả (ví dụ: "Thao PIN - Personal")
   - Active: ✅ (tick)

4. **Click "Thêm"**

5. **Quan sát terminal đang chạy `gateway_Thao.py`**:
   - Sau 1-2 giây, bạn sẽ thấy message:
     ```
     [SYNC] 📢 IMMEDIATE SYNC TRIGGERED from web app!
     ```
   - Tiếp theo sẽ hiển thị:
     ```
     [SYNC] ✅ DATABASE SYNC COMPLETED SUCCESSFULLY!
     [SYNC]    New passkeys are now ready to use
     ```

6. **Khi thấy message "✅ DATABASE SYNC COMPLETED"** → Passkey đã sẵn sàng!

7. **Nhập passkey từ thiết bị** → Sẽ hoạt động ngay!

### Cách 2: Thêm qua API (Cho developer)

```bash
curl -X POST http://localhost:5000/access/manage_passkey \
  -H "Content-Type: application/json" \
  -d '{
    "action": "add",
    "owner": "00002",
    "passcode": "123456",
    "description": "Test PIN",
    "active": true
  }'
```

Chờ thấy log sync thành công trong terminal gateway.

## 🧪 TEST FLOW HOÀN CHỈNH

Chạy script test tự động:

```bash
cd /run/media/mtu/Thao/Lap_trinh_iot/First_IoT/Physical_Devices/User2/Gateway
python test_passkey_sync.py
```

Script này sẽ:
1. Kiểm tra số passkey hiện tại
2. Thêm passkey mới
3. Chờ sync (6 giây)
4. Kiểm tra xem passkey đã được sync chưa

## ⏱️ THỜI GIAN SYNC

| Tình huống | Thời gian sync |
|-----------|----------------|
| Sync tự động (định kỳ) | Tối đa 5 giây |
| Sync ngay lập tức (có MQTT trigger) | 1-2 giây |
| Khi VPS offline | Chờ đến khi VPS online |

## 🔍 CÁCH KIỂM TRA SYNC

### Kiểm tra Gateway status:
```bash
curl -s "http://47.128.146.122:3000/api/sync/status/Gateway2" | jq .
```

### Kiểm tra database hiện tại:
```bash
curl -s "http://47.128.146.122:3000/api/sync/database/Gateway2" | jq .
```

### Trigger sync thủ công (nếu cần):
```bash
curl -X POST "http://47.128.146.122:3000/api/sync/notify-change/00002"
```

## 🐛 TROUBLESHOOTING

### Vấn đề: Passkey mới vẫn báo sai sau khi thêm

**Nguyên nhân**: Gateway chưa kịp sync

**Giải pháp**:
1. Hãy chờ 5-10 giây sau khi thêm passkey
2. Quan sát log terminal gateway, đợi thấy message "✅ DATABASE SYNC COMPLETED"
3. Sau đó mới nhập passkey từ thiết bị

### Vấn đề: Không thấy log sync trong terminal

**Kiểm tra**:
1. Gateway đang chạy: `ps aux | grep gateway_Thao`
2. VPS API hoạt động: `curl http://47.128.146.122:3000/health`
3. MQTT service hoạt động (xem log gateway khi khởi động)

### Vấn đề: Sync trigger không hoạt động

**Debug**:
1. Kiểm tra Gateway status:
   ```bash
   curl http://47.128.146.122:3000/api/sync/status/Gateway2
   ```
   Đảm bảo `status: "online"`

2. Test trigger thủ công:
   ```bash
   curl -X POST http://47.128.146.122:3000/api/sync/notify-change/00002
   ```

3. Xem response có `"notified": 1` không

## ✨ TIPS

1. **Luôn chờ log sync** trước khi test passkey mới
2. **Định kỳ kiểm tra** Gateway status để đảm bảo online
3. **Backup database** trước khi xóa passkey quan trọng
4. **Dùng description rõ ràng** để dễ quản lý (ví dụ: "Thao Personal PIN - Created 2026-01-08")

## 📊 MONITORING

Gateway hiển thị heartbeat mỗi 30s với thông tin:
```
Heartbeat #123 | Syncs: 45 | Errors: 0 | Local: OK | VPS: OK
```

- **Syncs**: Số lần sync thành công
- **Errors**: Số lần sync lỗi
- **Local**: Kết nối broker local (Mosquitto)
- **VPS**: Kết nối VPS MQTT

---

**Created**: 2026-01-08  
**Author**: Antigravity AI Assistant  
**For**: User2 Gateway (Thao)
