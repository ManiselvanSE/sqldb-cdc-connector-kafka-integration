# Monitoring Stack - Quick Start Guide

## ✅ What's Deployed

Your Debezium CDC monitoring stack is now set up with:

- ✅ **Grafana** - Visualization & Dashboards
- ✅ **Prometheus** - Metrics collection & storage
- ✅ **ServiceMonitors** - Scrape configs for Kafka & Connect
- ✅ **Alert Rules** - 9 pre-configured CDC alerts

---

## 🌐 Access URLs

### Grafana (Primary Dashboard)

```
URL: http://<GRAFANA_IP>:3000
Username: admin
Password: admin
```

**⚠️ IMPORTANT:** Change the default password on first login!

### Prometheus (Metrics & Alerts)

```
URL: http://<PROMETHEUS_IP>:9090
```

No authentication required (configure in production!)

---

## 📊 Quick Access Paths

### Grafana

1. **Login:** http://<GRAFANA_IP>:3000
2. **Change Password:** Click profile → Change Password
3. **Import Dashboard:**
   - Go to: Dashboards → Import
   - Upload: `dashboard-debezium-overview.json`
   - Select: Prometheus datasource
   - Click: Import

### Prometheus

1. **Targets:** http://<PROMETHEUS_IP>:9090/targets
   - Should see: kafka-metrics, connect-metrics (when metrics enabled)
   
2. **Alerts:** http://<PROMETHEUS_IP>:9090/alerts
   - View: All configured CDC alert rules

3. **Query:** http://<PROMETHEUS_IP>:9090/graph
   - Test query: `up`
   - Should show all monitoring targets

---

## 🔧 Next Steps

### Step 1: Enable Metrics on Confluent Components

**Kafka Connect already has JMX metrics exposed!**

Test it:
```bash
kubectl exec connect-0 -n confluent -- curl -s localhost:7778/metrics | head -20
```

If no metrics, enable JMX exporter in Connect CR:

```bash
kubectl patch connect connect -n confluent --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/metrics",
    "value": {
      "prometheus": {
        "enabled": true,
        "port": 7778
      }
    }
  }
]'
```

### Step 2: Import Grafana Dashboard

```bash
# From monitoring directory
cd /Users/maniselvank/Mani/connector/sqldb/monitoring

# Option A: Via UI (Recommended)
# 1. Go to http://<GRAFANA_IP>:3000
# 2. Dashboards → Import
# 3. Upload dashboard-debezium-overview.json

# Option B: Via kubectl
kubectl create configmap grafana-dashboard-debezium \
  --from-file=dashboard-debezium-overview.json \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart Grafana to load dashboards
kubectl rollout restart deployment/grafana -n monitoring
```

### Step 3: Verify Metrics Collection

```bash
# Check Prometheus targets
curl -s http://<PROMETHEUS_IP>:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Query connector status
curl -s 'http://<PROMETHEUS_IP>:9090/api/v1/query?query=kafka_connect_connector_status' | jq
```

### Step 4: Test Alerts

Alerts are configured for:

1. **DebeziumConnectorDown** - Connector stops running
2. **DebeziumTaskFailed** - Connector task fails
3. **DebeziumHighLag** - >10K pending records
4. **DebeziumNoRecordsProcessed** - No activity for 10min
5. **KafkaConnectWorkerDown** - Connect worker unavailable
6. **KafkaBrokerDown** - Kafka broker offline
7. **High Error Rate** - Frequent task restarts
8. **Under-replicated Partitions** - Replication issues
9. **ISR Shrinks** - In-Sync Replica issues

View at: http://<PROMETHEUS_IP>:9090/alerts

---

## 📈 Key Metrics to Watch

### In Prometheus

