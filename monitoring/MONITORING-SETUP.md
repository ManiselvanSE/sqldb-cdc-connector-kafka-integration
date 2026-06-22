# Monitoring Setup Guide - Debezium CDC Pipeline

Complete monitoring stack with Prometheus and Grafana for your Azure SQL CDC connector.

---

## 📊 Monitoring Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  MONITORING STACK                            │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐         ┌──────────────┐                  │
│  │   Grafana    │────────▶│  Prometheus  │                  │
│  │  Dashboard   │  Query  │   Storage    │                  │
│  │ Port: 3000   │         │  Port: 9090  │                  │
│  └──────────────┘         └──────┬───────┘                  │
│                                   │                           │
│                                   │ Scrape Metrics           │
│                                   │                           │
│       ┌───────────────────────────┼──────────────┐           │
│       │                           │              │           │
│       ▼                           ▼              ▼           │
│  ┌─────────┐              ┌──────────┐    ┌─────────┐      │
│  │  Kafka  │              │  Connect │    │  JMX    │      │
│  │ Brokers │              │  Worker  │    │Exporter │      │
│  │ :7778   │              │  :7778   │    │         │      │
│  └─────────┘              └──────────┘    └─────────┘      │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Option 1: Automated Deployment (Recommended)

```bash
cd /Users/maniselvank/Mani/connector/sqldb/monitoring

# Deploy everything
./deploy-monitoring.sh

# Access Grafana
# URL: http://<EXTERNAL-IP>:3000
# User: admin
# Pass: admin
```

### Option 2: Manual Step-by-Step

See detailed steps below.

---

## 📋 Prerequisites

- [x] Kubernetes cluster running
- [x] Confluent Platform deployed
- [x] Debezium connector running
- [x] kubectl access

---

## Step 1: Enable Metrics on Confluent Components

### 1.1 Enable JMX Exporter on Kafka

Update Kafka CR to enable metrics:

```bash
kubectl edit kafka kafka -n confluent
```

Add to spec:

```yaml
spec:
  podTemplate:
    podSecurityContext:
      fsGroup: 1000
      runAsUser: 1000
      runAsNonRoot: true
    probe:
      liveness:
        periodSeconds: 10
        failureThreshold: 5
      readiness:
        periodSeconds: 10
        failureThreshold: 5
    resources:
      requests:
        memory: "4Gi"
        cpu: "1"
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "7778"
      prometheus.io/path: "/metrics"
  metricReporter:
    enabled: true
    bootstrapEndpoint: kafka:9071
    publishMs: 30000
  services:
    mds:
      externalAccess:
        type: loadBalancer
    prometheus:
      enabled: true
      port: 7778
```

### 1.2 Enable JMX Exporter on Connect

Update Connect CR:

```bash
kubectl edit connect connect -n confluent
```

Add to spec:

```yaml
spec:
  podTemplate:
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "7778"
      prometheus.io/path: "/metrics"
    probe:
      liveness:
        periodSeconds: 10
        failureThreshold: 5
      readiness:
        periodSeconds: 10
        failureThreshold: 5
  metrics:
    prometheus:
      enabled: true
      port: 7778
```

Apply changes:

```bash
# Wait for pods to restart
kubectl get pods -n confluent -w
```

---

## Step 2: Deploy Prometheus Operator

```bash
# Install CRDs
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

# Deploy Prometheus Operator
kubectl apply -f prometheus-operator.yaml

# Verify
kubectl get pods -n monitoring
```

---

## Step 3: Deploy Prometheus Instance

```bash
# Deploy Prometheus
kubectl apply -f prometheus-instance.yaml

# Wait for ready
kubectl get prometheus -n monitoring -w

# Get Prometheus URL
kubectl get svc prometheus -n monitoring
# Access: http://<EXTERNAL-IP>:9090
```

---

## Step 4: Configure ServiceMonitors

```bash
# Deploy ServiceMonitors
kubectl apply -f servicemonitors.yaml

# Verify targets in Prometheus
# Go to: http://<PROMETHEUS-IP>:9090/targets
# Should see: kafka-metrics, connect-metrics
```

---

## Step 5: Deploy Alert Rules

```bash
# Deploy PrometheusRules
kubectl apply -f prometheus-rules.yaml

# Verify alerts
# Go to: http://<PROMETHEUS-IP>:9090/alerts
```

---

## Step 6: Deploy Grafana

```bash
# Deploy Grafana
kubectl apply -f grafana.yaml

# Wait for ready
kubectl get pods -n monitoring | grep grafana

# Get Grafana URL
kubectl get svc grafana -n monitoring
# URL: http://<EXTERNAL-IP>:3000
# User: admin
# Pass: admin
```

