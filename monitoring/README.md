# Debezium CDC Monitoring Stack

Complete Prometheus + Grafana monitoring setup for your Azure SQL Server CDC pipeline.

---

## 🎉 Deployment Complete!

Your monitoring stack is deployed and ready to use.

### Access URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** | http://<GRAFANA_IP>:3000 | admin / admin |
| **Prometheus** | http://<PROMETHEUS_IP>:9090 | No auth |

⚠️ **IMPORTANT:** Change the Grafana admin password on first login!

---

## 📁 Files in This Directory

| File | Purpose |
|------|---------|
| `QUICK-START.md` | ⭐ **Start here** - Quick setup guide |
| `MONITORING-SETUP.md` | Detailed setup & configuration guide |
| `prometheus-operator.yaml` | Prometheus Operator deployment |
| `prometheus-instance.yaml` | Prometheus instance configuration |
| `grafana.yaml` | Grafana deployment |
| `servicemonitors.yaml` | Metrics collection configs |
| `prometheus-rules.yaml` | Alert rules (9 CDC alerts) |
| `dashboard-debezium-overview.json` | Grafana dashboard for CDC |
| `deploy-monitoring.sh` | Automated deployment script |

---

## 🚀 Quick Start (3 Steps)

### 1. Access Grafana

```
Open: http://<GRAFANA_IP>:3000
Login: admin / admin
Change Password: Click profile → Change Password
```

### 2. Import Dashboard

```
1. Go to: Dashboards → Import
2. Upload: dashboard-debezium-overview.json
3. Select Datasource: Prometheus
4. Click: Import
```

### 3. Enable JMX Metrics (if needed)

```bash
# Test if metrics are already available
kubectl exec connect-0 -n confluent -- curl -s localhost:7778/metrics | head

# If no output, enable metrics in Connect CR:
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

---

## 📊 What's Monitored

### Debezium Connector

- ✅ Connector status (running/failed)
- ✅ Task status
- ✅ CDC records per second
- ✅ Snapshot progress
- ✅ Connector lag
- ✅ Error rate
- ✅ Database connection status

### Kafka Cluster

- ✅ Broker health
- ✅ Under-replicated partitions
- ✅ ISR shrinks
- ✅ Network throughput
- ✅ Request latency

### Connect Worker

- ✅ Worker health
- ✅ Active connectors/tasks
- ✅ Failed task restarts
- ✅ Resource usage

---

## 🚨 Alerts Configured

9 pre-configured alerts:

| Alert | Severity | Threshold |
|-------|----------|-----------|
| DebeziumConnectorDown | Critical | Connector not running |
| DebeziumTaskFailed | Critical | Task failed |
| KafkaConnectWorkerDown | Critical | Worker unavailable |
| KafkaBrokerDown | Critical | Broker offline |
| DebeziumHighLag | Warning | >10K pending records |
| DebeziumNoRecordsProcessed | Warning | No activity 10min |
| DebeziumHighErrorRate | Warning | Frequent restarts |
| KafkaUnderReplicatedPartitions | Warning | Replication issues |
| KafkaISRShrink | Warning | ISR shrinking |

View alerts: http://<PROMETHEUS_IP>:9090/alerts

---

## 🔧 Common Tasks

### View Prometheus Targets

```bash
# Via browser
http://<PROMETHEUS_IP>:9090/targets

# Via CLI
curl -s http://<PROMETHEUS_IP>:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

### Query Metrics

```bash
# Connector status
curl -s 'http://<PROMETHEUS_IP>:9090/api/v1/query?query=kafka_connect_connector_status{connector="sqlserver-debezium-connector"}' | jq

# CDC throughput
curl -s 'http://<PROMETHEUS_IP>:9090/api/v1/query?query=rate(kafka_connect_source_connector_source_record_poll_total[1m])' | jq
```

### Restart Components

```bash
# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring

# Restart Prometheus (delete pod, StatefulSet recreates it)
kubectl delete pod prometheus-confluent-monitoring-0 -n monitoring

# Restart Prometheus Operator
kubectl rollout restart deployment/prometheus-operator -n monitoring
```

