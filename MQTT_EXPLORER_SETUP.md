# MQTT Explorer Setup Guide

This guide provides connection settings for the IRIS MQTT brokers using MQTT Explorer.

## Download MQTT Explorer

Download from: https://mqtt-explorer.com/

## Connection Settings

### mqtt-1 (Primary Broker - West Europe)

**Connection Details:**
```
Name: IRIS Dev - mqtt-1
Protocol: mqtts://
Host: iris-dev-mqtt-1.westeurope.azurecontainer.io
Port: 8883
Username: deviceuser
Password: <See password section below>
```

**TLS/SSL Settings:**
- Enable SSL/TLS: ✅ Yes
- Protocol: TLS 1.3
- Validate certificate: No (for dev - self-signed certificates)
- CA Certificate file: Use `ca.crt` from this repository
- Client certificate: Not required

**Advanced Settings:**
- MQTT Version: 5.0 (or 3.1.1 compatible)
- Clean session: Yes
- Keep alive: 60 seconds

---

### mqtt-2 (External Company Simulator - West Europe)

**Connection Details:**
```
Name: IRIS Dev - mqtt-2
Protocol: mqtts://
Host: iris-dev-mqtt-2.westeurope.azurecontainer.io
Port: 8883
Username: external_integration_user
Password: <See password section below>
```

**TLS/SSL Settings:**
- Enable SSL/TLS: ✅ Yes
- Protocol: TLS 1.3
- Validate certificate: No (for dev - self-signed certificates)
- CA Certificate file: Use `ca.crt` from this repository
- Client certificate: Not required

**Advanced Settings:**
- MQTT Version: 5.0 (or 3.1.1 compatible)
- Clean session: Yes
- Keep alive: 60 seconds

---

## Topics to Monitor

### All Advantech Device Messages
```
Advantech/#
```
This subscribes to all messages from Advantech devices.

### Specific Device Topics
```
Advantech/74FE4857C133/#
Advantech/74FE4857C1B3/#
```

### Test Topics
```
test/#
```
For testing connectivity and bridge functionality.

---

## Getting Passwords

Passwords are stored securely in GitHub Secrets and cannot be retrieved from this repository.

### Option 1: Ask DevOps/Admin
Contact the person who set up the GitHub Actions secrets for the actual password values.

### Option 2: GitHub Secrets (if you have access)
1. Go to: https://github.com/apcoa-tech/iris-mqtt-broker/settings/secrets/actions
2. Find these secrets:
   - `MQTT_USER_DEVICEUSER_PASSWORD` - For mqtt-1 deviceuser
   - `MQTT_USER_ADMINUSER_PASSWORD` - For mqtt-1 adminuser
   - `MQTT_BRIDGE_PASSWORD` - For mqtt-2 external_integration_user

**Note:** GitHub Secrets are encrypted and cannot be viewed - only updated.

### Option 3: Azure Key Vault (if configured)
Check Azure Key Vault in the `iot-dev` resource group for stored credentials.

---

## Getting Certificates

### CA Certificate (ca.crt)

**Location:** `/path/to/iris-mqtt-broker/ca.crt`

This file contains the full certificate chain:
- Production Mosquitto server certificate
- IRIS Production CA certificate

**Download from repository:**
```bash
# If you have access to the repository
git clone https://github.com/apcoa-tech/iris-mqtt-broker.git
cd iris-mqtt-broker
# ca.crt is in the root directory
```

**Or download from Azure File Share:**
```bash
az storage file download \
  --account-name irisstdev001 \
  --share-name iris-dev-mqtt-certs \
  --path ca.crt \
  --dest ./ca.crt
```

---

## Step-by-Step Setup in MQTT Explorer

### 1. Open MQTT Explorer
Launch the MQTT Explorer application.

### 2. Create New Connection
Click the **+** button to add a new connection.

### 3. Basic Connection Settings
- **Name:** IRIS Dev - mqtt-1 (or mqtt-2)
- **Protocol:** mqtts://
- **Host:** iris-dev-mqtt-1.westeurope.azurecontainer.io
- **Port:** 8883

