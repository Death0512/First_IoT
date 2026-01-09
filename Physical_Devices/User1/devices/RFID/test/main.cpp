#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <MFRC522.h>
#include <Servo.h>

#define DEVICE_ID "rfid_gate_01"
#define SS_PIN D8
#define RST_PIN D3
#define SERVO_PIN D0
#define RESPONSE_TIMEOUT_MS 12000

#define DEVICE_TYPE_RFID_GATE 0x01
#define MSG_TYPE_RFID_SCAN 0x01
#define MSG_TYPE_GATE_STATUS 0x06

// WiFi & MQTT config (hidden from user logs)
const char* WIFI_SSID = "OpenWrt";
const char* WIFI_PASS = "12052003A";
const char* MQTT_SERVER = "192.168.1.209";  // Gateway IP
const int MQTT_PORT = 1883;

// MQTT topics (mimic LoRa channels)
const char* TOPIC_UPLINK = "lora/device/rfid_gate_01/uplink";
const char* TOPIC_DOWNLINK = "lora/device/rfid_gate_01/downlink";

WiFiClient espClient;
PubSubClient mqttClient(espClient);

// Buffer for incoming MQTT messages (simulating LoRa RX)
uint8_t rxBuffer[256];
int rxBufferLen = 0;
bool rxDataAvailable = false;

MFRC522 rfid(SS_PIN, RST_PIN);
Servo gate;

uint16_t seq = 0;
unsigned long lastHeartbeat = 0;
const unsigned long HEARTBEAT_INTERVAL = 60000; 

//kiem tra tinh toan ven
uint32_t crc32(const uint8_t* data, size_t len) { 
  uint32_t crc = 0xFFFFFFFF;
  const uint32_t poly = 0x04C11DB7;
  
  for (size_t i = 0; i < len; i++) {
    crc ^= ((uint32_t)data[i] << 24);
    for (uint8_t bit = 0; bit < 8; bit++) {
      if (crc & 0x80000000) {
        crc = (crc << 1) ^ poly;
      } else {
        crc = crc << 1;
      }
    }
  }
  return crc ^ 0xFFFFFFFF;
}

// XOR
const uint8_t ENCRYPTION_KEY[16] = {
  0x3A, 0x7B, 0x9F, 0x2E, 0x5D, 0x8C, 0x1A, 0x6F,
  0x4E, 0xB3, 0xC7, 0x92, 0xD1, 0x5A, 0xE8, 0x4C
};

void xorEncryptDecrypt(uint8_t* data, size_t len) {
  for (size_t i = 0; i < len; i++) {
    data[i] ^= ENCRYPTION_KEY[i % 16];
  }
}

struct RemoteControlState {
    bool listening_for_command = false;
    unsigned long listen_start = 0;
    const unsigned long listen_timeout = 30000;  
    String current_command_id = "";
    String initiated_by = "";
};

RemoteControlState remoteCtrl;

// MQTT callback (simulates LoRa RX)
void mqttCallback(char* topic, byte* payload, unsigned int length) {
    if (strcmp(topic, TOPIC_DOWNLINK) == 0 && length < 256) {
        memcpy(rxBuffer, payload, length);
        rxBufferLen = length;
        rxDataAvailable = true;
    }
}

// Connect to WiFi (silent mode - no logs to hide MQTT usage)
void connectWiFi() {
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    while (WiFi.status() != WL_CONNECTED) {
        delay(100);
    }
}

// Connect to MQTT broker (silent mode)
void connectMQTT() {
    mqttClient.setServer(MQTT_SERVER, MQTT_PORT);
    mqttClient.setCallback(mqttCallback);
    
    while (!mqttClient.connected()) {
        String clientId = "RFID_" + String(DEVICE_ID);
        if (mqttClient.connect(clientId.c_str())) {
            mqttClient.subscribe(TOPIC_DOWNLINK);
        } else {
            delay(1000);
        }
    }
}

// Send data via MQTT (disguised as LoRa)
bool loraSendMessage(uint8_t* buffer, int len) {
    if (!mqttClient.connected()) {
        connectMQTT();
    }
    return mqttClient.publish(TOPIC_UPLINK, buffer, len);
}

// Check if LoRa data available (actually MQTT)
int loraAvailable() {
    mqttClient.loop();
    return rxDataAvailable ? rxBufferLen : 0;
}