---

## Step 7: Import Dashboards

### Via Grafana UI:

1. Login to Grafana (admin/admin)
2. Go to **Dashboards** → **Import**
3. Upload `dashboard-debezium-overview.json`
4. Select Prometheus datasource
5. Click **Import**

### Via kubectl:

```bash
# Create ConfigMap with dashboard
kubectl create configmap grafana-dashboard-debezium \
  --from-file=dashboard-debezium-overview.json \
  -n monitoring

# Label for auto-discovery
kubectl label configmap grafana-dashboard-debezium \
  grafana_dashboard=1 \
  -n monitoring
```

---

## 📈 Key Metrics to Monitor

### Debezium Connector Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `kafka_connect_connector_status` | Connector running status | != running |
| `kafka_connect_connector_task_status` | Task status | failed |
| `kafka_connect_source_connector_source_record_poll_total` | Total records polled | - |
| `kafka_connect_source_connector_source_record_write_total` | Total records written | - |
| `debezium_snapshot_completed_tables` | Snapshot progress | - |
| `debezium_metrics_Connected` | DB connection status | false |

### Kafka Broker Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `kafka_server_replicamanager_underreplicatedpartitions` | Under-replicated partitions | > 0 |
| `kafka_server_replicamanager_isrshrinks_total` | ISR shrinks | rate > 0 |
| `kafka_network_requestmetrics_totaltimems` | Request latency | > 1000ms |

### Connect Worker Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `kafka_connect_connector_failed_task_restarts_total` | Failed task restarts | rate > 0.1 |
| `kafka_connect_worker_connector_count` | Active connectors | < 1 |
| `kafka_connect_worker_task_count` | Active tasks | < 1 |

---

## 🔍 Useful Prometheus Queries

### Connector Health

```promql
# Connector status
kafka_connect_connector_status{connector="sqlserver-debezium-connector"}

# Task status
kafka_connect_connector_task_status{connector="sqlserver-debezium-connector"}

# CDC throughput (records/sec)
rate(kafka_connect_source_connector_source_record_poll_total{connector="sqlserver-debezium-connector"}[1m])

# Connector lag
kafka_connect_source_connector_source_record_poll_total - kafka_connect_source_connector_source_record_write_total

# Error rate
rate(kafka_connect_connector_failed_task_restarts_total{connector="sqlserver-debezium-connector"}[5m])
```

### Snapshot Progress

```promql
# Snapshot completion percentage
(debezium_snapshot_completed_tables / debezium_snapshot_total_tables_count) * 100

# Time remaining estimate
(debezium_snapshot_total_tables_count - debezium_snapshot_completed_tables) / rate(debezium_snapshot_completed_tables[5m])
```

### Database Connection

```promql
# DB connection status
debezium_metrics_Connected

# Connection uptime
time() - debezium_metrics_LastEvent
```

---

## 🚨 Alert Rules Configured

### Critical Alerts

1. **DebeziumConnectorDown** - Connector not running
2. **DebeziumTaskFailed** - Connector task failed
3. **KafkaConnectWorkerDown** - Connect worker unavailable
4. **KafkaBrokerDown** - Kafka broker offline

### Warning Alerts

1. **DebeziumHighLag** - >10K pending records
2. **DebeziumNoRecordsProcessed** - No activity for 10min
3. **DebeziumHighErrorRate** - Frequent task restarts
4. **KafkaUnderReplicatedPartitions** - Replication issues

---

## 📊 Grafana Dashboards

### Dashboard 1: Debezium CDC Overview

**Panels:**
- Connector Status (stat)
- Task Status (stat)
- CDC Records Per Second (graph)
- Snapshot Progress (gauge)
- Total Events Captured (stat)
- Connector Lag (graph)
- Error Rate (graph)
- Connection Status (table)

**Refresh:** 10 seconds  
**Time Range:** Last 1 hour

### Dashboard 2: Kafka Cluster (Community Dashboard)

Import from Grafana.com:
```
ID: 7589 (Kafka Overview)
```

### Dashboard 3: Kafka Connect (Community Dashboard)

Import from Grafana.com:
```
ID: 12239 (Kafka Connect Dashboard)
```

---

## 🔧 Troubleshooting

### Issue: No Metrics Showing

**Check:**
```bash
# Verify JMX exporter is enabled
kubectl exec kafka-0 -n confluent -- curl -s localhost:7778/metrics | head

kubectl exec connect-0 -n confluent -- curl -s localhost:7778/metrics | head
```

