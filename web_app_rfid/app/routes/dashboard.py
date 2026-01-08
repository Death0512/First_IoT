from flask import Blueprint, jsonify, request
from app.db_connect import get_db
from ..utils.helpers import now_iso

dashboard_bp = Blueprint("dashboard", __name__, url_prefix="/dashboard")


@dashboard_bp.get("/overview")
def overview_dashboard():
    conn = get_db()
    cur = conn.cursor()

    cur.execute("SELECT COUNT(*) FROM devices;")
    devices = cur.fetchone()["count"]

    cur.execute("SELECT COUNT(*) FROM passwords;")
    users = cur.fetchone()["count"]

    cur.execute("SELECT COUNT(*) FROM access_logs;")
    logs = cur.fetchone()["count"]

    conn.close()
    return jsonify({
        "devices": devices,
        "users": users,
        "access_logs": logs
    })


@dashboard_bp.get("/temperature")
def temperature_chart():
    """
    Lấy dữ liệu nhiệt độ / độ ẩm cho user hiện tại
    + Trả về dữ liệu theo khoảng thời gian (hours parameter)
    + Có kèm dữ liệu 'hôm nay' (nhiệt độ, độ ẩm, icon)
    """
    user_id = str(request.args.get("user_id", "")).strip()
    device_id_param = str(request.args.get("device_id", "")).strip()
    hours = request.args.get("hours", "24")
    
    try:
        hours = int(hours)
        if hours <= 0:
            hours = 24
    except:
        hours = 24
    
    if not user_id and not device_id_param:
        return jsonify({"ok": False, "error": "missing_user_id_or_device_id"}), 400

    conn = get_db()
    cur = conn.cursor()

    # 1️⃣ Lấy device cảm biến
    if device_id_param:
        device_id = device_id_param
    else:
        cur.execute("""
        SELECT device_id
        FROM user_devices_view
        WHERE user_id = %s AND device_type ILIKE 'temperature%%'
        LIMIT 1;
    """, (user_id,))
    
        dev_row = cur.fetchone()
        if not dev_row:
            conn.close()
            return jsonify({"ok": False, "error": "no_device", "msg": "User không có cảm biến nhiệt độ"}), 404
    
        device_id = dev_row["device_id"]

    # 2️⃣ Lấy dữ liệu theo khoảng thời gian
    cur.execute(f"""
        SELECT time, temperature, humidity
        FROM telemetry
        WHERE device_id = %s
          AND time >= NOW() - INTERVAL '{hours} hours'
        ORDER BY time ASC
    """, (device_id,))
    rows = cur.fetchall()

    if not rows:
        conn.close()
        return jsonify({"ok": False, "error": "no_data"}), 404


    # Latest reading is the last record (most recent)
    latest = rows[-1]
    latest_temp = latest["temperature"]
    latest_hum = latest["humidity"]
    latest_time = latest["time"]

    # 3️⃣ Xác định icon phù hợp (handle None values)
    if latest_temp is None:
        icon = "❓"
    elif latest_temp >= 33:
        icon = "🔥"
    elif latest_temp >= 28:
        icon = "☀️"
    elif latest_temp >= 24:
        icon = "🌤️"
    elif latest_temp >= 20:
        icon = "🌥️"
    else:
        icon = "❄️"

    conn.close()

    # 4️⃣ Trả về dữ liệu đầy đủ
    return jsonify({
        "ok": True,
        "device_id": device_id,
        "latest": {
            "temperature": latest_temp,
            "humidity": latest_hum,
            "time": latest_time.isoformat(),
            "icon": icon
        },
        "chart": [
            {"time": r["time"].isoformat(), "temp": r["temperature"], "hum": r["humidity"]}
            for r in rows  # Đã được sắp xếp ASC, không cần đảo ngược
        ]
    })