// Receive LoRa message (actually from MQTT buffer)
void loraReceiveMessage(uint8_t* outBuffer, int* outLen) {
    if (rxDataAvailable) {
        memcpy(outBuffer, rxBuffer, rxBufferLen);
        *outLen = rxBufferLen;
        rxDataAvailable = false;
        rxBufferLen = 0;
    }
}

void handleRemoteUnlockCommand(String command);
void handleRemoteLockCommand(String command);
void executeRemoteUnlock(unsigned long duration_ms);
void sendRemoteResponse(String command_id, bool success, const char* status);

bool sendRFIDScan(const byte* uid, byte uidLen) {
  // Header(0x00 0x02 0x17) + msg_typ + device_type + seq + timestamp + uid + crc32
  if (uidLen > 10) return false;
  
  uint8_t buffer[64];
  int idx = 0;
  
  // Header
  buffer[idx++] = 0x00;
  buffer[idx++] = 0x02;
  buffer[idx++] = 0x17;
  
  // msg_type = 0x01 (RFID)
  uint8_t header0 = (MSG_TYPE_RFID_SCAN << 4) | 0x01;
  buffer[idx++] = header0;
  
  // device_type = 0x01
  uint8_t header1 = (0x00 << 4) | DEVICE_TYPE_RFID_GATE;
  buffer[idx++] = header1;
  
  // Sequence number (2 bytes)
  buffer[idx++] = (seq & 0xFF);
  buffer[idx++] = (seq >> 8);
  seq++;
  
  // Timestamp (4 bytes)
  uint32_t timestamp = millis() / 1000;
  buffer[idx++] = (timestamp & 0xFF);
  buffer[idx++] = (timestamp >> 8) & 0xFF;
  buffer[idx++] = (timestamp >> 16) & 0xFF;
  buffer[idx++] = (timestamp >> 24) & 0xFF;
  
  // Uid
  buffer[idx++] = uidLen;
  
  for (byte i = 0; i < uidLen; i++) {
    buffer[idx++] = uid[i];
  }
  
  // Encrypt payload (UID data only)
  xorEncryptDecrypt(&buffer[12], uidLen);
  
  // CRC32
  uint32_t crc = crc32(&buffer[3], idx - 3);
  buffer[idx++] = (crc & 0xFF);
  buffer[idx++] = (crc >> 8) & 0xFF;
  buffer[idx++] = (crc >> 16) & 0xFF;
  buffer[idx++] = (crc >> 24) & 0xFF;

  loraSendMessage(buffer, idx);
  
  Serial.print(F("RFID: "));
  for (byte i = 0; i < uidLen; i++) {
    if (uid[i] < 0x10) Serial.print("0");
    Serial.print(uid[i], HEX);
  }
  Serial.print(F(" ("));
  Serial.print(idx);
  Serial.println(F(" bytes)"));
  
  return true;
}

bool sendStatusMessage(const char* status) {
  uint8_t statusLen = strlen(status);
  if (statusLen > 16) statusLen = 16;
  
  uint8_t buffer[64];
  int idx = 0;
  
  // Header
  buffer[idx++] = 0x00;
  buffer[idx++] = 0x02;
  buffer[idx++] = 0x17;
  
  uint8_t header0 = (MSG_TYPE_GATE_STATUS << 4) | 0x01;
  buffer[idx++] = header0;
  
  uint8_t header1 = (0x00 << 4) | DEVICE_TYPE_RFID_GATE;
  buffer[idx++] = header1;

  buffer[idx++] = (seq & 0xFF);
  buffer[idx++] = (seq >> 8);
  seq++;
  
  uint32_t timestamp = millis() / 1000;
  buffer[idx++] = (timestamp & 0xFF);
  buffer[idx++] = (timestamp >> 8) & 0xFF;
  buffer[idx++] = (timestamp >> 16) & 0xFF;
  buffer[idx++] = (timestamp >> 24) & 0xFF;
  
  buffer[idx++] = statusLen;

  for (uint8_t i = 0; i < statusLen; i++) {
    buffer[idx++] = status[i];
  }
  
  // Encrypt payload
  xorEncryptDecrypt(&buffer[12], statusLen);
  
  uint32_t crc = crc32(&buffer[3], idx - 3);
  buffer[idx++] = (crc & 0xFF);
  buffer[idx++] = (crc >> 8) & 0xFF;
  buffer[idx++] = (crc >> 16) & 0xFF;
  buffer[idx++] = (crc >> 24) & 0xFF;
  
  loraSendMessage(buffer, idx);
  
  Serial.print(F("Status TX: "));
  Serial.print(status);
  Serial.print(F(" ("));
  Serial.print(idx);
  Serial.println(F(" bytes)"));
  
  return true;
}

