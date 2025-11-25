# IRIS MQTT Broker Deployment Guide

## Overview

This guide covers deploying MQTT broker configurations to Azure Container Instances.

## Architecture

### Development Environment (Dual Broker - Simulates Production)
```
IoT Devices
    │
    ├──> mqtt-1 (iris-dev-mqtt-1.westeurope.azurecontainer.io:8883)
    │    OUR MQTT Broker (simulates production)
    │    │
    │    └──bridge──> mqtt-2 (iris-dev-mqtt-2.westeurope.azurecontainer.io:8883)
    │                 EXTERNAL COMPANY Simulator (standalone)
    │
    │    Purpose: Test bridge integration without access to external company's dev env
```

### Production Environment (Single Broker)
```
IoT Devices
    │
    └──> mqtt (iris-prd-mqtt.westeurope.azurecontainer.io:8883)
         OUR MQTT Broker
         │
         └──bridge──> External Company's MQTT Broker
                      (Not owned by us)
```

**Key Points:**
- **DEV**: mqtt-1 = our broker, mqtt-2 = fake external company (for testing)
- **PRD**: Single broker that bridges to the real external company
- mqtt-2 in dev is standalone - it does NOT bridge back to mqtt-1
- This simulates the real production scenario where external company accepts our connection

## Prerequisites

### 1. Infrastructure Provisioned

Before deploying configs, ensure the following Azure resources exist:

- **Azure Container Instances**: Created by `iris-container-instance-plugin`
- **Azure File Shares**: Created by `iris-blob-storage-plugin`
- **Docker Image**: Built and pushed to ACR by `build-image.yml` workflow

### 2. TLS Certificates

Upload TLS certificates to Azure File Shares before first deployment.

#### For Development

Upload to file share: `iris-dev-mqtt-certs`
```bash
# Generate self-signed certs (dev only)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout server.key \
  -out server.crt \
  -subj "/CN=iris-dev-mqtt.westeurope.azurecontainer.io"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ca.key \
  -out ca.crt \
  -subj "/CN=IRIS Dev CA"

# Upload to Azure File Share
az storage file upload --account-name irisstdev001 \
  --share-name iris-dev-mqtt-certs \
  --source server.crt --path server.crt

az storage file upload --account-name irisstdev001 \
  --share-name iris-dev-mqtt-certs \
  --source server.key --path server.key

az storage file upload --account-name irisstdev001 \
  --share-name iris-dev-mqtt-certs \
  --source ca.crt --path ca.crt
```

Upload to file share: `iris-dev-mqtt-bridge-certs`
```bash
# Get production broker CA certificate
# (You need to obtain this from production broker admin)
az storage file upload --account-name irisstdev001 \
  --share-name iris-dev-mqtt-bridge-certs \
  --source production_ca.crt --path production_ca.crt
```

#### For Production

Upload to file share: `iris-prd-mqtt-certs`
```bash
# Use proper CA-signed certificates for production
az storage file upload --account-name irisstprd001 \
  --share-name iris-prd-mqtt-certs \
  --source server.crt --path server.crt

az storage file upload --account-name irisstprd001 \
  --share-name iris-prd-mqtt-certs \
  --source server.key --path server.key

az storage file upload --account-name irisstprd001 \
  --share-name iris-prd-mqtt-certs \
  --source ca.crt --path ca.crt
```

Upload to file share: `iris-prd-mqtt-bridge-certs`
```bash
# Upload external company's CA certificate
az storage file upload --account-name irisstprd001 \
  --share-name iris-prd-mqtt-bridge-certs \
  --source external_company_ca.crt --path external_company_ca.crt
```

### 3. GitHub Secrets

Add the following secrets to the `iris-mqtt-broker` repository:

```bash
# Azure OIDC (already set)
gh secret set AZURE_CLIENT_ID --repo apcoa-tech/iris-mqtt-broker
gh secret set AZURE_TENANT_ID --repo apcoa-tech/iris-mqtt-broker
gh secret set AZURE_SUBSCRIPTION_ID --repo apcoa-tech/iris-mqtt-broker

# MQTT Passwords - Generate strong passwords
gh secret set MQTT_BRIDGE_PASSWORD --repo apcoa-tech/iris-mqtt-broker
# ^ Password for mqtt-1 to connect to mqtt-2 (dev) or external company (prd)
# ^ Also used by mqtt-2 for "external_integration_user" account

gh secret set MQTT_USER_DEVICEUSER_PASSWORD --repo apcoa-tech/iris-mqtt-broker
# ^ Password for IoT devices connecting to mqtt-1

gh secret set MQTT_USER_ADMINUSER_PASSWORD --repo apcoa-tech/iris-mqtt-broker
# ^ Password for admin/monitoring tools connecting to mqtt-1
```

