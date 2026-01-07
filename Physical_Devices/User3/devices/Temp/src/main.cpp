#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <LiquidCrystal_I2C.h>
#include <time.h>

// WiFi credentials
const char* ssid = "OpenWrt";
const char* wifiPass = "12052003A";

// MQTT config
const char* mqtt_host = "192.168.1.209";
const uint16_t mqtt_port = 1884;

const char* device_id = "temp_01";
const char* topic_telemetry = "home/devices/temp_01/telemetry";
const char* topic_status = "home/devices/temp_01/status";

const char* mqtt_username = "temp_01";
const char* mqtt_password = "125";

const char root_ca_pem[] = R"EOF(
-----BEGIN CERTIFICATE-----
MIIDDTCCAfWgAwIBAgIUS+E+kpfVG7IekecE4wEelNVnRDowDQYJKoZIhvcNAQEL
BQAwFjEUMBIGA1UEAwwLSW9UX0NBXzIwMjYwHhcNMjYwMTA3MTU0MjM0WhcNMzYw
MTA1MTU0MjM0WjAWMRQwEgYDVQQDDAtJb1RfQ0FfMjAyNjCCASIwDQYJKoZIhvcN
AQEBBQADggEPADCCAQoCggEBAKq5lFe1rNEvbCaa7XKehwAy52i4o1YkcD5Alxro
FLhtVfOEt+jUUHaG0TCnL9KFp2bnXNSHajBLf9yQNq1tNCsFvhb3YeV89xlHCtK0
YGMNRJ218jcZzzf6EFiBQ4PlVtelEMNnGbx2AgLr6iUhkKtNmWRpLdappj3E6lMo
XJiPgX0JrO++SEgvLP9+cWtCnQdpLmFIi+1CoqEJ8UvAp+hHb3JGwnm8Ll6imPUe
Tf35LRUxRQSHQHW/vnL9xFSCpA18V+R04ftw4I6/4BV33qdZ984UdRzyirEpNO0a
DxK1ZhYpKIawSzaYch30uY+wYpkXH82e477XaKfavG7eecECAwEAAaNTMFEwHQYD
VR0OBBYEFG3YHOBcEsnztABeVJ7M3QE234LRMB8GA1UdIwQYMBaAFG3YHOBcEsnz
tABeVJ7M3QE234LRMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEB
ACP8o6P6BRFBz/sOMJa1z+ogiLO787YFkWd74sGa1qU7DKc5lsftwtTXIK6z6vFE
dhGca4NvTEUR3ssnyMW83ke2iRIokpKJx3cj6VS+NjvMQOy3vzoap3KA0bjCHoJL
1LccvNfzCS0r5cQ2Q/ICPPyhyoFiYj3q1S/oPgO5yD2VrEBNFaty7V64dVR8APN2
4h2G7N3rMJOBirDv2O8OX7zB52IZB6VPR/oLFXG0/ovUkvg8xkkEUezBRo1MSB3l
RZ7EbkSJQi6nOLdOTlFSqPemFMyWTUFvYXPGEWWdIHV78CUByR7qMrKhoAm3VVuD
ShtuGvF9XMCero8PiFyoxnA=
-----END CERTIFICATE-----
)EOF";

// DHT11 config
#define DHTPIN D4
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

// LCD I2C config (16x2)
LiquidCrystal_I2C lcd(0x27, 16, 2);

BearSSL::X509List cert(root_ca_pem);
WiFiClientSecure tlsClient;
PubSubClient mqtt(tlsClient);

// Timing
unsigned long lastTelemetry = 0;
const unsigned long telemetryInterval = 30000;
unsigned long lastDisplay = 0;
const unsigned long displayInterval = 2000;
unsigned long lastReconnectAttempt = 0;
const unsigned long reconnectInterval = 5000;

// Sensor data
float lastTemp = 0.0;
float lastHumidity = 0.0;
bool sensorError = false;
int consecutiveErrors = 0;
const int maxConsecutiveErrors = 5;

// Data buffering for offline mode
#define BUFFER_SIZE 10
struct TelemetryData {
  float temperature;
  float humidity;
  time_t timestamp;
};
TelemetryData dataBuffer[BUFFER_SIZE];
int bufferIndex = 0;
int bufferedCount = 0;

// Forward declarations
void sendTelemetry(float temp, float humidity, time_t timestamp = 0, bool buffered = false);
void reconnectMQTT();
void updateLCD(float temp, float humidity, bool error);
void handleSensorError();