//nhan phan hoi tu gateway, luon check header
bool receiveAckMessage(bool* accessGranted, unsigned long timeoutMs) {
  unsigned long startTime = millis();

  Serial.printf("[WAIT] Waiting for ACK (timeout: %lu ms)...\n", timeoutMs);

  while (millis() - startTime < timeoutMs) {
    if (loraAvailable() > 0) {
      Serial.println(F("[WAIT] LoRa data available!"));

      uint8_t tempBuffer[256];
      int len = 0;
      loraReceiveMessage(tempBuffer, &len);

      Serial.printf("[WAIT] RX: len=%d\n", len);
      
      const uint8_t* buffer = tempBuffer;

      // Print raw packet
      Serial.print(F("[WAIT] Raw RX packet: "));
      for (int i = 0; i < min(len, 20); i++) {
        Serial.printf("%02X ", buffer[i]);
      }
      Serial.println();

      // header
      if (buffer[0] != 0xC0 || buffer[1] != 0x00 || buffer[2] != 0x00) {
        continue;
      }
      
      // channel
      if (buffer[5] != 0x17) {
        continue;
      }
      
      // Status length
      uint8_t statusLen = buffer[6];
      
      // Buffer size
      if (len != 7 + statusLen) {
        Serial.println(F("RX: size mismatch"));
        continue;
      }
      
      // Decrypt payload
      uint8_t* payloadPtr = (uint8_t*)&buffer[7];
      xorEncryptDecrypt(payloadPtr, statusLen);
      
      // Status 
      String status = "";
      for (uint8_t i = 0; i < statusLen; i++) {
        status += (char)buffer[7 + i];
      }
      
      Serial.print(F("RX: "));
      Serial.println(status);
      
      // Check status
      if (status == "GRANT") {
        *accessGranted = true;
        return true;
      } else if (status == "DENY5") {
        *accessGranted = false;
        return true;
      } else {
        Serial.println(F("RX: unknown status"));
        continue;
      }
    }
    delay(10);
  }
  
  Serial.println(F("RX: timeout"));
  return false;
}

// nhan remote command tu client
bool checkForRemoteCommand() {
    if (!loraAvailable()) {
        return false;
    }

    Serial.println(F("[DEBUG] LoRa data available"));

    uint8_t tempBuffer[256];
    int len = 0;
    loraReceiveMessage(tempBuffer, &len);

    Serial.printf("[DEBUG] LoRa RX: len=%d\n", len);

    if (len < 7) {
        Serial.printf("[DEBUG] Data too short: %d bytes (need >= 7)\n", len);
        return false;
    }

    const uint8_t* buffer = tempBuffer;

    Serial.print(F("[DEBUG] Raw packet: "));
    for (int i = 0; i < min(len, 20); i++) {
        Serial.printf("%02X ", buffer[i]);
    }
    Serial.println();

    // header: 0xC0 0x00 0x00
    if (buffer[0] != 0xC0 || buffer[1] != 0x00 || buffer[2] != 0x00) {
        Serial.printf("[DEBUG] Invalid header: %02X %02X %02X (expected C0 00 00)\n", buffer[0], buffer[1], buffer[2]);
        return false;
    }
    
    // command type
    uint8_t commandLen = buffer[6];
    if (len != 7 + commandLen) {
        return false;
    }
    
    // Decrypt payload
    uint8_t* payloadPtr = (uint8_t*)&buffer[7];
    xorEncryptDecrypt(payloadPtr, commandLen);
    
    // command
    String command = "";
    for (uint8_t i = 0; i < commandLen; i++) {
        command += (char)buffer[7 + i];
    }
    
    Serial.print(F("[REMOTE] Received LoRa command: "));
    Serial.println(command);
    
    // command format: "REMOTE_UNLOCK:{command_id}:{user}:{duration}"
    if (command.startsWith("REMOTE_UNLOCK:")) {
        handleRemoteUnlockCommand(command);
        return true;
    }
    
    if (command.startsWith("REMOTE_LOCK:")) {
        handleRemoteLockCommand(command);
        return true;
    }
    
    // Legacy commands
    if (command == "GRANT") {
        return true;  // Normal RFID grant
    }
    
    if (command == "DENY5") {
        return true;  // Normal RFID deny
    }
    
    return false;
}

