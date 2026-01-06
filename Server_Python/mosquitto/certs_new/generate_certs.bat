@echo off
REM =========================================================
REM IoT Certificate Generation Script
REM IP: 18.143.176.27
REM Generated: 2026-01-06
REM =========================================================

set CERT_DIR=%~dp0
set NEW_IP=18.143.176.27
set DAYS_CA=3650
set DAYS_CERT=825

echo =========================================================
echo Generating IoT Certificates for IP: %NEW_IP%
echo =========================================================

REM =========================================================
REM Step 1: Generate CA (Certificate Authority)
REM =========================================================
echo [1/6] Generating CA private key...
openssl genrsa -out "%CERT_DIR%ca.key.pem" 2048

echo [2/6] Generating CA certificate...
openssl req -new -x509 -days %DAYS_CA% -key "%CERT_DIR%ca.key.pem" -out "%CERT_DIR%ca.cert.pem" -subj "/CN=IoT_CA_2026"

REM =========================================================
REM Step 2: Generate Server Certificate (for Mosquitto on VPS)
REM =========================================================
echo [3/6] Generating Server private key...
openssl genrsa -out "%CERT_DIR%server.key.pem" 2048

echo [4/6] Creating Server CSR with SAN extension...
REM Create openssl config for SAN
echo [req] > "%CERT_DIR%server_san.cnf"
echo default_bits = 2048 >> "%CERT_DIR%server_san.cnf"
echo prompt = no >> "%CERT_DIR%server_san.cnf"
echo default_md = sha256 >> "%CERT_DIR%server_san.cnf"
echo distinguished_name = dn >> "%CERT_DIR%server_san.cnf"
echo req_extensions = req_ext >> "%CERT_DIR%server_san.cnf"
echo. >> "%CERT_DIR%server_san.cnf"
echo [dn] >> "%CERT_DIR%server_san.cnf"
echo CN = VPS.server >> "%CERT_DIR%server_san.cnf"
echo. >> "%CERT_DIR%server_san.cnf"
echo [req_ext] >> "%CERT_DIR%server_san.cnf"
echo subjectAltName = @alt_names >> "%CERT_DIR%server_san.cnf"
echo. >> "%CERT_DIR%server_san.cnf"
echo [alt_names] >> "%CERT_DIR%server_san.cnf"
echo DNS.1 = VPS.server >> "%CERT_DIR%server_san.cnf"
echo DNS.2 = localhost >> "%CERT_DIR%server_san.cnf"
echo IP.1 = %NEW_IP% >> "%CERT_DIR%server_san.cnf"
echo IP.2 = 127.0.0.1 >> "%CERT_DIR%server_san.cnf"

openssl req -new -key "%CERT_DIR%server.key.pem" -out "%CERT_DIR%server.csr.pem" -config "%CERT_DIR%server_san.cnf"

REM Create extension file for signing
echo subjectAltName = DNS:VPS.server,DNS:localhost,IP:%NEW_IP%,IP:127.0.0.1 > "%CERT_DIR%server_ext.cnf"
echo basicConstraints = CA:FALSE >> "%CERT_DIR%server_ext.cnf"
echo keyUsage = digitalSignature, keyEncipherment >> "%CERT_DIR%server_ext.cnf"
echo extendedKeyUsage = serverAuth, clientAuth >> "%CERT_DIR%server_ext.cnf"

echo Signing Server certificate with CA...
openssl x509 -req -in "%CERT_DIR%server.csr.pem" -CA "%CERT_DIR%ca.cert.pem" -CAkey "%CERT_DIR%ca.key.pem" -CAcreateserial -out "%CERT_DIR%server.cert.pem" -days %DAYS_CERT% -extfile "%CERT_DIR%server_ext.cnf"

REM Create full chain
echo Creating Server full chain...
copy /b "%CERT_DIR%server.cert.pem"+"%CERT_DIR%ca.cert.pem" "%CERT_DIR%server.full.pem"

REM =========================================================
REM Step 3: Generate Gateway1 Certificate (User1 - Anh)
REM =========================================================
echo [5/6] Generating Gateway1 certificate...
openssl genrsa -out "%CERT_DIR%gateway1.key.pem" 2048