void addToBuffer(float temp, float humidity) {
  dataBuffer[bufferIndex].temperature = temp;
  dataBuffer[bufferIndex].humidity = humidity;
  dataBuffer[bufferIndex].timestamp = time(nullptr);
  
  bufferIndex = (bufferIndex + 1) % BUFFER_SIZE;
  if (bufferedCount < BUFFER_SIZE) {
    bufferedCount++;
  }
  
  Serial.printf("[BUFFER] Added reading (%d buffered)\n", bufferedCount);
}

void flushBuffer() {
  if (bufferedCount == 0 || !mqtt.connected()) {
    return;
  }
  
  Serial.printf("[BUFFER] Flushing %d readings\n", bufferedCount);
  
  int startIndex = (bufferIndex - bufferedCount + BUFFER_SIZE) % BUFFER_SIZE;
  
  for (int i = 0; i < bufferedCount; i++) {
    int idx = (startIndex + i) % BUFFER_SIZE;
    sendTelemetry(
      dataBuffer[idx].temperature,
      dataBuffer[idx].humidity,
      dataBuffer[idx].timestamp,
      true
    );
    delay(100);
  }
  
  bufferedCount = 0;
  Serial.println("[BUFFER] Flush complete");
}

void sendTelemetry(float temp, float humidity, time_t timestamp, bool buffered) {
  StaticJsonDocument<300> doc;
  doc["device_id"] = device_id;
  doc["msg_type"] = "temp_update";
  doc["timestamp"] = timestamp ? timestamp : time(nullptr);
  doc["buffered"] = buffered;
  
  JsonObject data = doc.createNestedObject("data");
  data["temperature"] = serialized(String(temp, 1));
  data["humidity"] = serialized(String(humidity, 1));
  data["unit_temp"] = "C";
  data["unit_humidity"] = "%";
  
  String payload;
  serializeJson(doc, payload);
  
  if (mqtt.publish(topic_telemetry, payload.c_str(), false)) {
    Serial.printf("[TELEMETRY] Sent: T=%.1f°C, H=%.1f%%\n", temp, humidity);
  } else {
    Serial.println("[ERROR] Telemetry send failed");
    if (!buffered) {
      addToBuffer(temp, humidity);
    }
  }
}

void reconnectMQTT() {
  if (millis() - lastReconnectAttempt < reconnectInterval) {
    return;
  }
  
  lastReconnectAttempt = millis();
  
  if (mqtt.connected()) {
    return;
  }
  
  Serial.print("[MQTT] Connecting...");
  
  if (mqtt.connect(device_id, mqtt_username, mqtt_password)) {
    Serial.println(" connected");
    
    StaticJsonDocument<128> st;
    st["device_id"] = device_id;
    st["state"] = "online";
    st["timestamp"] = time(nullptr);
    st["free_heap"] = ESP.getFreeHeap();
    String out; 
    serializeJson(st, out);
    mqtt.publish(topic_status, out.c_str(), true);
    
    flushBuffer();
    
  } else {
    Serial.printf(" failed, rc=%d\n", mqtt.state());
  }
}

void updateLCD(float temp, float humidity, bool error) {
  lcd.clear();
  
  if (error) {
    lcd.setCursor(0, 0);
    lcd.print("Sensor Error!");
    lcd.setCursor(0, 1);
    lcd.print("Check DHT11");
  } else {
    lcd.setCursor(0, 0);
    lcd.print("Temp: ");
    lcd.print(temp, 1);
    lcd.print((char)223);
    lcd.print("C");
    
    lcd.setCursor(0, 1);
    lcd.print("Humi: ");
    lcd.print(humidity, 1);
    lcd.print("%");
  }
}

float validateTemperature(float temp) {
  if (isnan(temp) || temp < -40 || temp > 80) {
    return NAN;
  }
  return temp;
}

float validateHumidity(float humidity) {
  if (isnan(humidity) || humidity < 0 || humidity > 100) {
    return NAN;
  }
  return humidity;
}