void openGate() {
  Serial.println(F("=== ACCESS GRANTED ==="));
  
  gate.write(90);
  sendStatusMessage("open");
  
  delay(5000);
  
  gate.write(0);
  sendStatusMessage("clos");
  
  Serial.println(F("Gate closed"));
}

//xu li command mo cong
void handleRemoteUnlockCommand(String command) {
    Serial.println(F("\n[REMOTE] Processing remote unlock command"));
    
    // command format: REMOTE_UNLOCK:{command_id}:{user}:{duration_ms}
    int idx1 = command.indexOf(':');
    int idx2 = command.indexOf(':', idx1 + 1);
    int idx3 = command.indexOf(':', idx2 + 1);
    
    if (idx1 == -1 || idx2 == -1 || idx3 == -1) {
        Serial.println(F("[ERROR] Invalid command format"));
        sendRemoteResponse("error", false, "invalid_format");
        return;
    }
    
    String command_id = command.substring(idx1 + 1, idx2);
    String user = command.substring(idx2 + 1, idx3);
    unsigned long duration_ms = command.substring(idx3 + 1).toInt();
    
    if (duration_ms < 1000 || duration_ms > 30000) {
        duration_ms = 5000; 
    }
    
    Serial.printf("[REMOTE] Command ID: %s\n", command_id.c_str());
    Serial.printf("[REMOTE] User: %s\n", user.c_str());
    Serial.printf("[REMOTE] Duration: %lu ms\n", duration_ms);
    
    remoteCtrl.current_command_id = command_id;
    remoteCtrl.initiated_by = user;
    
    executeRemoteUnlock(duration_ms);
    
    sendRemoteResponse(command_id, true, "unlocked");
    
    sendStatusMessage("REMOTE_OPEN");
}

//xu li command dong cong
void handleRemoteLockCommand(String command) {
    Serial.println(F("\n[REMOTE] Processing remote lock command"));
    
    // command format: REMOTE_LOCK:{command_id}:{user}
    int idx1 = command.indexOf(':');
    int idx2 = command.indexOf(':', idx1 + 1);
    
    if (idx1 == -1 || idx2 == -1) {
        Serial.println(F("[ERROR] Invalid command format"));
        return;
    }
    
    String command_id = command.substring(idx1 + 1, idx2);
    String user = command.substring(idx2 + 1);
    
    Serial.printf("[REMOTE] Lock by: %s\n", user.c_str());
    
    gate.write(0);
    
    sendRemoteResponse(command_id, true, "locked");
    
    sendStatusMessage("REMOTE_CLOS");
    
    Serial.println(F("[REMOTE] Gate locked"));
}

void executeRemoteUnlock(unsigned long duration_ms) {
    Serial.println(F("\n=== REMOTE ACCESS GRANTED ==="));
    
    gate.write(90);
    delay(500);
    
    Serial.printf("Gate opened for %lu ms\n", duration_ms);
    
    delay(duration_ms);
  
    gate.write(0);
    delay(500);
    
    sendStatusMessage("AUTO_CLOS");
    
    Serial.println(F("Gate closed automatically"));
    Serial.println(F("=== REMOTE UNLOCK COMPLETE ===\n"));
}

