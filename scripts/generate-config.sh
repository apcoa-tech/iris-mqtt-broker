#!/bin/bash
# Generate mosquitto.conf from template with secrets from environment variables
# This script is executed by GitHub Actions workflow

set -e

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
  echo "❌ Error: Configuration contains unreplaced placeholders:"
  grep '\${' "$OUTPUT_FILE"
  echo ""
  echo "This likely means required environment variables are not set."
  echo "Please check the workflow and ensure all variables used in the template are exported."
  exit 1
fi

# Display config (with passwords masked)
echo ""
echo "Generated configuration (passwords masked):"
echo "=========================================="
sed 's/\(password\s\+\).*/\1***MASKED***/' "$OUTPUT_FILE"
echo "=========================================="
