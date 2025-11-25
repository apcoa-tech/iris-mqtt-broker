#!/bin/bash
# Generate Mosquitto password file from Key Vault secrets
# This script is executed by GitHub Actions workflow

set -e

OUTPUT_FILE="${1:-/tmp/password.txt}"
USERS="${2:-deviceuser,adminuser}"

echo "Generating password file for users: $USERS"

# Remove existing password file
rm -f "$OUTPUT_FILE"

# Split users by comma and create password entries
IFS=',' read -ra USER_ARRAY <<< "$USERS"

first_user=true
for username in "${USER_ARRAY[@]}"; do
  # Get password from environment variable (set by workflow from Key Vault)
  password_var="PASSWORD_${username^^}"
  password="${!password_var}"

  if [ -z "$password" ]; then
    echo "⚠️  Warning: Password for user '$username' not found in $password_var"
    continue
  fi

  echo "Adding user: $username"

  # Use -c flag for first user to create the file
  if [ "$first_user" = true ]; then
    docker run --rm \
      -v "$(dirname "$OUTPUT_FILE"):/tmp" \
      eclipse-mosquitto:2.0.22 \
      mosquitto_passwd -c -b "/tmp/$(basename "$OUTPUT_FILE")" "$username" "$password"
    first_user=false
  else
    docker run --rm \
      -v "$(dirname "$OUTPUT_FILE"):/tmp" \
      eclipse-mosquitto:2.0.22 \
      mosquitto_passwd -b "/tmp/$(basename "$OUTPUT_FILE")" "$username" "$password"
  fi
done

if [ -f "$OUTPUT_FILE" ]; then
  echo "✅ Password file generated: $OUTPUT_FILE"
  echo "Users: $(wc -l < "$OUTPUT_FILE")"
else
  echo "❌ Error: Password file not created"
  exit 1
fi