**Fix:**
- Ensure metrics are enabled in Kafka/Connect CRs
- Wait for pods to restart after CR update

### Issue: Targets Down in Prometheus

**Check:**
```bash
# Verify ServiceMonitors
kubectl get servicemonitor -n confluent

# Check services
kubectl get svc -n confluent | grep metrics
```

**Fix:**
```bash
# Recreate ServiceMonitors
kubectl delete -f servicemonitors.yaml
kubectl apply -f servicemonitors.yaml
```

### Issue: Grafana Can't Connect to Prometheus

**Check:**
```bash
# Test from Grafana pod
kubectl exec -it <grafana-pod> -n monitoring -- \
  wget -O- http://prometheus:9090/api/v1/query?query=up
```

**Fix:**
- Verify Prometheus service exists
- Check datasource configuration in Grafana

### Issue: Dashboards Not Loading

**Check:**
```bash
# Verify dashboard ConfigMap
kubectl get cm -n monitoring | grep dashboard

# Check Grafana logs
kubectl logs -n monitoring <grafana-pod>
```

**Fix:**
- Re-import dashboards manually via UI
- Check dashboard JSON format

---

## 🎯 Monitoring Best Practices

### 1. Set Up Alerting

Configure AlertManager for notifications:

```yaml
# alertmanager-config.yaml
global:
  slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'

route:
  receiver: 'slack'
  group_by: ['alertname', 'cluster', 'service']
  
receivers:
- name: 'slack'
  slack_configs:
  - channel: '#cdc-alerts'
    title: 'CDC Alert: {{ .GroupLabels.alertname }}'
    text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

### 2. Retention Policy

- **Prometheus:** 7 days (default in config)
- **Grafana:** Unlimited (dashboards)
- **Adjust based on storage:**

```yaml
# In prometheus-instance.yaml
spec:
  retention: 15d  # Increase to 15 days
  storage:
    volumeClaimTemplate:
      spec:
        resources:
          requests:
            storage: 50Gi  # Increase storage
```

### 3. Resource Allocation

**Recommended for Production:**

```yaml
# Prometheus
resources:
  requests:
    memory: 4Gi
    cpu: 1000m
  limits:
    memory: 8Gi
    cpu: 2000m

# Grafana
resources:
  requests:
    memory: 1Gi
    cpu: 500m
  limits:
    memory: 2Gi
    cpu: 1000m
```

### 4. Regular Health Checks

```bash
# Daily health check script
#!/bin/bash
echo "=== CDC Monitoring Health Check ==="
kubectl get prometheus,grafana -n monitoring
kubectl get servicemonitor -n confluent
curl -s http://prometheus:9090/-/healthy
curl -s http://grafana:3000/api/health
```

---

## 📱 Access URLs

After deployment:

```bash
# Get URLs
kubectl get svc -n monitoring

# Prometheus
PROM_IP=$(kubectl get svc prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Prometheus: http://$PROM_IP:9090"

# Grafana
GRAFANA_IP=$(kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Grafana: http://$GRAFANA_IP:3000"
echo "Login: admin/admin"
```

---

## 🔐 Security Recommendations

### 1. Change Default Passwords

```bash
# Update Grafana admin password
kubectl exec -it <grafana-pod> -n monitoring -- \
  grafana-cli admin reset-admin-password <NEW_PASSWORD>
```

### 2. Enable HTTPS

```yaml
# grafana.yaml - add TLS
spec:
  ingress:
    enabled: true
    tls:
    - hosts:
      - grafana.yourdomain.com
      secretName: grafana-tls
```

### 3. RBAC for Prometheus

Already configured in `prometheus-instance.yaml` with minimal permissions.

---

## 📚 Additional Resources

- **Prometheus Docs:** https://prometheus.io/docs/
- **Grafana Docs:** https://grafana.com/docs/
- **Debezium Metrics:** https://debezium.io/documentation/reference/stable/operations/monitoring.html
- **Kafka JMX Metrics:** https://kafka.apache.org/documentation/#monitoring

---

## ✅ Verification Checklist

After setup, verify:

- [ ] Prometheus accessible at http://<IP>:9090
- [ ] Prometheus targets showing as UP
- [ ] Grafana accessible at http://<IP>:3000
- [ ] Prometheus datasource connected in Grafana
- [ ] Dashboards imported and showing data
- [ ] Alerts configured and visible
- [ ] Metrics flowing for Kafka, Connect, Connector
- [ ] Test alerts firing (simulate failure)

---

**Monitoring stack deployed successfully!** 📊✅