#### Generating Strong Passwords

```bash
# Generate random passwords
BRIDGE_PWD=$(openssl rand -base64 32)
DEVICE_PWD=$(openssl rand -base64 32)
ADMIN_PWD=$(openssl rand -base64 32)

# Add to GitHub
gh secret set MQTT_BRIDGE_PASSWORD --body "$BRIDGE_PWD" --repo apcoa-tech/iris-mqtt-broker
gh secret set MQTT_USER_DEVICEUSER_PASSWORD --body "$DEVICE_PWD" --repo apcoa-tech/iris-mqtt-broker
gh secret set MQTT_USER_ADMINUSER_PASSWORD --body "$ADMIN_PWD" --repo apcoa-tech/iris-mqtt-broker

# Save these passwords securely - you'll need them for testing
echo "Bridge Password (mqtt-1 -> mqtt-2): $BRIDGE_PWD"
echo "Device User Password: $DEVICE_PWD"
echo "Admin User Password: $ADMIN_PWD"
```

## Deployment

### Deploy to Development (Dual Broker)

#### Option 1: Via GitHub Actions Workflow (Recommended)

1. Go to: https://github.com/apcoa-tech/iris-mqtt-broker/actions/workflows/deploy-config.yml
2. Click "Run workflow"
3. Select `environment: dev`
4. Click "Run workflow"

#### Option 2: Via Git Push

```bash
cd iris-mqtt-broker
# Make changes to config templates
git add config/
git commit -m "Update MQTT configuration"
git push origin main
```

This automatically triggers the workflow and deploys to both mqtt-1 and mqtt-2.

### Deploy to Production (Single Broker)

1. Go to: https://github.com/apcoa-tech/iris-mqtt-broker/actions/workflows/deploy-config.yml
2. Click "Run workflow"
3. Select `environment: prd`
4. Click "Run workflow"

## Verification

### Check Container Status

```bash
# Development
az container show -g iot-dev -n iris-dev-mqtt-1 --query instanceView.state
az container show -g iot-dev -n iris-dev-mqtt-2 --query instanceView.state

# Production
az container show -g iot-prd -n iris-prd-mqtt --query instanceView.state
```

### View Container Logs

```bash
# Development - mqtt-1
az container logs -g iot-dev -n iris-dev-mqtt-1 --container-name mosquitto --follow

# Development - mqtt-2
az container logs -g iot-dev -n iris-dev-mqtt-2 --container-name mosquitto --follow

# Production
az container logs -g iot-prd -n iris-prd-mqtt --container-name mosquitto --follow
```

### Test MQTT Connection

```bash
# Install mosquitto clients
brew install mosquitto  # macOS
# OR
apt-get install mosquitto-clients  # Ubuntu

# Test mqtt-1 (our broker)
mosquitto_pub -h iris-dev-mqtt-1.westeurope.azurecontainer.io -p 8883 \
  --cafile ca.crt \
  -u deviceuser -P <MQTT_USER_DEVICEUSER_PASSWORD> \
  -t "Advantech/74FE4857C133/data" -m '{"temp":25.5}'

# Subscribe on mqtt-1 to see local messages
mosquitto_sub -h iris-dev-mqtt-1.westeurope.azurecontainer.io -p 8883 \
  --cafile ca.crt \
  -u deviceuser -P <MQTT_USER_DEVICEUSER_PASSWORD> \
  -t "Advantech/#" -v

# Subscribe on mqtt-2 to verify bridge is working
mosquitto_sub -h iris-dev-mqtt-2.westeurope.azurecontainer.io -p 8883 \
  --cafile ca.crt \
  -u external_integration_user -P <MQTT_BRIDGE_PASSWORD> \
  -t "Advantech/#" -v

# Expected: Messages published to mqtt-1 should appear on mqtt-2 (via bridge)
```

**Testing the Bridge:**

1. Start subscriber on mqtt-2 (external company simulator):
```bash
mosquitto_sub -h iris-dev-mqtt-2.westeurope.azurecontainer.io -p 8883 \
  --cafile ca.crt \
  -u external_integration_user -P <MQTT_BRIDGE_PASSWORD> \
  -t "Advantech/#" -v
```

