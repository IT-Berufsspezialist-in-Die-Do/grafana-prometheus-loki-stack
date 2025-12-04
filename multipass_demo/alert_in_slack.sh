#!/usr/bin/env bash
set -e

echo "=== Detecting system architecture ==="
ARCH=$(uname -m)

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
  AM_ARCH="linux-arm64"
elif [ "$ARCH" = "x86_64" ]; then
  AM_ARCH="linux-amd64"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

echo "Detected: $ARCH"

##########################################################
# 1. Install Alertmanager
##########################################################
echo "=== Installing Alertmanager ==="

AM_VERSION="0.27.0"

wget -q https://github.com/prometheus/alertmanager/releases/download/v${AM_VERSION}/alertmanager-${AM_VERSION}.${AM_ARCH}.tar.gz
tar -xzf alertmanager-${AM_VERSION}.${AM_ARCH}.tar.gz

sudo rm -rf /opt/alertmanager
sudo mv alertmanager-${AM_VERSION}.${AM_ARCH} /opt/alertmanager

sudo mkdir -p /opt/alertmanager/data

##########################################################
# 2. Create Alertmanager Configuration
##########################################################

echo "=== Writing Alertmanager configuration ==="

sudo tee /opt/alertmanager/alertmanager.yml >/dev/null <<EOF
global:
  resolve_timeout: 5m

route:
  receiver: slack-notifications

receivers:
  - name: slack-notifications
    slack_configs:
      - channel: '#test'  
        api_url: 'https://hooks.slack.com/services/DEIN/SLACK/WEBHOOK'
        send_resolved: true
        title: |-
          [{{ .Status | toUpper }}] Alert: {{ .CommonLabels.alertname }}
        text: >-
          {{ range .Alerts }}
          *Alert:* {{ .Annotations.summary }}
          *Beschreibung:* {{ .Annotations.description }}
          *Labels:* {{ .Labels }}
          {{ end }}
EOF

##########################################################
# 3. Create Alertmanager Systemd Service
##########################################################

echo "=== Creating Alertmanager systemd service ==="

sudo tee /etc/systemd/system/alertmanager.service >/dev/null <<EOF
[Unit]
Description=Prometheus Alertmanager
After=network.target

[Service]
ExecStart=/opt/alertmanager/alertmanager \
  --config.file=/opt/alertmanager/alertmanager.yml \
  --storage.path=/opt/alertmanager/data
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable alertmanager
sudo systemctl start alertmanager

##########################################################
# 4. Update Prometheus configuration
##########################################################

echo "=== Updating Prometheus configuration ==="

# Add alertmanager section if missing
if ! grep -q "alerting:" /opt/prometheus/prometheus.yml; then
sudo tee -a /opt/prometheus/prometheus.yml >/dev/null <<EOF

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["localhost:9093"]

rule_files:
  - /opt/prometheus/rules/*.yml
EOF
fi

sudo mkdir -p /opt/prometheus/rules

##########################################################
# 5. Create Alert Rule File
##########################################################

echo "=== Writing test alert rule ==="

sudo tee /opt/prometheus/rules/test-alert.yml >/dev/null <<EOF
groups:
  - name: test-alert
    rules:
      - alert: TestAlert
        expr: vector(1)
        for: 15s
        labels:
          severity: warning
        annotations:
          summary: "Testalarm"
          description: "Dieser Alert wird absichtlich immer ausgelöst."
EOF

##########################################################
# 6. Restart services
##########################################################

echo "=== Restarting services ==="

sudo systemctl restart alertmanager
sudo systemctl restart prometheus

echo "===================================================="
echo "Alertmanager:       http://<vm-ip>:9093"
echo "Prometheus Alerts:  http://<vm-ip>:9090/alerts"
echo "Slack:              Nachrichten werden in #test erscheinen"
echo "===================================================="
