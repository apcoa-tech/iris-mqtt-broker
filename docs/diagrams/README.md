# MQTT Broker Deployment Architecture Diagrams

This directory contains PlantUML diagrams documenting the MQTT broker deployment architecture and workflows.

## Diagrams

### 1. mqtt-deployment-architecture.puml
**Comprehensive architecture diagram** showing:
- All GitHub repositories involved
- Azure resources (Storage Account, Container Instances, File Shares)
- How certificates are deployed from `prd_broker_certs/`
- How GitHub Secrets are used (especially `MQTT_SERVER_KEY`)
- All 7 file shares and their purposes
- Container mounts and relationships
- The workflow steps from trigger to completion
- Security features and notes

### 2. workflow-sequence.puml
**Sequential workflow diagram** showing:
- Step-by-step execution of the deploy-config.yml workflow
- Authentication flow with Azure OIDC
- Certificate deployment decision (exist vs. not exist)
- Configuration generation with envsubst
- File uploads to Azure Storage
- Container restart process
- Mount points and startup sequence
- Bridge connection establishment

## Viewing the Diagrams

### Option 1: VS Code (Recommended)
Install the PlantUML extension:
1. Install extension: `PlantUML` by jebbs
2. Open any `.puml` file
3. Press `Alt+D` to preview

### Option 2: Online PlantUML Editor
1. Go to https://www.plantuml.com/plantuml/uml/
2. Copy the content of the `.puml` file
3. Paste and view

### Option 3: Command Line (requires PlantUML)
```bash
# Install PlantUML (macOS)
brew install plantuml

# Generate PNG
plantuml mqtt-deployment-architecture.puml
plantuml workflow-sequence.puml

# Generate SVG
plantuml -tsvg mqtt-deployment-architecture.puml
plantuml -tsvg workflow-sequence.puml
```

## Key Architecture Components

### Repositories
1. **iris-mqtt-broker**: Main repo with workflow, configs, and production certificates
2. **iris-container-instance-plugin**: Terraform for container infrastructure
3. **iris-blob-storage-plugin**: Terraform for file share infrastructure

### Azure File Shares (7 total)
1. **iris-dev-mqtt-certs**: Shared certificates for both brokers
2. **iris-dev-mqtt-1-config**: mqtt-1 configuration files
3. **iris-dev-mqtt-2-config**: mqtt-2 configuration files
4. **iris-dev-mqtt-1-data**: mqtt-1 persistent data
5. **iris-dev-mqtt-2-data**: mqtt-2 persistent data
6. **iris-dev-mqtt-1-log**: mqtt-1 logs
7. **iris-dev-mqtt-2-log**: mqtt-2 logs

### Certificate Management
- **Public certificates** (ca.crt, server.crt): Stored in `prd_broker_certs/` directory
- **Private key** (server.key): Stored in GitHub Secret `MQTT_SERVER_KEY`
- **Deployed to**: `iris-dev-mqtt-certs` file share
- **Mounted as**: Read-only at `/mosquitto/certs`

### Workflow Triggers
1. Push to main branch
2. Manual workflow dispatch
3. workflow_dispatch event

### Security Features
- OIDC authentication with Azure
- Private keys never committed to git
- Private keys removed from git history
- TLS 1.3 for all connections
- Password authentication required
- Read-only certificate mounts
- Secrets stored in GitHub Secrets

## Deployment Flow Summary

1. **Infrastructure Creation** (One-time with Terraform):
   - Create 7 file shares (blob-storage-plugin)
   - Create 2 container instances (container-instance-plugin)

2. **Configuration Deployment** (Via GitHub Actions workflow):
   - Check if certificates exist in Azure
   - If not exist: Deploy production certificates from repo + secret
   - Generate configurations from templates
   - Upload configurations to file shares
   - Restart containers
   - Verify containers are running

3. **Container Startup**:
   - Mount all file shares
   - Load certificates (ca.crt, server.crt, server.key)
   - Load configuration (mosquitto.conf)
   - Load passwords (password.txt)
   - Start Mosquitto broker with TLS on port 8883
   - Establish bridge connection between mqtt-1 and mqtt-2

## Related Documentation

- **Certificate Management**: `../azure-fileshare-certs.md`
- **Workflow File**: `../../.github/workflows/deploy-config.yml`
- **Mosquitto Config Templates**: `../../config/mosquitto-mqtt-*.conf.template`
- **Production Certificates**: `../../prd_broker_certs/`

## Troubleshooting

Common issues and their locations in the diagrams:

1. **Certificate errors**: See "Certificate Deployment" section in sequence diagram
2. **Container crashes**: Check mount points in architecture diagram
3. **Bridge connection fails**: See bridge configuration in architecture diagram
4. **Missing secrets**: Check GitHub Secrets section in both diagrams

## Updates

When updating the architecture:
1. Update the relevant `.puml` file
2. Regenerate the diagram images
3. Update this README if adding new diagrams
4. Commit both source and generated images (if applicable)

---

Last Updated: 2025-11-26
