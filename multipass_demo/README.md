# Logging und Monitoring + Visualisierung
## Multipass Setup für VM 
Richte dir zunächst eine VM in multipass ein:
```bash
multipass launch --name monitor --mem 4G --disk 20G --cpus 2
```
Dann wähle dich drauf:
```bash
multipass shell monitor
```
Danach kannst du dich entscheiden, ob du den Stack per Hand hochziehst, oder per Bash-Script automatisierung.
- per Hand: von 01-03 die Anleitungen durchgehen
- automatisiert: von 01-03 die Bash-Scripts durchführen

### Bash Skript durchführen
- Klone dir per `git clone https://github.com/IT-Berufsspezialist-Mo-Mi/grafana-prometheus-loki-stack.git`
- Navigiere mit `cd grafana-prometheus-loki-stack/multipass_demo` rein und mache die Skripte ausführbar mit `chmod +x <script_name>`
- ausführen mit `.\<script_name>` 
