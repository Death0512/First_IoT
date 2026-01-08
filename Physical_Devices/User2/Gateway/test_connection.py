#!/usr/bin/env python3
"""Test script to diagnose NetworkError issues"""

import requests
import ssl
import paho.mqtt.client as mqtt
import json
import sys

print("="*70)
print("TESTING USER2 CONNECTIONS")
print("="*70)

# Test 1: VPS API Connection
print("\n[TEST 1] Testing VPS API Connection...")
try:
    url = "http://47.128.146.122:3000/api/sync/database/Gateway2"
    response = requests.get(url, timeout=10)
    print(f"✅ VPS API Response: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"   Version: {data.get('version')}")
        print(f"   Passwords: {data.get('stats', {}).get('passwords_count', 0)}")
except requests.exceptions.ConnectionError as e:
    print(f"❌ VPS API Connection Error: {e}")
    sys.exit(1)
except requests.exceptions.Timeout as e:
    print(f"❌ VPS API Timeout: {e}")
    sys.exit(1)
except Exception as e:
    print(f"❌ VPS API Error: {e}")
    sys.exit(1)

# Test 2: VPS MQTT Broker Connection
print("\n[TEST 2] Testing VPS MQTT Broker Connection...")
vps_connected = False

def on_vps_connect(client, userdata, flags, rc):
    global vps_connected
    if rc == 0:
        print("✅ VPS MQTT Broker Connected Successfully!")
        vps_connected = True
    else:
        print(f"❌ VPS MQTT Broker Connection Failed: rc={rc}")

vps_client = mqtt.Client(client_id="Gateway2_test_vps")
vps_client.on_connect = on_vps_connect

try:
    vps_client.tls_set(
        ca_certs='./certs/ca.cert.pem',
        certfile='./certs/gateway2.cert.pem',
        keyfile='./certs/gateway2.key.pem',
        cert_reqs=ssl.CERT_REQUIRED,
        tls_version=ssl.PROTOCOL_TLSv1_2
    )
    vps_client.connect('47.128.146.122', 8883, 60)
    vps_client.loop_start()
    
    import time
    time.sleep(3)
    
    if not vps_connected:
        print("❌ VPS MQTT: Connection timeout")
        sys.exit(1)
        
    vps_client.loop_stop()
    vps_client.disconnect()
    
except FileNotFoundError as e:
    print(f"❌ VPS MQTT: Certificate file not found: {e}")
    sys.exit(1)
except Exception as e:
    print(f"❌ VPS MQTT Error: {e}")
    sys.exit(1)

# Test 3: Local Mosquitto Broker Connection
print("\n[TEST 3] Testing Local Mosquitto Broker Connection...")
local_connected = False

def on_local_connect(client, userdata, flags, rc):
    global local_connected
    if rc == 0:
        print("✅ Local Mosquitto Broker Connected Successfully!")
        local_connected = True
    else:
        print(f"❌ Local Mosquitto Broker Connection Failed: rc={rc}")

local_client = mqtt.Client(client_id="Gateway2_test_local")
local_client.on_connect = on_local_connect

try:
    local_client.tls_set(
        ca_certs='./certs/ca.cert.pem',
        certfile='./certs/gateway2.cert.pem',
        keyfile='./certs/gateway2.key.pem',
        cert_reqs=ssl.CERT_REQUIRED,
        tls_version=ssl.PROTOCOL_TLSv1_2
    )
    local_client.username_pw_set(username='Gateway2', password='125')
    local_client.connect('192.168.1.209', 1884, 60)
    local_client.loop_start()
    
    time.sleep(3)
    
    if not local_connected:
        print("❌ Local Mosquitto: Connection timeout")
        sys.exit(1)
        
    local_client.loop_stop()
    local_client.disconnect()
    
except FileNotFoundError as e:
    print(f"❌ Local Mosquitto: Certificate file not found: {e}")
    sys.exit(1)
except Exception as e:
    print(f"❌ Local Mosquitto Error: {e}")
    sys.exit(1)

print("\n" + "="*70)
print("✅ ALL TESTS PASSED - No NetworkError detected!")
print("="*70)
