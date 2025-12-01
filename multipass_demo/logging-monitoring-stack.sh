#!/usr/bin/env bash
set -e

echo "=== Detecting system architecture ==="
ARCH=$(uname -m)

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
  PROM_ARCH="linux-arm64"
  NODE_ARCH="linux-arm64"
  LOKI_ARCH="linux-arm64"
elif [ "$ARCH" = "x86_64" ]; then
  PROM_ARCH="linux-amd64"
  NODE_ARCH="linux-amd64"
  LOKI_ARCH="linux-amd64"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

echo "Detected CPU architecture: $ARCH"

echo "=== Updating system ==="
sudo apt update -y
sudo apt install -y curl wget unzip gnupg apt-transport-https software-properties-common

##########################################################
# 1. Install Grafana
##########################################################
echo "=== Installing Grafana ==="
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt update -y
sudo apt install -y grafana

sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

##########################################################
# 2. Install Prometheus
##########################################################
echo "=== Installing Prometheus ==="

PROM_VERSION="2.48.0"
wget -q https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.${PROM_ARCH}.tar.gz
tar -xzf prometheus-${PROM_VERSION}.${PROM_ARCH}.tar.gz
sudo rm -rf /opt/prometheus
sudo mv prometheus-${PROM_VERSION}.${PROM_ARCH} /opt/prometheus

sudo tee /etc/systemd/system/prometheus.service >/dev/null <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
ExecStart=/opt/prometheus/prometheus --config.file=/opt/prometheus/prometheus.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF | sudo tee /opt/prometheus/prometheus.yml
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node"
    static_configs:
      - targets: ["localhost:9100"]
EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

##########################################################
# 3. Install Node Exporter
##########################################################
echo "=== Installing Node Exporter ==="

NODE_VERSION="1.8.1"
wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_VERSION}/node_exporter-${NODE_VERSION}.${NODE_ARCH}.tar.gz
tar -xzf node_exporter-${NODE_VERSION}.${NODE_ARCH}.tar.gz
sudo rm -rf /opt/node_exporter
sudo mv node_exporter-${NODE_VERSION}.${NODE_ARCH} /opt/node_exporter

sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<EOF
[Unit]
Description=Node Exporter

[Service]
ExecStart=/opt/node_exporter/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

##########################################################
# 4. Install Loki (single node mode)
##########################################################
echo "=== Installing Loki ==="

LOKI_VERSION="2.9.0"
wget -q https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-${LOKI_ARCH}.zip
unzip -q loki-${LOKI_ARCH}.zip
chmod +x loki-${LOKI_ARCH}
sudo mv loki-${LOKI_ARCH} /usr/local/bin/loki

# Create Loki directories
sudo mkdir -p /tmp/loki/index /tmp/loki/cache /tmp/loki/chunks /tmp/loki/compactor
sudo chmod -R 777 /tmp/loki

cat <<EOF | sudo tee /etc/loki.yaml
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules

compactor:
  working_directory: /tmp/loki/compactor
  shared_store: filesystem

schema_config:
  configs:
    - from: "2023-01-01"
      store: boltdb-shipper
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /tmp/loki/index
    cache_location: /tmp/loki/cache
    shared_store: filesystem

  filesystem:
    directory: /tmp/loki/chunks

ingester:
  chunk_idle_period: 3m
  max_chunk_age: 1h
  lifecycler:
    ring:
      replication_factor: 1
      kvstore:
        store: inmemory

limits_config:
  allow_structured_metadata: true
EOF

sudo tee /etc/systemd/system/loki.service >/dev/null <<EOF
[Unit]
Description=Loki Log Aggregation
After=network.target

[Service]
ExecStart=/usr/local/bin/loki -config.file=/etc/loki.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable loki
sudo systemctl start loki

##########################################################
# 5. Install Promtail (journal + /var/log/*.log)
##########################################################
echo "=== Installing Promtail ==="

wget -q https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/promtail-${LOKI_ARCH}.zip
unzip -q promtail-${LOKI_ARCH}.zip
chmod +x promtail-${LOKI_ARCH}
sudo mv promtail-${LOKI_ARCH} /usr/local/bin/promtail

cat <<EOF | sudo tee /etc/promtail.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: system-logs
    static_configs:
      - targets: ["localhost"]
        labels:
          job: system
          host: logvm
          __path__: /var/log/*.log

  - job_name: journald
    journal:
      path: /var/log/journal
    labels:
      job: journald
      host: logvm
EOF

sudo tee /etc/systemd/system/promtail.service >/dev/null <<EOF
[Unit]
Description=Promtail Log Collector

[Service]
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail

echo "===================================================="
echo "SETUP COMPLETED!"
echo "Grafana:       http://<vm-ip>:3000 (admin/admin)"
echo "Prometheus:    http://<vm-ip>:9090"
echo "Loki:          http://<vm-ip>:3100/loki/api/v1/query"
echo "Promtail:      http://<vm-ip>:9080"
echo "NodeExporter:  http://<vm-ip>:9100/metrics"
echo "===================================================="