### 4. Authentication
- **Username:** deviceuser (for mqtt-1) or external_integration_user (for mqtt-2)
- **Password:** Enter the password from GitHub Secrets

### 5. TLS/SSL Configuration
- Click on **Encryption (TLS)** section
- Enable **Use TLS**
- Set **TLS Version:** TLS 1.3
- **Validate certificate:** Uncheck (for dev environment with self-signed certs)
- **CA Certificate file:** Browse and select the `ca.crt` file
- Leave **Client certificate** and **Client key** empty

### 6. Advanced Settings (Optional)
- **MQTT Version:** Auto-detect (or manually select 5.0)
- **Clean session:** Checked
- **Keep alive:** 60 seconds
- **Timeout:** 30 seconds

### 7. Save and Connect
Click **SAVE** then **CONNECT**

### 8. Verify Connection
Once connected, you should see:
- Green status indicator
- Subscription panel on the left
- Message viewer on the right

### 9. Subscribe to Topics
In the topic subscription field, enter:
```
Advantech/#
```
Then click **Subscribe**

---

## Testing the Connection

### Test mqtt-1 (Primary Broker)

1. Connect to mqtt-1 using deviceuser credentials
2. Subscribe to `Advantech/#`
3. Publish a test message:
   - Topic: `Advantech/test`
   - Message: `{"test": "hello from mqtt-1"}`
4. Verify you see the message in the viewer

### Test mqtt-2 (External Simulator)

1. Connect to mqtt-2 using external_integration_user credentials
2. Subscribe to `Advantech/#`
3. You should see messages bridged from mqtt-1
4. Publish a test message:
   - Topic: `Advantech/test`
   - Message: `{"test": "hello from mqtt-2"}`
5. Verify the message appears

### Test Bidirectional Bridge

1. Open two MQTT Explorer windows
2. Connect one to mqtt-1, another to mqtt-2
3. Subscribe both to `Advantech/#`
4. Publish a message from mqtt-1
5. Verify it appears in mqtt-2 window (bridged)
6. Publish a message from mqtt-2
7. Verify it appears in mqtt-1 window (bridged back)

---

## Troubleshooting

### Connection Refused
- Verify the broker is running: `az container show -g iot-dev -n iris-dev-mqtt-1`
- Check firewall/network rules
- Verify port 8883 is accessible

### Authentication Failed
- Double-check username and password
- Verify the password file is up-to-date in Azure File Share
- Check if passwords were recently rotated

### Certificate Errors
- Ensure you're using the correct `ca.crt` file
- For dev environment, disable certificate validation
- Verify TLS version is 1.3 or 1.2

### No Messages Appearing
- Verify topic subscription is correct (use `#` wildcard)
- Check if devices are actively publishing
- Verify bridge configuration if testing cross-broker messages

### Bridge Not Working
- Check bridge configuration in mosquitto.conf
- Verify `bridge_insecure true` is set (dev environment)
- Check bridge credentials match between brokers

---

## Security Notes

### Development Environment
- Self-signed certificates are acceptable
- Certificate validation can be disabled
- Passwords should still be kept secure

### Production Environment
When moving to production:
- ✅ Use proper certificates with valid hostnames
- ✅ Enable certificate validation
- ✅ Use strong passwords (already using PBKDF2-SHA512)
- ✅ Rotate credentials regularly
- ✅ Enable client certificates for mutual TLS
- ✅ Use Azure Key Vault for secret management

---

## Additional Resources

- **Mosquitto Documentation:** https://mosquitto.org/documentation/
- **MQTT Protocol:** https://mqtt.org/
- **MQTT Explorer:** https://mqtt-explorer.com/
- **GitHub Repository:** https://github.com/apcoa-tech/iris-mqtt-broker

---

## Support

For issues or questions:
1. Check the main README.md in this repository
2. Review DEPLOYMENT.md for deployment issues
3. Check BRIDGE_TEST_SUCCESS.md for bridge configuration
4. Contact the DevOps team
