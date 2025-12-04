# Anleitung: Metriken und Logs in einem umfassenden Grafana-Dashboard visualisieren

In dieser Anleitung baust du dir Schritt für Schritt ein Dashboard, das:

- Prometheus-Metriken nutzt:
  - `job="prometheus"` (Prometheus selbst)
  - `job="node"` (Node Exporter, Systemmetriken)
  - `job="backend"` (dein Node.js-Backend)
- Loki-Logs nutzt:
  - `job="system"` (`/var/log/*.log`)
  - `job="journald"` (Systemd-Journal)
  - `job="nginx"` (`/var/log/nginx/*.log`)
  - `app="demo-backend"` (Backend-Logs über winston-loki)

Voraussetzung: Dein Setup-Skript hat bereits Grafana, Prometheus, Loki, Promtail, Node Exporter und Backend installiert und gestartet.

## 1. Grafana-Weboberfläche erreichen

1. Ermittele die IP deiner VM (z. B. mit `ip a` oder im Cloud-Panel).
2. Öffne im Browser:

   http://<vm-ip>:3000

3. Standard-Login:
   - Benutzername: `admin`
   - Passwort: `admin`
4. Beim ersten Login wirst du aufgefordert, ein neues Passwort zu setzen.

## 2. Datenquellen in Grafana einrichten

### 2.1 Prometheus als Datenquelle hinzufügen

1. Links im Menü: Connections → Data sources
2. „Add data source“
3. „Prometheus“
4. URL: http://localhost:9090
5. Save & test

### 2.2 Loki als Datenquelle hinzufügen

1. Add data source
2. Loki
3. URL: http://localhost:3100
4. Save & test

## 3. Neues Dashboard anlegen

1. Dashboards → New → New dashboard
2. Add a new panel
3. Datenquelle wählen (Prometheus oder Loki)
4. Query schreiben (PromQL oder LogQL)

## 4. Metriken mit PromQL visualisieren

### 4.1 Status aller Targets

```
up
```

### 4.2 CPU-Auslastung

```
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

### 4.3 RAM-Auslastung

```
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) 
/ node_memory_MemTotal_bytes * 100
```

### 4.4 API-Requests pro Sekunde

```
rate(api_requests_total[5m])
```

### 4.5 Antwortzeit P90

```
histogram_quantile(
  0.9,
  sum(rate(api_response_time_seconds_bucket[5m])) by (le)
)
```

## 5. Logs mit Loki und LogQL analysieren

### 5.1 Grundform

```
{app="demo-backend"}
```

### 5.2 Filtern nach Fehlern

```
{app="demo-backend"} |= "error"
```

### 5.3 Nginx-Logs

```
{job="nginx"}
```

### 5.4 Log-Volumen

```
count_over_time({app="demo-backend"} |= "error" [5m])
```

## 6. Dashboard-Struktur

1. Reihe: Systemmetriken  
2. Reihe: Backend-Performance  
3. Reihe: Backend-Logs  
4. Reihe: Nginx-Logs  
5. Reihe: System-Logs  

## 7. Verbindung zwischen Metriken und Logs

1. Panel öffnen  
2. Auf Punkt in Graph klicken  
3. „View logs“ oder Data Link nutzen  
4. Explore-Ansicht öffnet die Logs im gleichen Zeitfenster  

## 8. Zusammenfassung

Dieses Dashboard kombiniert:

- Systemmetriken
- Backend-Metriken
- API-Antwortzeiten
- Nginx-Logs
- Backend-Logs
- System-Logs

Damit erhältst du ein vollständiges Observability-Dashboard.

