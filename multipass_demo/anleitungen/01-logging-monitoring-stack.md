# Vollständige Anleitung: Monitoring-Stack auf einer Multipass-VM manuell installieren und konfigurieren

Diese Anleitung beschreibt Schritt für Schritt, wie du:

1. Eine neue Multipass-VM startest  
2. Alle Programme (Grafana, Prometheus, Node Exporter, Loki, Promtail) manuell installierst  
3. Die passenden Config-Dateien anlegst  
4. Systemd-Services einrichtest  
5. Alles startest und überprüfst  

Alle Schritte orientieren sich exakt an deinem initialen Bash-Skript.

---

## 1. Multipass-VM erstellen

Zuerst eine neue Ubuntu-VM starten:

```bash
multipass launch --name monitor --mem 4G --disk 20G --cpus 2
```

In die VM einloggen:

```bash
multipass shell monitor
```

---

## 2. System aktualisieren und Grundpakete installieren

```bash
sudo apt update -y
sudo apt install -y curl wget unzip gnupg apt-transport-https software-properties-common
```

---

## 3. CPU-Architektur prüfen (wie im Skript)

Prüfen, ob du `amd64` oder `arm64` hast:

```bash
uname -m
```

Typisch:

- Apple M1/M2 = arm64
- Standard-PC = x86_64

---

## 4. Grafana installieren

### 4.1 GPG-Key und Repository hinzufügen

```bash
sudo mkdir -p /etc/apt/keyrings/
wget -q -O- https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
```

Repository anlegen:

```bash
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list >/dev/null
```

### 4.2 Grafana installieren

```bash
sudo apt update -y
sudo apt install -y grafana
```

### 4.3 Service registrieren und starten

```bash
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
```

Grafana läuft jetzt unter:

```
http://<vm-ip>:3000
```

---

## 5. Prometheus installieren

Version festlegen:

```bash
PROM_VERSION="2.48.0"
```

### 5.1 Tarball herunterladen

Für amd64:

```bash
wget https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
```

Für arm64:

```bash
wget https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-arm64.tar.gz
```

### 5.2 Entpacken und nach /opt verschieben:

```bash
tar -xzf prometheus-${PROM_VERSION}*.tar.gz
sudo mv prometheus-${PROM_VERSION}* /opt/prometheus
```

---

## 6. Prometheus-Konfiguration erstellen

```bash
sudo tee /opt/prometheus/prometheus.yml >/dev/null <<EOF
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
```

---

## 7. Systemd-Service für Prometheus schreiben

```bash
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
```

Service aktivieren:

```bash
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus
```

---

## 8. Node Exporter installieren

Version:

```bash
NODE_VERSION="1.8.1"
```

Herunterladen:

```bash
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_VERSION}/node_exporter-${NODE_VERSION}.linux-amd64.tar.gz
```

Entpacken und verschieben:

```bash
tar -xzf node_exporter-${NODE_VERSION}*.tar.gz
sudo mv node_exporter-${NODE_VERSION}* /opt/node_exporter
```

### Node Exporter Systemd-Service

```bash
sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<EOF
[Unit]
Description=Node Exporter

[Service]
ExecStart=/opt/node_exporter/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF
```

Starten:

```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

---

## 9. Loki installieren

Version:

```bash
LOKI_VERSION="2.9.0"
```

Herunterladen:

```bash
wget https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip
```

Entpacken:

```bash
unzip loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki
```

### Loki Datenverzeichnisse erstellen

```bash
sudo mkdir -p /tmp/loki/index /tmp/loki/cache /tmp/loki/chunks /tmp/loki/compactor
sudo chmod -R 777 /tmp/loki
```

### Loki Config erstellen

```bash
sudo tee /etc/loki.yaml >/dev/null <<EOF
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
```

### Loki als Service

```bash
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
```

Starten:

```bash
sudo systemctl daemon-reload
sudo systemctl enable loki
sudo systemctl start loki
```

---

## 10. Promtail installieren

Herunterladen:

```bash
wget https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail
```

### Promtail-Konfiguration erstellen

```bash
sudo tee /etc/promtail.yaml >/dev/null <<EOF
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
```

### Promtail Service

```bash
sudo tee /etc/systemd/system/promtail.service >/dev/null <<EOF
[Unit]
Description=Promtail Log Collector

[Service]
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
```

Starten:

```bash
sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail
```

---

## 11. Services prüfen

```bash
systemctl status grafana-server
systemctl status prometheus
systemctl status node_exporter
systemctl status loki
systemctl status promtail
```

---

## 12. Zugriff

Grafana:  
```
http://<vm-ip>:3000
```

Prometheus:  
```
http://<vm-ip>:9090
```

Loki Query API:  
```
http://<vm-ip>:3100/loki/api/v1/query
```

Node Exporter:  
```
http://<vm-ip>:9100/metrics
```

---

Damit ist der komplette Monitoring-Stack manuell installiert, vollständig konfiguriert und einsatzbereit.
