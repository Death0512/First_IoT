
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

SET timezone = 'Asia/Ho_Chi_Minh';
ALTER DATABASE iot_db SET timezone TO 'Asia/Ho_Chi_Minh';

-- Users table
CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    full_name TEXT,
    phone TEXT,
    role TEXT DEFAULT 'client', -- 'owner', 'admin', 'member'
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_active ON users(active);

-- Gateways table
CREATE TABLE IF NOT EXISTS gateways (
    gateway_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    name TEXT,
    location TEXT,
    status TEXT DEFAULT 'offline', -- 'online', 'offline', 'maintenance'
    last_seen TIMESTAMPTZ,
    database_version TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_gateways_user ON gateways(user_id);
CREATE INDEX IF NOT EXISTS idx_gateways_status ON gateways(status);
CREATE INDEX IF NOT EXISTS idx_gateways_heartbeat ON gateways(last_seen);

-- Devices table: ESP8266 devices 
CREATE TABLE IF NOT EXISTS devices (
    device_id TEXT PRIMARY KEY,
    gateway_id TEXT NOT NULL REFERENCES gateways(gateway_id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    device_type TEXT NOT NULL,
    location TEXT,
    communication TEXT, -- 'WiFi', 'LoRa'
    status TEXT DEFAULT 'offline', -- 'online', 'offline'
    last_seen TIMESTAMPTZ, -- Last message received from device
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_devices_gateway ON devices(gateway_id);
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id);
CREATE INDEX IF NOT EXISTS idx_devices_type ON devices(device_type);
CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen);

-- Passwords table: passwords for keypad door access
CREATE TABLE IF NOT EXISTS passwords (
    password_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    hash TEXT NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    last_used TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_passwords_user ON passwords(user_id);
CREATE INDEX IF NOT EXISTS idx_passwords_active ON passwords(active);
CREATE INDEX IF NOT EXISTS idx_passwords_hash ON passwords(hash);

-- RFID cards table: RFID cards for gate access
CREATE TABLE IF NOT EXISTS rfid_cards (
    uid TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    active BOOLEAN DEFAULT TRUE,
    card_type TEXT,
    description TEXT,
    registered_at TIMESTAMPTZ NOT NULL,
    last_used TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    deactivated_at TIMESTAMPTZ,
    deactivation_reason TEXT,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rfid_user ON rfid_cards(user_id);
CREATE INDEX IF NOT EXISTS idx_rfid_active ON rfid_cards(active);

-- Telemetry table: temperature and humidity readings from sensors
CREATE TABLE telemetry (
    time TIMESTAMPTZ NOT NULL, -- Timestamp from gateway, not server
    device_id TEXT NOT NULL,
    gateway_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    metadata JSONB -- Additional sensor data (battery, signal strength, etc.)
);

SELECT create_hypertable('telemetry', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS idx_telemetry_user_time ON telemetry(user_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_device_time ON telemetry(device_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_gateway_time ON telemetry(gateway_id, time DESC);

-- Access logs table: RFID and password access attempts
CREATE TABLE access_logs (
    time TIMESTAMPTZ NOT NULL, -- Timestamp from gateway, not server
    device_id TEXT NOT NULL,
    gateway_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    method TEXT NOT NULL, -- 'rfid', 'passkey', 'remote'
    result TEXT NOT NULL, -- 'granted', 'denied'
    password_id TEXT,
    rfid_uid TEXT,
    deny_reason TEXT, -- Reason for denial if result is 'denied'
    metadata JSONB -- Additional context (source, command_id, etc.)
);

SELECT create_hypertable('access_logs', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS idx_access_logs_user_time ON access_logs(user_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_access_logs_device_time ON access_logs(device_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_access_logs_method ON access_logs(method, time DESC);
CREATE INDEX IF NOT EXISTS idx_access_logs_result ON access_logs(result, time DESC);

-- System logs table: system events, errors, alerts, and device status changes
CREATE TABLE system_logs (
    time TIMESTAMPTZ NOT NULL, -- Timestamp from gateway, not server
    gateway_id TEXT,
    device_id TEXT, -- NULL for gateway-level logs
    user_id TEXT,
    log_type TEXT NOT NULL, -- 'system_event', 'device_event', 'error', 'alert'
    event TEXT NOT NULL, -- Event name: 'device_online', 'device_offline', 'high_temperature', etc.
    severity TEXT NOT NULL, -- 'info', 'warning', 'error', 'critical'
    message TEXT,
    value DOUBLE PRECISION, -- For alerts with threshold values
    threshold DOUBLE PRECISION, -- Threshold that triggered the alert
    metadata JSONB -- Additional event data
);

SELECT create_hypertable('system_logs', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS idx_system_logs_user_time ON system_logs(user_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_system_logs_gateway_time ON system_logs(gateway_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_system_logs_device_time ON system_logs(device_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_system_logs_type ON system_logs(log_type, time DESC);
CREATE INDEX IF NOT EXISTS idx_system_logs_severity ON system_logs(severity, time DESC);
CREATE INDEX IF NOT EXISTS idx_system_logs_event ON system_logs(event);

-- Command logs table: track commands sent to devices
CREATE TABLE command_logs (
    time TIMESTAMPTZ NOT NULL, -- Timestamp when command was sent
    command_id TEXT NOT NULL,
    source TEXT NOT NULL, -- 'client', 'gateway_auto', 'api'
    device_id TEXT NOT NULL,
    gateway_id TEXT NOT NULL,
    user_id TEXT,
    command_type TEXT NOT NULL, -- 'unlock', 'lock', 'fan_on', 'fan_off', 'set_auto', etc.
    status TEXT NOT NULL, -- 'sent', 'executing', 'completed', 'failed'
    params JSONB, -- Command parameters
    result JSONB, -- Command execution result
    completed_at TIMESTAMPTZ,
    metadata JSONB
);

SELECT create_hypertable('command_logs', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS idx_command_logs_device_time ON command_logs(device_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_command_logs_status ON command_logs(status);
CREATE INDEX IF NOT EXISTS idx_command_logs_command_id ON command_logs(command_id);

-- ============================================================================
-- RETENTION POLICIES (Auto-cleanup old data)
-- ============================================================================

-- Keep telemetry data for 90 days
SELECT add_retention_policy('telemetry', INTERVAL '90 days', if_not_exists => TRUE);

-- Keep access logs for 180 days (6 months)
SELECT add_retention_policy('access_logs', INTERVAL '180 days', if_not_exists => TRUE);

-- Keep system logs for 90 days
SELECT add_retention_policy('system_logs', INTERVAL '90 days', if_not_exists => TRUE);

-- Keep command logs for 30 days
SELECT add_retention_policy('command_logs', INTERVAL '30 days', if_not_exists => TRUE);

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View: devices with owner information
CREATE OR REPLACE VIEW user_devices_view AS
SELECT 
    d.device_id,
    d.user_id,
    d.gateway_id,
    d.device_type,
    d.location,
    d.status,
    d.last_seen,
    u.username,
    u.full_name,
    g.name AS gateway_name
FROM devices d
JOIN users u ON d.user_id = u.user_id
JOIN gateways g ON d.gateway_id = g.gateway_id
WHERE u.active = TRUE;

-- View: device health status based on last_seen
CREATE OR REPLACE VIEW device_health_view AS
SELECT 
    d.device_id,
    d.user_id,
    d.device_type,
    d.location,
    d.status,
    d.last_seen,
    EXTRACT(EPOCH FROM (NOW() - d.last_seen))/60 AS minutes_since_seen,
    CASE 
        WHEN d.last_seen IS NULL THEN 'unknown'
        WHEN d.last_seen > NOW() - INTERVAL '5 minutes' THEN 'healthy'
        WHEN d.last_seen > NOW() - INTERVAL '15 minutes' THEN 'warning'
        ELSE 'critical'
    END AS health_status
FROM devices d;

-- ============================================================================
-- PERMISSIONS
-- ============================================================================

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO iot;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO iot;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO iot;

-- ============================================================================
-- SCHEMA MIGRATION COMPLETE
-- ============================================================================

INSERT INTO users (user_id, username, email, password_hash, full_name, phone, role, active, created_at, updated_at)
VALUES ('00001', 'Anh', 'anh@iot.local', '$2b$10$IhIlIxY2od5hr3oJyOcPFOsINCIQpE1xk/pw4oMJJZ1j76DRMGmEK', 'Death', '+84901234567', 'owner', TRUE, NOW(), NOW())
ON CONFLICT (user_id) DO UPDATE SET 
    username = EXCLUDED.username,
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    updated_at = NOW();

INSERT INTO users (user_id, username, email, password_hash, full_name, phone, role, active, created_at, updated_at)
VALUES ('00002', 'Thao', 'thao@iot.local', '$2b$10$hsu4FolYIVI1Qat9e5d5KuHaZXJeFmS9IyQc3tXgnptThex5jYOdG', 'Vuong Linh Thao', '+84901234567', 'owner', TRUE, NOW(), NOW())
ON CONFLICT (user_id) DO UPDATE SET 
    username = EXCLUDED.username,
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    updated_at = NOW();

INSERT INTO users (user_id, username, email, password_hash, full_name, phone, role, active, created_at, updated_at)
VALUES ('00003', 'Tu', 'tu@iot.local', '$2b$10$GO6tbC5XLZWil3clSFi/Heh4.Ij68flzb2HncZLxoZl3Ei7/T0iQK', 'Thai Thi Minh Tu', '+84901234567', 'owner', TRUE, NOW(), NOW())
ON CONFLICT (user_id) DO UPDATE SET 
    username = EXCLUDED.username,
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    updated_at = NOW();

INSERT INTO gateways (gateway_id, user_id, name, location, status, last_seen, database_version, created_at, updated_at)
VALUES ('Gateway1', '00001', 'Main Gate Gateway', 'Building Entrance', 'offline', NOW() - INTERVAL '1 minute', 'v1.0.0', NOW(), NOW()) 
ON CONFLICT (gateway_id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    name = EXCLUDED.name,
    location = EXCLUDED.location,
    updated_at = NOW();

INSERT INTO gateways (gateway_id, user_id, name, location, status, last_seen, database_version, created_at, updated_at)
VALUES ('Gateway2', '00002', 'Door Gateway', 'Apartment', 'offline', NOW() - INTERVAL '1 minute', 'v1.0.0', NOW(), NOW()) 
ON CONFLICT (gateway_id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    name = EXCLUDED.name,
    location = EXCLUDED.location,
    updated_at = NOW();

INSERT INTO gateways (gateway_id, user_id, name, location, status, last_seen, database_version, created_at, updated_at)
VALUES ('Gateway3', '00003', 'Fan Temp Gateway', 'Apartment', 'offline', NOW() - INTERVAL '1 minute', 'v1.0.0', NOW(), NOW()) 
ON CONFLICT (gateway_id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    name = EXCLUDED.name,
    location = EXCLUDED.location,
    updated_at = NOW();

INSERT INTO devices (device_id, gateway_id, user_id, device_type, location, communication, status, last_seen, created_at, updated_at)
VALUES ('rfid_gate_01', 'Gateway1', '00001', 'rfid_gate', 'Main Gate', 'LoRa', 'offline', NOW() - INTERVAL '2 minutes', NOW(), NOW())
ON CONFLICT (device_id) DO UPDATE SET
    gateway_id = EXCLUDED.gateway_id,
    user_id = EXCLUDED.user_id,
    location = EXCLUDED.location,
    updated_at = NOW();

INSERT INTO devices (device_id, gateway_id, user_id, device_type, location, communication, status, last_seen, created_at, updated_at)
VALUES ('passkey_01', 'Gateway2', '00002', 'passkey', 'Front Door', 'Wifi', 'offline', NOW() - INTERVAL '2 minutes', NOW(), NOW())
ON CONFLICT (device_id) DO UPDATE SET
    gateway_id = EXCLUDED.gateway_id,
    user_id = EXCLUDED.user_id,
    location = EXCLUDED.location,
    updated_at = NOW();

INSERT INTO devices (device_id, gateway_id, user_id, device_type, location, communication, status, last_seen, created_at, updated_at)
VALUES ('temp_01', 'Gateway3', '00003', 'temperature sensor', 'Room', 'Wifi', 'offline', NOW() - INTERVAL '2 minutes', NOW(), NOW())
ON CONFLICT (device_id) DO UPDATE SET
    gateway_id = EXCLUDED.gateway_id,
    user_id = EXCLUDED.user_id,
    location = EXCLUDED.location,
    updated_at = NOW();

INSERT INTO devices (device_id, gateway_id, user_id, device_type, location, communication, status, last_seen, created_at, updated_at)
VALUES ('fan_01', 'Gateway3', '00003', 'fan controller', 'Room', 'Wifi', 'offline', NOW() - INTERVAL '2 minutes', NOW(), NOW())
ON CONFLICT (device_id) DO UPDATE SET
    gateway_id = EXCLUDED.gateway_id,
    user_id = EXCLUDED.user_id,
    location = EXCLUDED.location,
    updated_at = NOW();

INSERT INTO rfid_cards (uid, user_id, active, card_type, description, registered_at, last_used, expires_at, deactivated_at, deactivation_reason, updated_at)
VALUES ('8675f205', '00001', TRUE, 'MIFARE Classic', 'Thai Thi Minh Tu - Main Card', NOW() - INTERVAL '30 days', NOW() - INTERVAL '1 hour', NULL, NULL, NULL, NOW())
ON CONFLICT (uid) DO UPDATE SET
    active = EXCLUDED.active,
    description = EXCLUDED.description,
    last_used = EXCLUDED.last_used,
    updated_at = NOW();

INSERT INTO passwords (password_id, user_id, hash, active, description, created_at, last_used, expires_at, updated_at)
VALUES ('passwd_00002_001', '00002', '9dc3bece812e7e35fcf534ea2191d969794e8a6c394613bf96c4a468eff062a7', TRUE, 'Vuong Linh Thao PIN - 251203', NOW() - INTERVAL '30 days', NOW() - INTERVAL '3 hours', NULL, NOW())
ON CONFLICT (password_id) DO UPDATE SET
    active = EXCLUDED.active,
    last_used = EXCLUDED.last_used,
    updated_at = NOW();

INSERT INTO telemetry (time, device_id, gateway_id, user_id, temperature, humidity, metadata)
SELECT
    gs AS time,
    'temp_01',
    'Gateway3',
    '00003',
    ROUND((23.5 + 4.0 * SIN(EXTRACT(HOUR FROM gs) * PI() / 12) + 2.0 * SIN(EXTRACT(DOW FROM gs) * PI() / 3.5) + RANDOM() * 1.2)::NUMERIC, 2)::DOUBLE PRECISION,
    ROUND((68.0 - 20.0 * SIN(EXTRACT(HOUR FROM gs) * PI() / 12) + RANDOM() * 6)::NUMERIC, 1)::DOUBLE PRECISION,
    JSONB_BUILD_OBJECT(
        'battery', ROUND((95.0 - EXTRACT(EPOCH FROM (NOW() - gs))/86400 * 0.08 - RANDOM()*2)::NUMERIC, 1),
        'rssi', -45 - (RANDOM() * 25)::INT,
        'uptime_sec', (EXTRACT(EPOCH FROM (NOW() - gs)) / 600)::BIGINT * 600
    )
FROM GENERATE_SERIES(
    '2025-08-08 00:00:00+07'::TIMESTAMPTZ,
    '2025-11-06 23:50:00+07'::TIMESTAMPTZ,
    '10 minutes'::INTERVAL
) AS t(gs);

-- ========================================================================
-- 2. ACCESS LOGS — USER 00001: RFID (ra/vào nhà)
-- ========================================================================
WITH trips AS (
    SELECT
        d::DATE + MAKE_INTERVAL(
            HOURS => (7 + FLOOR(RANDOM()*2) + CASE WHEN RANDOM() < 0.5 THEN 11 ELSE 0 END)::INT,
            MINS => (RANDOM()*30)::INT
        ) AS time
    FROM GENERATE_SERIES('2025-08-08'::DATE, '2025-11-06'::DATE, '1 day') d
    CROSS JOIN GENERATE_SERIES(1, 2 + (RANDOM()*3)::INT)
)
INSERT INTO access_logs (time, device_id, gateway_id, user_id, method, result, rfid_uid, metadata)
SELECT
    time,
    'rfid_gate_01', 'Gateway1', '00001', 'rfid',
    CASE WHEN RANDOM() < 0.98 THEN 'granted' ELSE 'denied' END,
    CASE WHEN RANDOM() < 0.98 THEN '8675F205' ELSE '00000000' END,
    JSONB_BUILD_OBJECT('source', 'rfid_reader')
FROM trips;

-- ========================================================================
-- 3. ACCESS LOGS — USER 00002: PASSKEY (phòng riêng)
-- ========================================================================
WITH pins AS (
    SELECT
        d::DATE + MAKE_INTERVAL(
            HOURS => (8 + FLOOR(RANDOM()*14))::INT,
            MINS => (RANDOM()*40)::INT
        ) AS time
    FROM GENERATE_SERIES('2025-08-08'::DATE, '2025-11-06'::DATE, '1 day') d
    CROSS JOIN GENERATE_SERIES(1, 6 + (RANDOM()*4)::INT)
)
INSERT INTO access_logs (time, device_id, gateway_id, user_id, method, result, password_id, deny_reason, metadata)
SELECT
    time,
    'passkey_01', 'Gateway2', '00002', 'passkey',
    CASE WHEN RANDOM() < 0.94 THEN 'granted' ELSE 'denied' END,
    CASE WHEN RANDOM() < 0.94 THEN 'passwd_00002_001' ELSE NULL END,
    CASE WHEN RANDOM() > 0.94 THEN 'invalid_password' ELSE NULL END,
    JSONB_BUILD_OBJECT('source', 'keypad', 'attempts', 1)
FROM pins;

-- ========================================================================
-- 4. COMMAND LOGS — ĐÃ ÉP KIỂU RÕ RÀNG
-- ========================================================================
INSERT INTO command_logs (time, command_id, source, device_id, gateway_id, user_id, command_type, status, params, completed_at, result, metadata)
SELECT * FROM (VALUES
    ('2025-09-15 07:25:00+07'::TIMESTAMPTZ, 'cmd_gate_001', 'client', 'rfid_gate_01', 'Gateway1', '00001', 'remote_unlock', 'completed',
     '{"duration": 7000}'::JSONB, '2025-09-15 07:25:03+07'::TIMESTAMPTZ, '{"success": true}'::JSONB, '{"app": "iOS"}'::JSONB),

    ('2025-10-02 19:45:00+07'::TIMESTAMPTZ, 'cmd_door_001', 'client', 'passkey_01', 'Gateway2', '00002', 'remote_unlock', 'completed',
     '{"duration": 5000}'::JSONB, '2025-10-02 19:45:02+07'::TIMESTAMPTZ, '{"success": true}'::JSONB, '{"app": "Android"}'::JSONB),

    ('2025-08-20 14:30:00+07'::TIMESTAMPTZ, 'cmd_fan_001', 'gateway_auto', 'fan_01', 'Gateway3', '00003', 'set_fan', 'completed',
     '{"state": "on", "speed": 80}'::JSONB, '2025-08-20 14:30:01+07'::TIMESTAMPTZ, '{"rpm": 2200}'::JSONB, '{"trigger": "temp"}'::JSONB),

    ('2025-11-01 22:00:00+07'::TIMESTAMPTZ, 'cmd_auto_001', 'client', 'fan_01', 'Gateway3', '00003', 'set_auto', 'completed',
     '{"mode": "temperature"}'::JSONB, '2025-11-01 22:00:01+07'::TIMESTAMPTZ, '{"success": true}'::JSONB, '{"rule": "temp>29"}'::JSONB)
) AS v(time, command_id, source, device_id, gateway_id, user_id, command_type, status, params, completed_at, result, metadata);

-- ========================================================================
-- 5. SYSTEM LOGS — ĐÃ ÉP KIỂU
-- ========================================================================
INSERT INTO system_logs (time, gateway_id, device_id, user_id, log_type, event, severity, message, value, threshold, metadata)
SELECT * FROM (VALUES
    ('2025-08-13 03:00:00+07'::TIMESTAMPTZ, 'Gateway1', NULL, '00001', 'system_event', 'gateway_reboot', 'info', 'Weekly reboot', NULL, NULL, '{"reason": "scheduled"}'::JSONB),
    ('2025-08-25 15:20:00+07'::TIMESTAMPTZ, 'Gateway3', 'temp_01', '00003', 'alert', 'temperature_threshold', 'warning', 'Phòng quá nóng', 32.1, 30.0, '{"auto_fan": true}'::JSONB),
    ('2025-10-30 08:00:00+07'::TIMESTAMPTZ, 'Gateway3', 'temp_01', '00003', 'alert', 'low_battery', 'warning', 'Pin cảm biến yếu', 14.2, 20.0, '{"replace_by": "2025-11-15"}'::JSONB)
) AS v(time, gateway_id, device_id, user_id, log_type, event, severity, message, value, threshold, metadata);

-- ========================================================================
-- 6. 50 LỆNH NGẪU NHIÊN — ĐÃ ÉP KIỂU
-- ========================================================================
INSERT INTO command_logs (time, command_id, source, device_id, gateway_id, user_id, command_type, status, params, completed_at, result, metadata)
SELECT
    gs,
    'cmd_' || MD5(RANDOM()::TEXT),
    CASE WHEN RANDOM() < 0.8 THEN 'client' ELSE 'gateway_auto' END,
    CASE WHEN RANDOM() < 0.4 THEN 'rfid_gate_01' WHEN RANDOM() < 0.8 THEN 'passkey_01' ELSE 'fan_01' END,
    CASE WHEN RANDOM() < 0.4 THEN 'Gateway1' WHEN RANDOM() < 0.8 THEN 'Gateway2' ELSE 'Gateway3' END,
    CASE WHEN RANDOM() < 0.4 THEN '00001' WHEN RANDOM() < 0.8 THEN '00002' ELSE '00003' END,
    CASE WHEN RANDOM() < 0.6 THEN 'remote_unlock' WHEN RANDOM() < 0.9 THEN 'set_fan' ELSE 'set_auto' END,
    'completed',
    CASE WHEN RANDOM() < 0.6 THEN JSONB_BUILD_OBJECT('duration', 5000 + (RANDOM()*3000)::INT)
         ELSE JSONB_BUILD_OBJECT('state', CASE WHEN RANDOM() < 0.5 THEN 'on' ELSE 'off' END) END,
    gs + INTERVAL '2 seconds',
    '{"success": true}'::JSONB,
    JSONB_BUILD_OBJECT('source_ip', '192.168.1.' || (10 + (RANDOM()*20)::INT))
FROM GENERATE_SERIES(
    '2025-08-08 06:00:00+07'::TIMESTAMPTZ,
    '2025-11-06 23:00:00+07'::TIMESTAMPTZ,
    '4 hours'::INTERVAL * RANDOM()
) gs
LIMIT 50;