# MQTT Broker Scripts

This directory contains scripts for managing and testing the MQTT broker infrastructure.

## Scripts

### `generate-config.sh`

Generates `mosquitto.conf` from template with environment variable substitution.

**Usage:**
```bash
./scripts/generate-config.sh [template-file] [output-file]
```

**Example:**
```bash
# Generate config from template
export BRIDGE_USERNAME="external_integration_user"
export BRIDGE_PASSWORD="your-password"
export BRIDGE_REMOTE_ADDRESS="mqtt-2.example.com:8883"

./scripts/generate-config.sh config/mosquitto.conf.template /tmp/mosquitto.conf
```

**Called by:** GitHub Actions workflow during deployment

---

### `generate-password-file.sh`

Generates Mosquitto password file with hashed passwords for authentication.

**Usage:**
```bash
./scripts/generate-password-file.sh [output-file] [comma-separated-users]
```

**Example:**
```bash
# Set passwords via environment variables
export PASSWORD_DEVICEUSER="password1"
export PASSWORD_ADMINUSER="password2"

# Generate password file
./scripts/generate-password-file.sh /tmp/password.txt "deviceuser,adminuser"
```

**Requirements:**
- `mosquitto_passwd` must be installed
- Password environment variables must be set: `PASSWORD_<USERNAME_UPPERCASE>`

**Called by:** GitHub Actions workflow during deployment

---

### `test-mqtt.sh`

Tests MQTT broker connectivity and bridge functionality.

**Usage:**
```bash
./scripts/test-mqtt.sh [environment]
```

**Example:**
```bash
# Test dev environment (default)
./scripts/test-mqtt.sh dev

# Test UAT environment
./scripts/test-mqtt.sh uat
```

**Prerequisites:**
1. Install mosquitto client tools:
   ```bash
   # macOS
   brew install mosquitto

   # Ubuntu/Debian
   sudo apt-get install mosquitto-clients

   # RHEL/CentOS
   sudo yum install mosquitto
   ```

2. Set password environment variables or script will prompt:
   ```bash
   export PASSWORD_DEVICEUSER="your-device-password"
   export PASSWORD_EXTERNAL_INTEGRATION_USER="your-bridge-password"
   ```

3. Ensure you're logged into Azure CLI:
   ```bash
   az login
   ```

**What it tests:**
1. ✅ mqtt-1 broker connectivity (publish/subscribe)
2. ✅ mqtt-2 broker connectivity (publish/subscribe)
3. ✅ Bridge functionality (mqtt-1 → mqtt-2)

**Sample output:**
```
========================================
MQTT Broker Testing - dev
========================================

📥 Downloading CA certificate...
✅ CA certificate downloaded

Testing mqtt-1 (iris-dev-mqtt-1.westeurope.azurecontainer.io)...
  📤 Publishing test message...
  ✅ Publish successful
  📥 Testing subscription (5 second timeout)...
  ✅ Subscribe successful

Testing mqtt-2 (iris-dev-mqtt-2.westeurope.azurecontainer.io)...
  📤 Publishing test message...
  ✅ Publish successful
  📥 Testing subscription (5 second timeout)...
  ✅ Subscribe successful

========================================
Testing Bridge (mqtt-1 → mqtt-2)
========================================

This test will:
  1. Start subscriber on mqtt-2 (external broker)
  2. Publish message to mqtt-1 (our broker)
  3. Verify message arrives on mqtt-2 via bridge

Starting mqtt-2 subscriber in background...
📤 Publishing to mqtt-1...
  Topic: Advantech/BRIDGE_TEST/data
  Message: {"bridge_test":true,"timestamp":"2025-11-25T08:00:00Z"}
⏳ Waiting for message on mqtt-2 (5 seconds)...
✅ Bridge test PASSED - Message received on mqtt-2!

Received message:
Advantech/BRIDGE_TEST/data {"bridge_test":true,"timestamp":"2025-11-25T08:00:00Z"}

========================================
✅ Testing Complete
========================================
```

---

## Environment Variables

Scripts expect these environment variables to be set (or will load from `config/env.<environment>`):

