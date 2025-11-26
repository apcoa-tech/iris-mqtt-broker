# Azure File Share Certificate Management for MQTT Broker

Commands for managing certificates stored in Azure File Shares for the IRIS MQTT broker infrastructure.

## Overview

The MQTT broker uses Azure File Shares to store certificates, configurations, data, and logs. This document provides commands for finding, downloading, and managing certificates in these shares.

## File Share Structure

Each environment (dev/uat/prd) has the following file shares:
- `iris-{env}-mqtt-certs` - Shared certificates (ca.crt, server.crt, server.key)
- `iris-{env}-mqtt-1-config` - mqtt-1 configuration files
- `iris-{env}-mqtt-2-config` - mqtt-2 configuration files
- `iris-{env}-mqtt-1-data` - mqtt-1 persistent data
- `iris-{env}-mqtt-2-data` - mqtt-2 persistent data
- `iris-{env}-mqtt-1-log` - mqtt-1 logs
- `iris-{env}-mqtt-2-log` - mqtt-2 logs

## Prerequisites

1. Azure CLI installed and authenticated
2. Access to the resource group (iot-dev, iot-uat, or iot-prd)
3. Storage account name (e.g., irisstdev001 for dev)

## Common Operations

### 1. Find Storage Account and File Shares

```bash
# Set environment
ENV=dev  # or uat, prd
RG=iot-${ENV}

# Find storage account
STORAGE_ACCOUNT=$(az storage account list -g $RG --query "[].name" -o tsv)
echo "Storage Account: $STORAGE_ACCOUNT"

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
  --resource-group $RG \
  --account-name $STORAGE_ACCOUNT \
  --query '[0].value' -o tsv)

# List all file shares
az storage share list \
  --account-name $STORAGE_ACCOUNT \
  --account-key "$STORAGE_KEY" \
  --query "[].name" -o tsv
```

### 2. List Certificate Files

```bash
# List certificates in the main certs share
az storage file list \
  --account-name $STORAGE_ACCOUNT \
  --account-key "$STORAGE_KEY" \
  --share-name "iris-${ENV}-mqtt-certs" \
  --output table

# Expected files:
# - ca.crt (CA certificate)
# - server.crt (Server certificate)
# - server.key (Server private key)
```

### 3. Download Certificates

```bash
# Create local directory for downloads
mkdir -p /tmp/mqtt-certs-${ENV}

# Download all certificates
for file in ca.crt server.crt server.key; do
  az storage file download \
    --account-name $STORAGE_ACCOUNT \
    --account-key "$STORAGE_KEY" \
    --share-name "iris-${ENV}-mqtt-certs" \
    --path "$file" \
    --dest "/tmp/mqtt-certs-${ENV}/$file"
  echo "Downloaded $file"
done
```

### 4. Verify Certificate Validity

```bash
# Verify CA certificate
openssl x509 -in /tmp/mqtt-certs-${ENV}/ca.crt -text -noout | head -15

# Verify server certificate
openssl x509 -in /tmp/mqtt-certs-${ENV}/server.crt -text -noout | head -15

# Check if ca.crt is a single certificate (should return 1)
grep -c "BEGIN CERTIFICATE" /tmp/mqtt-certs-${ENV}/ca.crt

# Verify certificate chain
openssl verify -CAfile /tmp/mqtt-certs-${ENV}/ca.crt /tmp/mqtt-certs-${ENV}/server.crt
```

### 5. Delete Certificates

**⚠️ Warning:** Only delete certificates if you plan to immediately re-deploy them via the workflow!

```bash
# Delete all certificates from the share
for file in ca.crt server.crt server.key; do
  az storage file delete \
    --account-name $STORAGE_ACCOUNT \
    --account-key "$STORAGE_KEY" \
    --share-name "iris-${ENV}-mqtt-certs" \
    --path "$file"
  echo "Deleted $file"
done
```

### 6. Trigger Certificate Re-deployment

After deleting certificates, trigger the deployment workflow:

```bash
gh workflow run deploy-config.yml \
  -R apcoa-tech/iris-mqtt-broker \
  -f environment=${ENV}

# Watch the workflow
gh run watch $(gh run list -R apcoa-tech/iris-mqtt-broker -w deploy-config.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

## Troubleshooting

### Common Issues

#### Issue: Containers in CrashLoopBackOff

**Symptom:** Containers repeatedly restart with exit code 1 or 3

**Possible Causes:**
1. ca.crt contains certificate chain instead of just CA cert
2. Certificates are corrupted or truncated
3. Certificate format issues (wrong line endings)

**Diagnosis:**
```bash
# Check container logs
az container logs -g iot-${ENV} -n iris-${ENV}-mqtt-1 | tail -50
az container logs -g iot-${ENV} -n iris-${ENV}-mqtt-2 | tail -50

# Look for errors like:
# - "Error: Unable to load CA certificates"
# - "error:04800066:PEM routines::bad end line"
# - "error:05880009:x509 certificate routines::PEM lib"
```

**Fix:**
1. Download and verify certificates (see sections 3 & 4)
2. If ca.crt has >1 certificate: delete all certs and re-deploy
3. Use production certificates from `prd_broker_certs/` directory

#### Issue: Certificate Chain in ca.crt

**Diagnosis:**
```bash
# Download ca.crt
az storage file download \
  --account-name $STORAGE_ACCOUNT \
  --account-key "$STORAGE_KEY" \
  --share-name "iris-${ENV}-mqtt-certs" \
  --path ca.crt \
  --dest /tmp/ca.crt

# Check certificate count (should be 1, not 2)
grep -c "BEGIN CERTIFICATE" /tmp/ca.crt
```

**Fix:**
```bash
# Delete and re-deploy (see sections 5 & 6)
```

## Certificate Requirements

### Production Certificates (Recommended)

The repository contains production certificates in `prd_broker_certs/`:
- `ca.crt` - CA certificate only (1139 bytes, 20 lines)
- `server.crt` - Server certificate (1111 bytes, 19 lines)
- `server.key` - Stored in GitHub Secrets as `MQTT_SERVER_KEY`

### Self-Signed Certificates (Dev/UAT fallback)

The workflow can generate self-signed certificates if production certs are not available:
- Automatically generated during deployment
- Valid for 10 years
- Uses 2048-bit RSA keys

## Workflow Certificate Logic

The deploy-config.yml workflow follows this logic:

1. **Check if certificates exist** in Azure File Share
2. If **NOT exist**:
   - Try to use production certificates from `prd_broker_certs/`
   - If production certs unavailable: generate self-signed
3. If **exist**: Skip certificate deployment (use existing)

To force re-deployment of certificates:
- Delete existing certificates (see section 5)
- Re-run the workflow (see section 6)

## Security Notes

1. **Private keys**: Never commit `server.key` to git
2. **GitHub Secrets**: Private key stored as `MQTT_SERVER_KEY`
3. **Access control**: Limit access to storage account keys
4. **Certificate rotation**: Plan to rotate certificates before expiry
5. **Git history**: If private key was committed, use `git filter-branch` to remove

## Related Files

- `.github/workflows/deploy-config.yml` - Certificate deployment workflow
- `config/mosquitto-mqtt-1.conf.template` - Mosquitto configuration template
- `prd_broker_certs/` - Production certificate directory (ca.crt, server.crt only)
- `.gitignore` - Ensures private keys are never committed