void handleSensorError() {
  consecutiveErrors++;
  Serial.printf("[ERROR] DHT11 read failed (consecutive: %d)\n", consecutiveErrors);
  
  sensorError = true;
  updateLCD(0, 0, true);
  
  if (mqtt.connected()) {
    StaticJsonDocument<128> st;
    st["device_id"] = device_id;
    st["state"] = "error";
    st["error"] = "sensor_read_failed";
    st["consecutive_errors"] = consecutiveErrors;
    st["timestamp"] = time(nullptr);
    String out;
    serializeJson(st, out);
    mqtt.publish(topic_status, out.c_str(), false);
  }
  
  if (consecutiveErrors >= maxConsecutiveErrors) {
    Serial.println("[CRITICAL] Too many sensor errors, reinitializing...");
    dht.begin();
    delay(2000);
    consecutiveErrors = 0;
  }
}

void setup() {
  Serial.begin(115200);
  delay(100);
  
  Serial.println("\n\n=================================");
  Serial.println("Temperature Monitor Starting");
  Serial.println("=================================");
  Serial.printf("Device ID: %s\n", device_id);
  Serial.printf("Free heap: %u bytes\n", ESP.getFreeHeap());
  
  dht.begin();
  delay(2000);
  
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Starting...");
  
  WiFi.mode(WIFI_STA);

  uint8_t newMAC[] = {0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x02};
  wifi_set_macaddr(STATION_IF, newMAC);

  WiFi.begin(ssid, wifiPass);
  Serial.print("[WiFi] Connecting");
  
  lcd.setCursor(0, 1);
  lcd.print("WiFi...");
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(3000);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("\n[ERROR] WiFi connection failed, restarting...");
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("WiFi Failed!");
    delay(2000);
    ESP.restart();
  }
  
  Serial.println("\n[WiFi] Connected");
  Serial.printf("[WiFi] IP: %s\n", WiFi.localIP().toString().c_str());
  Serial.printf("[WiFi] Signal: %d dBm\n", WiFi.RSSI());
  
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("WiFi OK");
  lcd.setCursor(0, 1);
  lcd.print(WiFi.localIP());
  delay(2000);
  
  // configTime(7 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  // Serial.println("[NTP] Waiting for time sync...");
  
  // time_t now = time(nullptr);
  // int timeAttempts = 0;
  // while (now < 1600000000 && timeAttempts < 20) {
  //   delay(500);
  //   now = time(nullptr);
  //   timeAttempts++;
  // }
  
  // if (now < 1600000000) {
  //   Serial.println("\n[WARNING] Time sync failed");
  // } else {
  //   Serial.printf("[NTP] Time synced: %lld\n", (long long)now);
  // }

  tlsClient.setTrustAnchors(&cert);
  tlsClient.setInsecure();
  
  mqtt.setServer(mqtt_host, mqtt_port);
  mqtt.setKeepAlive(60);
  
  reconnectMQTT();
  
  Serial.println("\n[SYSTEM] Ready!");
  Serial.println("=================================\n");
  
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Ready!");
  delay(1000);
}

void loop() {
  if (!mqtt.connected()) {
    reconnectMQTT();
  }
  mqtt.loop();
  
  unsigned long currentMillis = millis();
  
  if (currentMillis - lastDisplay >= displayInterval) {
    lastDisplay = currentMillis;
    
    float temp = dht.readTemperature();
    float humidity = dht.readHumidity();
    
    temp = validateTemperature(temp);
    humidity = validateHumidity(humidity);
    
    if (isnan(temp) || isnan(humidity)) {
      handleSensorError();
    } else {
      consecutiveErrors = 0;
      sensorError = false;
      lastTemp = temp;
      lastHumidity = humidity;
      updateLCD(temp, humidity, false);
      
      Serial.printf("[SENSOR] T: %.1f°C, H: %.1f%%\n", temp, humidity);
    }
  }
  
  if (currentMillis - lastTelemetry >= telemetryInterval) {
    lastTelemetry = currentMillis;
    
    if (!sensorError) {
      if (mqtt.connected()) {
        sendTelemetry(lastTemp, lastHumidity);
      } else {
        addToBuffer(lastTemp, lastHumidity);
      }
    } else {
      if (mqtt.connected()) {
        StaticJsonDocument<128> st;
        st["device_id"] = device_id;
        st["state"] = "error";
        st["error"] = "sensor_read_failed";
        st["timestamp"] = time(nullptr);
        String out;
        serializeJson(st, out);
        mqtt.publish(topic_status, out.c_str(), false);
      }
    }
  }
  
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WARNING] WiFi disconnected, reconnecting...");
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("WiFi Lost!");
    WiFi.reconnect();
    delay(1000);
  }
}