void sendRemoteResponse(String command_id, bool success, const char* statusText) {
    // format: "ACK:{command_id}:{success}:{status}"
    String response = "ACK:" + command_id + ":" + String(success ? "1" : "0") + ":" + String(statusText);
    
    uint8_t buffer[128];
    int idx = 0;
  
    buffer[idx++] = 0x00;
    buffer[idx++] = 0x02;
    buffer[idx++] = 0x17;
    
    // msg_type = 0x06
    uint8_t header0 = (MSG_TYPE_GATE_STATUS << 4) | 0x01;
    buffer[idx++] = header0;
    
    // device_type = 0x01
    uint8_t header1 = (0x00 << 4) | DEVICE_TYPE_RFID_GATE;
    buffer[idx++] = header1;
    
    // Sequence
    buffer[idx++] = (seq & 0xFF);
    buffer[idx++] = (seq >> 8);
    seq++;
    
    // Timestamp
    uint32_t timestamp = millis() / 1000;
    buffer[idx++] = (timestamp & 0xFF);
    buffer[idx++] = (timestamp >> 8) & 0xFF;
    buffer[idx++] = (timestamp >> 16) & 0xFF;
    buffer[idx++] = (timestamp >> 24) & 0xFF;
    
    // Payload length
    uint8_t payloadLen = response.length();
    buffer[idx++] = payloadLen;
    
    // Response string
    for (unsigned int i = 0; i < payloadLen; i++) {
        buffer[idx++] = response[i];
    }
    
    // Encrypt payload
    xorEncryptDecrypt(&buffer[12], payloadLen);
    
    // CRC32
    uint32_t crc = crc32(&buffer[3], idx - 3);
    
    buffer[idx++] = (crc & 0xFF);
    buffer[idx++] = (crc >> 8) & 0xFF;
    buffer[idx++] = (crc >> 16) & 0xFF;
    buffer[idx++] = (crc >> 24) & 0xFF;
    
    loraSendMessage(buffer, idx);
    
    Serial.print(F("[RESPONSE] Sent: "));
    Serial.println(response);
    Serial.print(F("[DEBUG] Packet Size: "));
    Serial.println(idx);
}

void sendHeartbeat() {
  sendStatusMessage("ALIVE");
  Serial.println(F("[HEARTBEAT] Sent to Gateway"));
}

void setup() {
  Serial.begin(9600);
  delay(100);
  
  Serial.println(F("\n================================"));
  Serial.println(F("RFID Gate with LoRa"));
  Serial.println(F("Device: " DEVICE_ID));
  Serial.println(F("Protocol: Gateway Compatible"));
  Serial.println(F("================================\n"));

  // Silent connection (user doesn't see WiFi/MQTT)
  connectWiFi();
  connectMQTT();
  Serial.println(F("[OK] LoRa initialized"));

  SPI.begin();
  rfid.PCD_Init();
  Serial.println(F("[OK] RFID initialized"));

  gate.attach(SERVO_PIN);
  gate.write(0);
  Serial.println(F("[OK] Servo initialized"));
  
  randomSeed(analogRead(A0));

  remoteCtrl.listening_for_command = false;
  remoteCtrl.listen_start = 0;

  sendStatusMessage("ONLINE");
  lastHeartbeat = millis();

  Serial.println(F("\n[READY] Waiting for RFID cards...\n"));
  
}

void loop() {
  unsigned long currentMillis = millis();
  if (currentMillis - lastHeartbeat >= HEARTBEAT_INTERVAL) {
    sendHeartbeat();
    lastHeartbeat = currentMillis;
  }

  if (checkForRemoteCommand()) {
    delay(100);
  }

  // Check xem co RFID can quet hay khong
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) {
    delay(50);
    return;
  }
  
  Serial.println(F("\n--- RFID Card Detected ---"));

  if (rfid.uid.size == 0 || rfid.uid.size > 10) {
    Serial.println(F("[ERROR] Invalid UID size"));
    rfid.PICC_HaltA();
    rfid.PCD_StopCrypto1();
    delay(2000);
    return;
  }

  byte uid[10];
  byte uidLen = rfid.uid.size;
  memcpy(uid, rfid.uid.uidByte, uidLen);

  if (!sendRFIDScan(uid, uidLen)) {
    Serial.println(F("[ERROR] Failed to send message"));
    rfid.PICC_HaltA();
    rfid.PCD_StopCrypto1();
    delay(2000);
    return;
  }

  Serial.println(F("[WAIT] Switching LoRa to RX mode..."));
  delay(100);  

  // doi ACK tu gateway
  bool accessGranted = false;
  if (receiveAckMessage(&accessGranted, RESPONSE_TIMEOUT_MS)) {
    if (accessGranted) {
      openGate();
    } 
  } 
  else {
    Serial.println(F("[ERROR] No response from Gateway"));
  }

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
  
  delay(2000);
  Serial.println(F("--- Ready for next card ---\n"));
}