2. In another terminal, publish to mqtt-1 (our broker):
```bash
mosquitto_pub -h iris-dev-mqtt-1.westeurope.azurecontainer.io -p 8883 \
  --cafile ca.crt \
  -u deviceuser -P <MQTT_USER_DEVICEUSER_PASSWORD> \
  -t "Advantech/74FE4857C133/test" -m "Bridge test message"
```

3. You should see the message appear on mqtt-2 subscriber (proving bridge works!)

## Troubleshooting

### Container Won't Start

Check logs for certificate errors:
```bash
az container logs -g iot-dev -n iris-dev-mqtt-1 --container-name mosquitto --tail 100
```

Common issues:
- Missing certificates in file share
- Incorrect certificate paths in config
- Certificate permissions/format issues

### Bridge Connection Fails

Check logs for bridge-specific errors:
```bash
az container logs -g iot-dev -n iris-dev-mqtt-1 | grep -i bridge
```

Common issues:
- Wrong bridge password
- Bridge CA certificate missing/incorrect
- Network connectivity to remote broker
- Remote broker not allowing connection

### Bridge Not Working (Dev)

Verify both containers are running:
```bash
az container show -g iot-dev -n iris-dev-mqtt-1 --query instanceView.state
az container show -g iot-dev -n iris-dev-mqtt-2 --query instanceView.state
```

Check bridge status in mqtt-1 logs:
```bash
az container logs -g iot-dev -n iris-dev-mqtt-1 | grep -i "external-company-bridge"
# Look for: "Bridge external-company-bridge: connected"
```

Check if external_integration_user exists on mqtt-2:
```bash
# Download password file from mqtt-2
az storage file download \
  --account-name irisstdev001 \
  --share-name iris-dev-mqtt-2-config \
  --path password.txt \
  --dest /tmp/password-mqtt-2.txt

cat /tmp/password-mqtt-2.txt | grep external_integration_user
# Should show hashed password for this user
```

### Configuration Not Updating

Force container restart after config change:
```bash
az container restart -g iot-dev -n iris-dev-mqtt-1
az container restart -g iot-dev -n iris-dev-mqtt-2
```

## File Share Contents

After successful deployment, file shares should contain:

### mqtt-1-config
```
mosquitto.conf  (generated from mosquitto-mqtt-1.conf.template)
password.txt    (hashed passwords for local users)
```

### mqtt-2-config
```
mosquitto.conf  (generated from mosquitto-mqtt-2.conf.template)
password.txt    (same as mqtt-1, shared)
```

### mqtt-certs (shared)
```
server.crt
server.key
ca.crt
```

### mqtt-bridge-certs (shared)
```
production_ca.crt
```

## Monitoring

### Key Metrics to Monitor

1. **Container Health**: Both containers should be "Running"
2. **Bridge Status**: Check logs for "Connection successful" messages
3. **Message Flow**: Verify messages are being bridged correctly
4. **Peer Connectivity**: mqtt-1 and mqtt-2 should stay connected

### Alerts to Configure

- Container restart events
- Bridge disconnection > 5 minutes
- High message queue depth
- Certificate expiration warnings (30 days)

## Updating Configuration

### Changing Bridge Topics

1. Edit `config/mosquitto-mqtt-1.conf.template` or `config/mosquitto-mqtt-2.conf.template`
2. Modify the `topic` lines under bridge configuration
3. Commit and push changes
4. Workflow automatically deploys and restarts containers

### Adding/Removing Users

1. Edit `config/env.dev` or `config/env.prd`
2. Update `LOCAL_USERS=deviceuser,adminuser,newuser`
3. Add corresponding GitHub secret `MQTT_USER_NEWUSER_PASSWORD`
4. Commit and push changes

### Changing Bridge Credentials

1. Update GitHub secret `MQTT_BRIDGE_PASSWORD`
2. Manually trigger workflow or push any config change
3. Containers will restart with new credentials

## Security Best Practices

1. **Never commit passwords** to git repository
2. **Rotate secrets regularly** (every 90 days)
3. **Use strong passwords** (32+ characters, random)
4. **Monitor access logs** for unauthorized attempts
5. **Update certificates** before expiration
6. **Use separate credentials** for each environment

## Support

For issues or questions:
1. Check container logs first
2. Review this deployment guide
3. Check GitHub Actions workflow runs
4. Contact DevOps team