### Common Variables
- `RESOURCE_GROUP` - Azure resource group name
- `STORAGE_ACCOUNT` - Azure storage account name
- `DEPLOY_DUAL_BROKERS` - "true" for dual broker setup, "false" for single

### Dual Broker Setup
- `CONTAINER_GROUP_1` - mqtt-1 container group name
- `CONTAINER_GROUP_2` - mqtt-2 container group name
- `BRIDGE_USERNAME` - Username for bridge authentication
- `BRIDGE_PASSWORD` - Password for bridge authentication
- `EXTERNAL_BROKER_ADDRESS` - mqtt-2 address (e.g., `mqtt-2.example.com:8883`)

### Single Broker Setup
- `CONTAINER_GROUP` - Container group name
- `BRIDGE_REMOTE_ADDRESS` - External broker address

### Password Variables
- `PASSWORD_DEVICEUSER` - Password for deviceuser
- `PASSWORD_ADMINUSER` - Password for adminuser (optional)
- `PASSWORD_EXTERNAL_INTEGRATION_USER` - Password for external_integration_user

---

## Quick Testing Guide

### 1. Install Prerequisites
```bash
# macOS
brew install mosquitto azure-cli

# Ubuntu
sudo apt-get install mosquitto-clients azure-cli
```

### 2. Login to Azure
```bash
az login
```

### 3. Set Passwords
```bash
# Get passwords from PASSWORDS.md or GitHub Secrets
export PASSWORD_DEVICEUSER="<from-PASSWORDS.md>"
export PASSWORD_EXTERNAL_INTEGRATION_USER="<from-PASSWORDS.md>"
```

### 4. Run Test
```bash
./scripts/test-mqtt.sh dev
```

### 5. Manual Testing

If you want to test manually:

```bash
# Download CA certificate first
./scripts/test-mqtt.sh dev  # This downloads ca.crt

# Subscribe to mqtt-2 in one terminal
mosquitto_sub -h iris-dev-mqtt-2.westeurope.azurecontainer.io -p 8883 \
  --cafile ca.crt \
  -u external_integration_user -P "$PASSWORD_EXTERNAL_INTEGRATION_USER" \
  -t "Advantech/#" -v

# Publish to mqtt-1 in another terminal
mosquitto_pub -h iris-dev-mqtt-1.westeurope.azurecontainer.io -p 8883 \
  --cafile ca.crt \
  -u deviceuser -P "$PASSWORD_DEVICEUSER" \
  -t "Advantech/TEST/data" \
  -m '{"temp":25.5}'

# Message should appear in mqtt-2 subscriber
```

---

## Troubleshooting

### Error: mosquitto tools not found
Install mosquitto client tools (see prerequisites above)

### Error: CA certificate not found
Run `./scripts/test-mqtt.sh` once to download it, or download manually:
```bash
az storage file download \
  --account-name irisstdev001 \
  --share-name iris-dev-mqtt-certs \
  --path ca.crt \
  --dest ./ca.crt
```

### Error: Connection refused
Check if containers are running:
```bash
az container show -g iot-dev -n iris-dev-mqtt-1 --query instanceView.state
az container logs -g iot-dev -n iris-dev-mqtt-1 --container-name mosquitto
```

### Bridge not working
1. Check mqtt-1 logs for bridge connection errors:
   ```bash
   az container logs -g iot-dev -n iris-dev-mqtt-1 --container-name mosquitto | grep -i bridge
   ```

2. Verify bridge credentials are correct in config:
   ```bash
   az storage file download \
     --account-name irisstdev001 \
     --share-name iris-dev-mqtt-1-config \
     --path mosquitto.conf \
     --dest /tmp/mqtt1.conf

   cat /tmp/mqtt1.conf | grep -A 10 "connection bridge"
   ```

3. Ensure mqtt-2 is accessible from mqtt-1:
   ```bash
   az container exec -g iot-dev -n iris-dev-mqtt-1 --container-name mosquitto \
     --exec-command "ping -c 3 iris-dev-mqtt-2.westeurope.azurecontainer.io"
   ```
