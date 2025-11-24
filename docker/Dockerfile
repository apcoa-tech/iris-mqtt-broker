# Custom Mosquitto MQTT Broker for IRIS
# Based on Eclipse Mosquitto 2.0.22 (Alpine 3.22.2)

FROM eclipse-mosquitto:2.0.22

LABEL maintainer="APCOA IRIS Team"
LABEL description="Custom Mosquitto MQTT broker with bridge configuration for IRIS project"
LABEL version="1.0.1"

# Copy static bridge CA certificate (not sensitive, rarely changes)
# This is the CA cert for verifying the remote production broker
COPY bridge_certs/production_ca.crt /mosquitto/bridge_certs/production_ca.crt

# Create necessary directories
RUN mkdir -p /mosquitto/config \
    /mosquitto/data \
    /mosquitto/certs \
    /mosquitto/bridge_certs

# Set proper permissions
RUN chown -R mosquitto:mosquitto /mosquitto/config \
    /mosquitto/data \
    /mosquitto/certs \
    /mosquitto/bridge_certs

# Set proper file permissions for bridge CA cert
RUN chmod 644 /mosquitto/bridge_certs/production_ca.crt

# Expose MQTTS port
EXPOSE 8883

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD mosquitto_sub -t '$SYS/#' -C 1 -i healthcheck || exit 1

# Use mosquitto user
USER mosquitto

# Default command (config will be mounted from Azure File Share)
CMD ["/usr/sbin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