echo [gateway1_dn] > "%CERT_DIR%gateway1.cnf"
echo default_bits = 2048 >> "%CERT_DIR%gateway1.cnf"
echo prompt = no >> "%CERT_DIR%gateway1.cnf"
echo default_md = sha256 >> "%CERT_DIR%gateway1.cnf"
echo distinguished_name = dn >> "%CERT_DIR%gateway1.cnf"
echo. >> "%CERT_DIR%gateway1.cnf"
echo [dn] >> "%CERT_DIR%gateway1.cnf"
echo CN = Gateway1 >> "%CERT_DIR%gateway1.cnf"

openssl req -new -key "%CERT_DIR%gateway1.key.pem" -out "%CERT_DIR%gateway1.csr.pem" -subj "/CN=Gateway1"

echo basicConstraints = CA:FALSE > "%CERT_DIR%gateway_ext.cnf"
echo keyUsage = digitalSignature, keyEncipherment >> "%CERT_DIR%gateway_ext.cnf"
echo extendedKeyUsage = clientAuth >> "%CERT_DIR%gateway_ext.cnf"

openssl x509 -req -in "%CERT_DIR%gateway1.csr.pem" -CA "%CERT_DIR%ca.cert.pem" -CAkey "%CERT_DIR%ca.key.pem" -CAcreateserial -out "%CERT_DIR%gateway1.cert.pem" -days %DAYS_CERT% -extfile "%CERT_DIR%gateway_ext.cnf"

copy /b "%CERT_DIR%gateway1.cert.pem"+"%CERT_DIR%ca.cert.pem" "%CERT_DIR%gateway1.full.pem"

REM =========================================================
REM Step 4: Generate Gateway2 Certificate (User2 - Thao)
REM =========================================================
echo Generating Gateway2 certificate...
openssl genrsa -out "%CERT_DIR%gateway2.key.pem" 2048
openssl req -new -key "%CERT_DIR%gateway2.key.pem" -out "%CERT_DIR%gateway2.csr.pem" -subj "/CN=Gateway2"
openssl x509 -req -in "%CERT_DIR%gateway2.csr.pem" -CA "%CERT_DIR%ca.cert.pem" -CAkey "%CERT_DIR%ca.key.pem" -CAcreateserial -out "%CERT_DIR%gateway2.cert.pem" -days %DAYS_CERT% -extfile "%CERT_DIR%gateway_ext.cnf"
copy /b "%CERT_DIR%gateway2.cert.pem"+"%CERT_DIR%ca.cert.pem" "%CERT_DIR%gateway2.full.pem"

REM =========================================================
REM Step 5: Generate Gateway3 Certificate (User3 - Tu)
REM =========================================================
echo [6/6] Generating Gateway3 certificate...
openssl genrsa -out "%CERT_DIR%gateway3.key.pem" 2048
openssl req -new -key "%CERT_DIR%gateway3.key.pem" -out "%CERT_DIR%gateway3.csr.pem" -subj "/CN=Gateway3"
openssl x509 -req -in "%CERT_DIR%gateway3.csr.pem" -CA "%CERT_DIR%ca.cert.pem" -CAkey "%CERT_DIR%ca.key.pem" -CAcreateserial -out "%CERT_DIR%gateway3.cert.pem" -days %DAYS_CERT% -extfile "%CERT_DIR%gateway_ext.cnf"
copy /b "%CERT_DIR%gateway3.cert.pem"+"%CERT_DIR%ca.cert.pem" "%CERT_DIR%gateway3.full.pem"

REM Cleanup temp files
del "%CERT_DIR%*.cnf" 2>nul
del "%CERT_DIR%*.srl" 2>nul

echo.
echo =========================================================
echo Certificate generation complete!
echo =========================================================
echo.
echo Generated files:
echo   CA:        ca.cert.pem, ca.key.pem
echo   Server:    server.cert.pem, server.key.pem, server.full.pem
echo   Gateway1:  gateway1.cert.pem, gateway1.key.pem, gateway1.full.pem
echo   Gateway2:  gateway2.cert.pem, gateway2.key.pem, gateway2.full.pem
echo   Gateway3:  gateway3.cert.pem, gateway3.key.pem, gateway3.full.pem
echo.
echo IP in Server cert: %NEW_IP%
echo.
pause
