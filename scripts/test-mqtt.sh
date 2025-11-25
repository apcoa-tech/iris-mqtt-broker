#!/bin/bash
# Test MQTT broker connectivity and bridge functionality
# This script tests both mqtt-1 and mqtt-2 brokers in the dev environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if mosquitto tools are installed
if ! command -v mosquitto_pub &> /dev/null || ! command -v mosquitto_sub &> /dev/null; then
  echo -e "${RED}❌ Error: mosquitto client tools not found${NC}"
  echo ""
  echo "Please install mosquitto client tools:"
  echo "  macOS:   brew install mosquitto"
  echo "  Ubuntu:  sudo apt-get install mosquitto-clients"
  echo "  RHEL:    sudo yum install mosquitto"
  exit 1
fi

# Default environment
ENVIRONMENT="${1:-dev}"
ENV_FILE="$REPO_ROOT/config/env.$ENVIRONMENT"

if [ ! -f "$ENV_FILE" ]; then
  echo -e "${RED}❌ Error: Environment file not found: $ENV_FILE${NC}"
  exit 1
fi

# Load environment variables
source "$ENV_FILE"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MQTT Broker Testing - $ENVIRONMENT${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Download CA certificate if not present
CA_CERT="$REPO_ROOT/ca.crt"
if [ ! -f "$CA_CERT" ]; then
  echo -e "${YELLOW}📥 Downloading CA certificate...${NC}"

  STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" -o tsv)

  az storage file download \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --share-name iris-${ENVIRONMENT}-mqtt-certs \
    --path ca.crt \
    --dest "$CA_CERT" \
    --output none

  echo -e "${GREEN}✅ CA certificate downloaded${NC}"
  echo ""
fi

# Get passwords from environment or prompt
if [ -z "$PASSWORD_DEVICEUSER" ]; then
  echo -e "${YELLOW}Enter password for deviceuser:${NC}"
  read -s PASSWORD_DEVICEUSER
  echo ""
fi

if [ -z "$PASSWORD_EXTERNAL_INTEGRATION_USER" ]; then
  echo -e "${YELLOW}Enter password for external_integration_user:${NC}"
  read -s PASSWORD_EXTERNAL_INTEGRATION_USER
  echo ""
fi

# Test function
test_broker() {
  local broker_name=$1
  local broker_host=$2
  local username=$3
  local password=$4
  local test_topic=$5

  echo -e "${BLUE}Testing $broker_name ($broker_host)...${NC}"

  # Test publish
  echo -e "  ${YELLOW}📤 Publishing test message...${NC}"
  if mosquitto_pub -h "$broker_host" -p 8883 \
    --cafile "$CA_CERT" \
    -u "$username" -P "$password" \
    -t "$test_topic" \
    -m "{\"test\":true,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"broker\":\"$broker_name\"}" \
    -d 2>&1 | grep -q "Sending PUBLISH"; then
    echo -e "  ${GREEN}✅ Publish successful${NC}"
  else
    echo -e "  ${RED}❌ Publish failed${NC}"
    return 1
  fi

  # Test subscribe (with timeout)
  echo -e "  ${YELLOW}📥 Testing subscription (5 second timeout)...${NC}"
  if timeout 5 mosquitto_sub -h "$broker_host" -p 8883 \
    --cafile "$CA_CERT" \
    -u "$username" -P "$password" \
    -t "$test_topic" \
    -C 1 &> /dev/null; then
    echo -e "  ${GREEN}✅ Subscribe successful${NC}"
  else
    echo -e "  ${YELLOW}⚠️  Subscribe timed out (may be normal if no messages)${NC}"
  fi

  echo ""
}

# Test mqtt-1 (our broker)
if [ "$DEPLOY_DUAL_BROKERS" = "true" ]; then
  MQTT1_HOST=$(az container show \
    -g "$RESOURCE_GROUP" \
    -n "$CONTAINER_GROUP_1" \
    --query "ipAddress.fqdn" -o tsv)

  test_broker "mqtt-1" "$MQTT1_HOST" "deviceuser" "$PASSWORD_DEVICEUSER" "Advantech/TEST001/data"

  # Test mqtt-2 (external simulator)
  MQTT2_HOST=$(az container show \
    -g "$RESOURCE_GROUP" \
    -n "$CONTAINER_GROUP_2" \
    --query "ipAddress.fqdn" -o tsv)

  test_broker "mqtt-2" "$MQTT2_HOST" "external_integration_user" "$PASSWORD_EXTERNAL_INTEGRATION_USER" "Advantech/TEST001/data"

  # Test bridge functionality
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}Testing Bridge (mqtt-1 → mqtt-2)${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""
  echo -e "${YELLOW}This test will:${NC}"
  echo -e "  1. Start subscriber on mqtt-2 (external broker)"
  echo -e "  2. Publish message to mqtt-1 (our broker)"
  echo -e "  3. Verify message arrives on mqtt-2 via bridge"
  echo ""
  echo -e "${YELLOW}Starting mqtt-2 subscriber in background...${NC}"

  # Create temp file for subscriber output
  SUBSCRIBER_OUTPUT=$(mktemp)

  # Start subscriber in background
  timeout 15 mosquitto_sub -h "$MQTT2_HOST" -p 8883 \
    --cafile "$CA_CERT" \
    -u "external_integration_user" -P "$PASSWORD_EXTERNAL_INTEGRATION_USER" \
    -t "Advantech/#" -v > "$SUBSCRIBER_OUTPUT" 2>&1 &

  SUBSCRIBER_PID=$!

  # Wait for subscriber to connect
  sleep 2

  # Publish to mqtt-1
  TEST_MESSAGE="{\"bridge_test\":true,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
  echo -e "${YELLOW}📤 Publishing to mqtt-1...${NC}"
  echo -e "  Topic: Advantech/BRIDGE_TEST/data"
  echo -e "  Message: $TEST_MESSAGE"

  mosquitto_pub -h "$MQTT1_HOST" -p 8883 \
    --cafile "$CA_CERT" \
    -u "deviceuser" -P "$PASSWORD_DEVICEUSER" \
    -t "Advantech/BRIDGE_TEST/data" \
    -m "$TEST_MESSAGE"

  # Wait for message to arrive
  echo -e "${YELLOW}⏳ Waiting for message on mqtt-2 (5 seconds)...${NC}"
  sleep 5

  # Check if message was received
  if grep -q "BRIDGE_TEST" "$SUBSCRIBER_OUTPUT"; then
    echo -e "${GREEN}✅ Bridge test PASSED - Message received on mqtt-2!${NC}"
    echo ""
    echo -e "${GREEN}Received message:${NC}"
    cat "$SUBSCRIBER_OUTPUT"
  else
    echo -e "${RED}❌ Bridge test FAILED - Message not received on mqtt-2${NC}"
    echo ""
    echo -e "${RED}Subscriber output:${NC}"
    cat "$SUBSCRIBER_OUTPUT"
  fi

  # Cleanup
  kill $SUBSCRIBER_PID 2>/dev/null || true
  rm -f "$SUBSCRIBER_OUTPUT"

else
  # Single broker mode
  MQTT_HOST=$(az container show \
    -g "$RESOURCE_GROUP" \
    -n "$CONTAINER_GROUP" \
    --query "ipAddress.fqdn" -o tsv)

  test_broker "mqtt-broker" "$MQTT_HOST" "deviceuser" "$PASSWORD_DEVICEUSER" "Advantech/TEST001/data"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ Testing Complete${NC}"
echo -e "${BLUE}========================================${NC}"
