#!/bin/bash
# Generate mosquitto.conf from template with secrets from environment variables
# This script is executed by GitHub Actions workflow

set -e

# Check required environment variables
required_vars=(
  "BRIDGE_USERNAME"
  "BRIDGE_PASSWORD"
)

for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Error: $var is not set"
    exit 1
  fi
done

# Template file
TEMPLATE_FILE="${1:-config/mosquitto.conf.template}"
OUTPUT_FILE="${2:-/tmp/mosquitto.conf}"

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "Error: Template file $TEMPLATE_FILE not found"
  exit 1
fi

echo "Generating mosquitto.conf from template..."

# Replace placeholders with environment variables
envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "✅ Configuration generated: $OUTPUT_FILE"

# Validate configuration (check for unreplaced placeholders)
if grep -q '\${' "$OUTPUT_FILE"; then
  echo "⚠️  Warning: Configuration contains unreplaced placeholders:"
  grep '\${' "$OUTPUT_FILE"
fi

# Display config (with passwords masked)
echo ""
echo "Generated configuration (passwords masked):"
echo "=========================================="
sed 's/\(password\s\+\).*/\1***MASKED***/' "$OUTPUT_FILE"
echo "=========================================="