---

## 📈 Key Prometheus Queries

Copy these into Prometheus UI (http://<PROMETHEUS_IP>:9090/graph):

```promql
# Connector Status
kafka_connect_connector_status{connector="sqlserver-debezium-connector"}

# CDC Records/Second
rate(kafka_connect_source_connector_source_record_poll_total{connector="sqlserver-debezium-connector"}[1m])

# Connector Lag
kafka_connect_source_connector_source_record_poll_total - kafka_connect_source_connector_source_record_write_total

# Error Rate
rate(kafka_connect_connector_failed_task_restarts_total{connector="sqlserver-debezium-connector"}[5m])

# Database Connection
debezium_metrics_Connected

# Snapshot Progress
(debezium_snapshot_completed_tables / debezium_snapshot_total_tables_count) * 100
```

---

## 🔍 Troubleshooting

### No Metrics in Grafana

1. **Check Prometheus datasource:**
   - Grafana → Configuration → Data Sources
   - URL should be: `http://prometheus:9090`
   - Click "Save & Test"

2. **Check if metrics are being collected:**
   ```bash
   # Test Connect metrics endpoint
   kubectl exec connect-0 -n confluent -- curl -s localhost:7778/metrics | grep kafka_connect
   ```

3. **Enable JMX exporter if needed:**
   See Step 3 in Quick Start above

### Prometheus Targets Down

1. **Check services exist:**
   ```bash
   kubectl get svc -n confluent | grep metrics
   ```

2. **Verify ServiceMonitors:**
   ```bash
   kubectl get servicemonitor -n confluent
   ```

3. **Check Prometheus logs:**
   ```bash
   kubectl logs -n monitoring prometheus-confluent-monitoring-0 2>/dev/null || echo "Pod not ready"
   ```

### Dashboard Not Loading

1. **Reimport dashboard:**
   - Grafana → Dashboards → Import
   - Upload `dashboard-debezium-overview.json`
   - Select Prometheus datasource

2. **Check dashboard JSON is valid:**
   ```bash
   cat dashboard-debezium-overview.json | jq . > /dev/null && echo "Valid JSON" || echo "Invalid JSON"
   ```

---

## 🔐 Security (Production)

### Change Grafana Password

```bash
kubectl exec -it <grafana-pod> -n monitoring -- \
  grafana-cli admin reset-admin-password <NEW_PASSWORD>
```

### Enable Grafana HTTPS

Edit `grafana.yaml` and add ingress with TLS.

### Add Prometheus Authentication

Deploy with authentication proxy or use Grafana as the only access point.

### Restrict Access

Update services to `ClusterIP` instead of `LoadBalancer` and use ingress controller.

---

## 📚 Documentation Links

- **Prometheus:** https://prometheus.io/docs/
- **Grafana:** https://grafana.com/docs/
- **Debezium Monitoring:** https://debezium.io/documentation/reference/stable/operations/monitoring.html
- **Kafka JMX Metrics:** https://kafka.apache.org/documentation/#monitoring

---

## 🎯 Next Steps

1. ✅ Access Grafana (http://<GRAFANA_IP>:3000)
2. ✅ Change admin password
3. ✅ Import Debezium dashboard
4. ✅ Enable JMX metrics if needed
5. ✅ Verify data flowing in dashboards
6. ✅ Set up alert notifications (Slack/Email)
7. ✅ Create custom dashboards for your use case

---

## 📞 Support

For issues or questions:
1. Check `MONITORING-SETUP.md` for detailed troubleshooting
2. Review Prometheus targets: http://<PROMETHEUS_IP>:9090/targets
3. Check component logs:
   ```bash
   kubectl logs -n monitoring deployment/grafana
   kubectl logs -n monitoring prometheus-confluent-monitoring-0
   ```

---

**Monitoring stack deployed successfully! 📊✅**

**Start here:** `QUICK-START.md`
