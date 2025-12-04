#!/usr/bin/env bash
set -e

echo "=== Installing Node.js (LTS) ==="
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs nginx

############################################################
# 1. BACKEND EINRICHTEN
############################################################
echo "=== Setting up Backend ==="

sudo mkdir -p /opt/backend
sudo tee /opt/backend/server.js >/dev/null <<'EOF'
const express = require("express");
const promClient = require("prom-client");
const winston = require("winston");
const LokiTransport = require("winston-loki");
const cors = require("cors");

const app = express();
app.use(cors());

const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

// Loki logger
const logger = winston.createLogger({
  transports: [
    new LokiTransport({
      host: "http://localhost:3100",
      labels: { app: "demo-backend" },
      json: true,
      level: "info",
    }),
    new winston.transports.Console()
  ]
});

// ROUTES
app.get("/", (req, res) => {
  logger.info("Root endpoint hit");
  res.json({ message: "Backend is running!" });
});

app.get("/error", (req, res) => {
  logger.error("Error endpoint triggered");
  res.status(500).json({ error: "Something broke!" });
});

// Prometheus metrics
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

// Counters + Histogram
const counter = new promClient.Counter({
  name: "api_requests_total",
  help: "Total number of API requests",
});
register.registerMetric(counter);

const histogram = new promClient.Histogram({
  name: "api_response_time_seconds",
  help: "Response times",
  buckets: [0.05, 0.1, 0.2, 0.5, 1, 2]
});
register.registerMetric(histogram);

app.use((req, res, next) => {
  counter.inc();
  const start = Date.now();
  res.on("finish", () => {
    histogram.observe((Date.now() - start) / 1000);
  });
  next();
});

app.get("/users", (req, res) => {
  logger.info("Requested user list");
  res.json([{ id: 1, name: "Alice" }, { id: 2, name: "Bob" }]);
});

app.get("/busy", (req, res) => {
  const start = Date.now();
  while (Date.now() - start < 15000) {}
  res.json({ status: "CPU load simulated for 15 seconds" });
});

app.get("/spam", (req, res) => {
  for (let i = 0; i < 100; i++) {
    logger.info("Spam log entry " + i);
  }
  res.json({ done: true });
});

app.listen(3001, () => console.log("Backend running on port 3001"));
EOF

echo "=== Installing backend dependencies ==="
cd /opt/backend
sudo npm init -y
sudo npm install express prom-client winston winston-loki cors

# Systemd service
sudo tee /etc/systemd/system/backend.service >/dev/null <<EOF
[Unit]
Description=Demo Backend Service
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/backend/server.js
Restart=always
User=root
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable backend
sudo systemctl start backend

############################################################
# 2. FRONTEND + NGINX SETUP
############################################################
echo "=== Creating frontend HTML ==="

sudo tee /var/www/frontend/index.html >/dev/null <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Monitoring Demo Frontend</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 30px auto;
            padding: 20px;
        }
        button {
            padding: 10px 20px;
            margin: 10px 0;
            font-size: 16px;
            cursor: pointer;
        }
        pre {
            background: #eee;
            padding: 15px;
            border-radius: 8px;
            white-space: pre-wrap;
        }
    </style>
</head>
<body>

<h1>Monitoring Demo Frontend</h1>

<p>Dieses Frontend testet die Endpunkte des Backends (Port 3001).</p>

<button onclick="callApi('/')">GET /</button>
<button onclick="callApi('/error')">GET /error</button>
<button onclick="callApi('/metrics')">GET /metrics</button>
<button onclick="callApi('/users')">GET /users</button>
<button onclick="callApi('/busy')">Lasttest - CPU brennt</button>
<button onclick="callApi('/spam')">Spamming Logs</button>
<button onclick="checkStatus('/')">Check Backend Status</button>

<h2>Response</h2>
<pre id="output">Bitte einen Button drücken…</pre>

<script src="script.js"></script>
</body>
</html>
EOF


echo "=== Creating frontend JavaScript ==="

sudo tee /var/www/frontend/script.js >/dev/null <<'EOF'
async function callApi(path) {
    const output = document.getElementById("output");
    output.textContent = "Loading...";

    try {
        const res = await fetch("/api" + path);
        const text = await res.text();

        output.textContent =
            "Status: " + res.status + " " + res.statusText + "\n\n" + text;
    } catch (err) {
        output.textContent = "Error: " + err.toString();
    }
}
EOF

sudo chown -R www-data:www-data /var/www/frontend

# Nginx config mit Reverse Proxy
sudo tee /etc/nginx/sites-available/frontend >/dev/null <<EOF
server {
    listen 80;
    server_name _;

    root /var/www/frontend;
    index index.html;

    location / {
        try_files \$uri /index.html;
    }

    location /api/ {
        proxy_pass http://localhost:3001/;
        proxy_set_header Host \$host;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/frontend /etc/nginx/sites-enabled/frontend
sudo rm -f /etc/nginx/sites-enabled/default

sudo systemctl restart nginx

############################################################
# 3. PROMETHEUS CONFIG UPDATE
############################################################
echo "=== Updating Prometheus configuration ==="

if ! grep -q "job_name: \"backend\"" /opt/prometheus/prometheus.yml; then
sudo tee -a /opt/prometheus/prometheus.yml >/dev/null <<'EOF'

  - job_name: "backend"
    static_configs:
      - targets: ["localhost:3001"]
EOF
fi

sudo systemctl restart prometheus

############################################################
# 4. PROMTAIL UPDATE (NGINX LOGS)
############################################################
echo "=== Updating Promtail configuration ==="

if ! grep -q "job_name: nginx" /etc/promtail.yaml; then
sudo tee -a /etc/promtail.yaml >/dev/null <<'EOF'

  - job_name: nginx
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          host: logvm
          __path__: /var/log/nginx/*.log
EOF
fi

sudo systemctl restart promtail


echo "============================================"
echo " Backend + Frontend + Nginx successfully set up!"
echo " Frontend:  http://<vm-ip>"
echo " API:       http://<vm-ip>/api"
echo "============================================"
