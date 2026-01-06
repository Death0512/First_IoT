#!/bin/bash
# =========================================================
# Deploy Certificates to VPS
# VPS IP: 18.143.176.27
# =========================================================

VPS_USER="root"
VPS_IP="18.143.176.27"
VPS_CERT_DIR="/opt/iot/mosquitto/certs"

echo "==========================================================="
echo " Deploying Certificates to VPS: $VPS_IP"
echo "==========================================================="

# Upload CA and Server certificates
echo "[1/3] Uploading CA certificates..."
scp ca.cert.pem $VPS_USER@$VPS_IP:$VPS_CERT_DIR/
scp ca.key.pem $VPS_USER@$VPS_IP:$VPS_CERT_DIR/

echo "[2/3] Uploading Server certificates..."
scp server.cert.pem $VPS_USER@$VPS_IP:$VPS_CERT_DIR/
scp server.key.pem $VPS_USER@$VPS_IP:$VPS_CERT_DIR/
scp server.full.pem $VPS_USER@$VPS_IP:$VPS_CERT_DIR/
scp server.csr.pem $VPS_USER@$VPS_IP:$VPS_CERT_DIR/

echo "[3/3] Restarting Mosquitto service..."
ssh $VPS_USER@$VPS_IP "cd /opt/iot && docker-compose restart mosquitto"

echo ""
echo "==========================================================="
echo " Deployment Complete!"
echo "==========================================================="
echo ""
echo "Next steps:"
echo "  1. Test MQTT connection from gateway"
echo "  2. Verify: openssl s_client -connect $VPS_IP:8883 -CAfile ca.cert.pem"
echo ""
