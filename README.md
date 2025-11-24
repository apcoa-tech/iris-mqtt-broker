# IRIS MQTT Broker

Custom Eclipse Mosquitto MQTT broker for the IRIS project with bridge configuration to production broker.

## Overview

This repository contains:
- **Custom Docker image** based on Eclipse Mosquitto 2.0.22 (Alpine 3.22.2)
- **Configuration templates** without sensitive data
- **Deployment scripts** for generating config with secrets from Azure Key Vault
- **GitHub Actions workflows** for automated building and deployment

The MQTT broker runs on Azure Container Instances with persistent storage backed by Azure File Shares.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ GitHub Repository (iris-mqtt-broker)               │
│  ├─ Dockerfile                                     │
│  ├─ Config Templates (no secrets)                  │
│  └─ Deployment Workflows                           │
└─────────────────────────────────────────────────────┘
                    │
                    │ Push triggers workflows
                    ▼
┌─────────────────────────────────────────────────────┐
│ GitHub Actions (OIDC authenticated)                │
│  1. Build Docker image → Push to ACR               │
│  2. Fetch secrets from Key Vault                   │
│  3. Generate mosquitto.conf + password.txt         │
│  4. Upload to Azure File Share                     │
│  5. Restart container                              │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│ Azure Container Instances                          │
│  ├─ Mosquitto container (custom image)             │
│  ├─ Mounts: config, data, certs file shares        │
│  ├─ Listens on port 8883 (MQTTS)                   │
│  └─ Bridges to production broker                   │
└─────────────────────────────────────────────────────┘
                    │
                    │ Bridge connection
                    ▼
┌─────────────────────────────────────────────────────┐
│ Production MQTT Broker                             │
│  Address: 3.121.198.76:8883                        │
│  Topics: Advantech/74FE4857C133/#                  │
│          Advantech/74FE4857C1B3/#                  │
└─────────────────────────────────────────────────────┘
```

## Repository Structure

```
iris-mqtt-broker/
├── docker/
│   ├── Dockerfile              # Custom Mosquitto image
│   └── bridge_certs/
│       └── production_ca.crt   # CA cert for remote broker (not secret)
├── config/
│   ├── mosquitto.conf.template # Config template (placeholders for secrets)
│   ├── env.template            # Environment config template
│   ├── env.dev                 # Dev environment config
│   ├── env.uat                 # UAT environment config (to be added)
│   └── env.prd                 # Production environment config (to be added)
├── scripts/
│   ├── generate-config.sh      # Generate config from template
│   └── generate-password-file.sh # Generate Mosquitto password file
├── .github/
│   └── workflows/
│       ├── build-image.yml     # Build and push Docker image
│       └── deploy-config.yml   # Deploy configuration to Azure
├── .gitignore
└── README.md
```

## Prerequisites

### Azure Resources (created by iris-container-instance-plugin)
- ✅ Resource Group: `iot-dev`
- ✅ Storage Account: `irisstdev001`
- ✅ File Shares: `mqtt-config`, `mqtt-data`, `mqtt-certs`
- ✅ Container Instance: `iris-dev-mqtt`
- ✅ Azure Container Registry: `irisacr`

### GitHub Secrets

**OIDC Authentication:**
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

**MQTT Passwords:**
- `MQTT_BRIDGE_PASSWORD` - Password for bridge connection to production broker
- `MQTT_USER_DEVICEUSER_PASSWORD` - Password for local user "deviceuser"
- `MQTT_USER_ADMINUSER_PASSWORD` - Password for local user "adminuser"

## Quick Start

### 1. Setup GitHub Secrets

Add these secrets to your GitHub repository:

**Via GitHub CLI:**
```bash
# Bridge password (from production broker)
gh secret set MQTT_BRIDGE_PASSWORD

# Local user passwords
gh secret set MQTT_USER_DEVICEUSER_PASSWORD
gh secret set MQTT_USER_ADMINUSER_PASSWORD

# OIDC credentials (if not already set)
gh secret set AZURE_CLIENT_ID
gh secret set AZURE_TENANT_ID
gh secret set AZURE_SUBSCRIPTION_ID
```

**Via GitHub Web UI:**
1. Go to repository **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Add each secret:
   - Name: `MQTT_BRIDGE_PASSWORD`, Value: `g4sbakTxxMjx8bVn`
   - Name: `MQTT_USER_DEVICEUSER_PASSWORD`, Value: `your_secure_password`
   - Name: `MQTT_USER_ADMINUSER_PASSWORD`, Value: `your_admin_password`

### 2. Upload Server Certificates

Upload your server certificates to the `mqtt-certs` file share:

```bash
STORAGE_ACCOUNT="irisstdev001"
STORAGE_KEY=$(az storage account keys list -g iot-dev -n $STORAGE_ACCOUNT --query '[0].value' -o tsv)