Query these in Prometheus UI (http://<PROMETHEUS_IP>:9090/graph):

```promql
# Connector Status
kafka_connect_connector_status{connector="sqlserver-debezium-connector"}

# CDC Records/Second
rate(kafka_connect_source_connector_source_record_poll_total{connector="sqlserver-debezium-connector"}[1m])

# Connector Lag
kafka_connect_source_connector_source_record_poll_total - kafka_connect_source_connector_source_record_write_total

# Error Rate
rate(kafka_connect_connector_failed_task_restarts_total{connector="sqlserver-debezium-connector"}[5m])
```

### In Grafana

Once dashboard is imported, you'll see:
- Connector Status (real-time)
- Task Status
- CDC Throughput graphs
- Snapshot Progress
- Error Rate trends
- Connection Status table

---

## 🔍 Troubleshooting

### Grafana Can't Connect to Prometheus

**Check:**
```bash
kubectl get svc prometheus -n monitoring
kubectl exec -it <grafana-pod> -n monitoring -- \
  wget -O- http://prometheus:9090/api/v1/query?query=up
```

**Fix:**
- Datasource should use URL: `http://prometheus:9090`
- Not the external IP

### No Metrics Showing

**Check if JMX exporter is running:**
```bash
# Check Connect metrics endpoint
kubectl exec connect-0 -n confluent -- curl -s localhost:7778/metrics | grep -i kafka_connect

# Check Kafka metrics endpoint (if enabled)
kubectl exec kafka-0 -n confluent -- curl -s localhost:7778/metrics | grep -i kafka_server
```

**If no output, enable metrics in CR:**

See `MONITORING-SETUP.md` Step 1 for detailed instructions.

### Prometheus Targets Down

**Check ServiceMonitors:**
```bash
kubectl get servicemonitor -n confluent
kubectl describe servicemonitor kafka-metrics -n confluent
```

**Verify services exist:**
```bash
kubectl get svc -n confluent | grep metrics
```

**Expected:**
- kafka-metrics (port 7778)
- connect-metrics (port 7778)

### Dashboard Not Loading

**Reimport manually:**
1. Go to Grafana UI
2. Dashboards → Import
3. Upload JSON file
4. Select Prometheus datasource

---

## 🎯 Quick Commands

```bash
# Check all monitoring components
kubectl get pods,svc -n monitoring

# View Grafana logs
kubectl logs -n monitoring deployment/grafana -f

# View Prometheus logs  
kubectl logs -n monitoring prometheus-confluent-monitoring-0 -f 2>/dev/null || echo "Prometheus pod not ready yet"

# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring

# Delete and redeploy monitoring (if needed)
cd /Users/maniselvank/Mani/connector/sqldb/monitoring
kubectl delete -f grafana.yaml
kubectl delete -f prometheus-instance.yaml
kubectl apply -f prometheus-instance.yaml
kubectl apply -f grafana.yaml
```

---

## 📝 What's Next

1. ✅ Access Grafana and change password
2. ✅ Import Debezium CDC dashboard
3. ✅ Enable JMX metrics on Kafka/Connect (if not already)
4. ✅ Verify metrics are being collected
5. ✅ Set up alert notifications (Slack/Email)
6. ✅ Create custom dashboards for your use case

---

## 📚 Documentation

- **Full Setup:** `MONITORING-SETUP.md`
- **CLI Alternative:** `/Users/maniselvank/Mani/connector/sqldb/CLI-COMMANDS.md`
- **Prometheus Queries:** `MONITORING-SETUP.md` (Key Metrics section)

---

## ✅ Verification Checklist

- [ ] Can access Grafana at http://<GRAFANA_IP>:3000
- [ ] Changed default Grafana password
- [ ] Can access Prometheus at http://<PROMETHEUS_IP>:9090
- [ ] Prometheus targets showing (when metrics enabled)
- [ ] Imported Debezium dashboard to Grafana
- [ ] Dashboard showing live data
- [ ] Alerts configured and visible in Prometheus
- [ ] Tested one alert by simulating failure

---

**Monitoring stack is ready! 📊**

Access Grafana now: http://<GRAFANA_IP>:3000 (admin/admin)