# Upload certificates
az storage file upload \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --share-name mqtt-certs \
  --source ca.crt

az storage file upload \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --share-name mqtt-certs \
  --source server.crt

az storage file upload \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --share-name mqtt-certs \
  --source server.key
```

### 3. Deploy

Push to main branch to trigger automated deployment:

```bash
git push origin main
```

Or manually trigger workflows:

```bash
# Build and push Docker image
gh workflow run build-image.yml

# Deploy configuration
gh workflow run deploy-config.yml
```

## Workflows

### Build Image Workflow

**Triggers:**
- Push to `main` branch (paths: `docker/**`)
- Pull requests
- Manual dispatch

**Steps:**
1. Build Docker image with custom Mosquitto
2. Tag with date + commit hash
3. Scan for vulnerabilities (Trivy)
4. Push to Azure Container Registry
5. Tag as `latest`

**Image naming:**
```
irisacr.azurecr.io/mosquitto:20250124-a1b2c3d4
irisacr.azurecr.io/mosquitto:latest
```

### Deploy Config Workflow

**Triggers:**
- Push to `main` branch (paths: `config/**`, `scripts/**`)
- Manual dispatch (select environment)

**Steps:**
1. Load environment configuration
2. Load secrets from GitHub Secrets
3. Generate `mosquitto.conf` from template
4. Generate `password.txt` with user credentials
5. Upload to Azure File Share
6. Restart container (optional)

**Manual deployment:**
```bash
gh workflow run deploy-config.yml \
  -f environment=dev \
  -f restart_container=true
```

## Configuration

### Environment Variables

Each environment has its own config file (`config/env.{dev,uat,prd}`):

```bash
# config/env.dev
ENVIRONMENT=dev
RESOURCE_GROUP=iot-dev
STORAGE_ACCOUNT=irisstdev001
CONTAINER_GROUP=iris-dev-mqtt
KEY_VAULT_NAME=iris-dev-keyvault
BRIDGE_REMOTE_ADDRESS=3.121.198.76:8883
BRIDGE_USERNAME=logforwarder
LOCAL_USERS=deviceuser,adminuser
```

### Mosquitto Configuration Template

The template (`config/mosquitto.conf.template`) uses placeholders:

```conf
# Bridge credentials (populated from GitHub Secrets)
remote_username ${BRIDGE_USERNAME}
remote_password ${BRIDGE_PASSWORD}

# Static configuration
listener 8883 0.0.0.0
bridge_cafile /mosquitto/bridge_certs/production_ca.crt
```

GitHub Actions replaces `${VARIABLE}` with values from GitHub Secrets.

## Security

✅ **No secrets in Git** - All secrets stored in GitHub Secrets
✅ **OIDC authentication** - No long-lived credentials in GitHub
✅ **Secrets masked in logs** - GitHub Actions masks sensitive data
✅ **File share access restricted** - Only workflow and container can access
✅ **TLS encryption** - All MQTT traffic encrypted (port 8883)
✅ **Static analysis** - Trivy scans Docker images for vulnerabilities

### What's Stored Where

| Item | Location | Sensitive? |
|------|----------|-----------|
| Bridge password | GitHub Secrets | ✅ Yes |
| Local user passwords | GitHub Secrets | ✅ Yes |
| Server private key | Azure File Share (mqtt-certs) | ✅ Yes |
| Server certificate | Azure File Share (mqtt-certs) | ⚠️  Semi-public |
| Bridge CA certificate | Docker image | ❌ No (public CA) |
| Config template | Git repository | ❌ No (no secrets) |
| Generated config | Azure File Share (mqtt-config) | ✅ Yes (contains passwords) |

### Migration to Key Vault (Optional)

If you want to migrate to Azure Key Vault later for better secret management:
1. Create Key Vault: `az keyvault create --name iris-dev-keyvault -g iot-dev`
2. Grant workflow access via OIDC
3. Update workflow to fetch from Key Vault instead of GitHub Secrets
4. Move secrets from GitHub to Key Vault

## Local Development

### Build Docker Image Locally

```bash
cd docker
docker build -t mosquitto:local .
```

### Generate Config Locally

```bash
# Set secrets as environment variables
export BRIDGE_USERNAME="logforwarder"
export BRIDGE_PASSWORD="your_password"
export PASSWORD_DEVICEUSER="device_password"

# Generate config
./scripts/generate-config.sh config/mosquitto.conf.template /tmp/mosquitto.conf

# Generate password file
./scripts/generate-password-file.sh /tmp/password.txt "deviceuser"
```

### Test Locally

```bash
docker run -d \
  --name mosquitto-test \
  -p 8883:8883 \
  -v $(pwd)/config:/mosquitto/config \
  -v $(pwd)/certs:/mosquitto/certs \
  mosquitto:local

# Check logs
docker logs -f mosquitto-test

# Test connection
mosquitto_pub -h localhost -p 8883 \
  --cafile certs/ca.crt \
  -u deviceuser -P device_password \
  -t "test/topic" -m "Hello MQTT"
```

## Monitoring

### View Container Logs

```bash
# Via Azure CLI
az container logs -g iot-dev -n iris-dev-mqtt --follow

# Via Azure Portal
# Container Instances > iris-dev-mqtt > Containers > Logs
```

### Check Container Status

```bash
az container show \
  -g iot-dev \
  -n iris-dev-mqtt \
  --query instanceView.state
```

### Check Bridge Connection

Look for these log messages:

```
✅ Good: "Connecting bridge production-bridge (3.121.198.76:8883)"
✅ Good: "Connection production-bridge established"
❌ Bad:  "Connection production-bridge failed: Connection refused"
❌ Bad:  "Bridge production-bridge doing local bridge_attempt_unsubscribe"
```

## Troubleshooting

### Issue: Container won't start

```bash
# Check container logs
az container logs -g iot-dev -n iris-dev-mqtt

# Common causes:
# - Invalid mosquitto.conf syntax
# - Missing certificates
# - File share not mounted
```

### Issue: Bridge not connecting

```bash
# Verify bridge configuration
az storage file download \
  --account-name irisstdev001 \
  --share-name mqtt-config \
  --path mosquitto.conf

# Check:
# - Bridge password is correct
# - Remote broker address is correct (3.121.198.76:8883)
# - CA certificate exists
# - Network connectivity (firewall rules)
```

### Issue: Authentication failures

```bash
# Regenerate password file
gh workflow run deploy-config.yml -f environment=dev

# Verify users exist in password.txt
az storage file download \
  --account-name irisstdev001 \
  --share-name mqtt-config \
  --path password.txt
```

### Issue: Workflow fails

```bash
# Check workflow logs
gh run list --workflow=deploy-config.yml
gh run view <run-id> --log

# Common causes:
# - Key Vault secrets missing
# - OIDC authentication failed
# - File share not accessible
```

## Multi-Environment Deployment

To deploy to UAT or Production:

### 1. Create environment config

```bash
# Copy and modify
cp config/env.dev config/env.prd

# Update values for production
vi config/env.prd
```

### 2. Create Key Vault secrets

```bash
# Production Key Vault
az keyvault secret set \
  --vault-name iris-prd-keyvault \
  --name mqtt-bridge-password \
  --value "PRODUCTION_PASSWORD"
```

### 3. Deploy

```bash
gh workflow run deploy-config.yml -f environment=prd
```

## Cost Estimation

| Resource | Monthly Cost (EUR) |
|----------|-------------------|
| Container Instance (1 vCPU, 1.5GB, 24/7) | €37-44 |
| File Shares (3 x 1GB) | €0.30 |
| Container Registry (Basic tier) | €4.24 |
| **Total** | **€42-48** |

## Maintenance

### Updating Mosquitto Version

1. Update `docker/Dockerfile`: Change `FROM eclipse-mosquitto:X.Y.Z`
2. Push to trigger image build
3. Update container instance to use new image

### Rotating Passwords

```bash
# Update GitHub Secret
gh secret set MQTT_BRIDGE_PASSWORD

# Or via GitHub Web UI: Settings → Secrets → Actions → Update secret

# Redeploy config (triggers automatically on push, or manually)
gh workflow run deploy-config.yml -f environment=dev -f restart_container=true
```

### Certificate Renewal

```bash
# Upload new certificates
az storage file upload \
  --account-name irisstdev001 \
  --share-name mqtt-certs \
  --source server.crt \
  --overwrite

# Restart container
az container restart -g iot-dev -n iris-dev-mqtt
```

## Related Repositories

- **iris-container-instance-plugin** - Terraform infrastructure for Azure Container Instances
- **iris-blob-storage-plugin** - Terraform infrastructure for Azure Storage (file shares)
- **iris-main** - Main IRIS infrastructure (VNet, resource groups)

## Contributing

1. Create feature branch
2. Make changes
3. Test locally
4. Create PR
5. Workflows run on PR (build image, validate config)
6. Merge to main triggers deployment

## Support

For issues or questions:
- Check troubleshooting section above
- Review workflow logs: `gh run list`
- Check Azure container logs: `az container logs -g iot-dev -n iris-dev-mqtt`
- Contact APCOA IoT team
