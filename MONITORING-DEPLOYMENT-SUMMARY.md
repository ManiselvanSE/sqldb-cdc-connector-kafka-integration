# Monitoring Deployment Summary

**Deployment Date:** 2026-06-22  
**Status:** ✅ COMPLETE

---

## 🎉 What's Deployed

Complete monitoring stack for Debezium CDC pipeline with:

✅ **Prometheus** - Metrics collection & storage  
✅ **Grafana** - Visualization & dashboards  
✅ **Alert Rules** - 9 pre-configured CDC alerts  
✅ **ServiceMonitors** - Kafka & Connect scrape configs  
✅ **Dashboard** - Pre-built Debezium CDC overview  

---

## 🌐 Access Information

### Grafana (Primary Interface)

```
URL:      http://20.235.34.175:3000
Username: admin
Password: admin (⚠️ CHANGE THIS!)
```

**What you can do:**
- View real-time CDC metrics dashboards
- Monitor connector health
- Track throughput and lag
- Analyze error trends
- Create custom dashboards

### Prometheus (Metrics & Alerts)

```
URL: http://20.235.28.252:9090
```

**What you can do:**
- Query raw metrics
- View configured alerts
- Check scrape targets
- Test PromQL queries
- Debug metric collection

---

## 📊 Monitoring Capabilities

### Real-Time Dashboards

1. **Connector Status**
   - Running/Failed state
   - Task health
   - Uptime tracking

2. **CDC Throughput**
   - Records per second
   - Total events captured
   - Write vs Poll rates

3. **Performance Metrics**
   - Connector lag
   - Snapshot progress
   - Processing latency

4. **Error Tracking**
   - Task failures
   - Restart count
   - Error rate trends

5. **Database Connection**
   - Connection status
   - Uptime
   - Last event timestamp

### Pre-Configured Alerts

| Alert | Triggers When | Action Required |
|-------|---------------|-----------------|
| **DebeziumConnectorDown** | Connector stops | Investigate logs immediately |
| **DebeziumTaskFailed** | Task fails | Check connector config/DB access |
| **DebeziumHighLag** | >10K pending records | Check DB performance/network |
| **DebeziumNoRecordsProcessed** | No activity 10min | Verify CDC is enabled on DB |
| **KafkaConnectWorkerDown** | Worker offline | Check Connect pod status |
| **KafkaBrokerDown** | Kafka broker offline | Check Kafka cluster health |
| **High Error Rate** | Frequent restarts | Investigate error logs |
| **Under-replicated Partitions** | Replication issues | Check broker health |
| **ISR Shrinks** | In-Sync Replica issues | Check network/broker health |

View all alerts: http://20.235.28.252:9090/alerts

---

## 📁 Files Created (10 total)

```
monitoring/
├── README.md                            # Main documentation (start here)
├── QUICK-START.md                       # 3-step quick setup guide
├── MONITORING-SETUP.md                  # Detailed setup & config (20KB)
├── deploy-monitoring.sh                 # Automated deployment script
├── prometheus-operator.yaml             # Operator deployment
├── prometheus-instance.yaml             # Prometheus configuration
├── grafana.yaml                         # Grafana deployment
├── servicemonitors.yaml                 # Metrics scrape configs
├── prometheus-rules.yaml                # Alert rules (9 alerts)
└── dashboard-debezium-overview.json     # Grafana dashboard JSON
```

**Total Size:** ~47KB of configuration

---

## 🚀 Quick Start (5 Minutes)

### Step 1: Access Grafana (1 min)

```
1. Open: http://20.235.34.175:3000
2. Login: admin / admin
3. Change password when prompted
```

### Step 2: Import Dashboard (2 min)

```
1. Click: Dashboards → Import
2. Upload: monitoring/dashboard-debezium-overview.json
3. Select: Prometheus (datasource)
4. Click: Import
```

### Step 3: Enable Metrics (2 min)

```bash
# Check if metrics are already available
kubectl exec connect-0 -n confluent -- curl -s localhost:7778/metrics | head

# If no output, enable JMX exporter:
kubectl patch connect connect -n confluent --type='json' -p='[
  {"op": "add", "path": "/spec/metrics", "value": {"prometheus": {"enabled": true, "port": 7778}}}
]'

# Wait for Connect pod to restart
kubectl get pods -n confluent -w
```

### Step 4: Verify (30 sec)

```
1. Go to Grafana dashboard
2. Should see live metrics
3. Check Prometheus targets: http://20.235.28.252:9090/targets
```

---

## 📈 Monitoring Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    USER ACCESS                          │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Grafana UI                    Prometheus UI            │
│  http://20.235.34.175:3000     http://20.235.28.252:9090│
│       │                               │                  │
│       │                               │                  │
│       └───────────────┬───────────────┘                  │
│                       │                                  │
│                       ▼                                  │
│              ┌────────────────┐                          │
│              │   Prometheus   │                          │
│              │    Storage     │                          │
│              │  (7 days ret)  │                          │
│              └────────┬───────┘                          │
│                       │                                  │
│                       │ Scrapes every 30s                │
│                       │                                  │
│       ┌───────────────┼───────────────┐                 │
│       │               │               │                 │
│       ▼               ▼               ▼                 │
│  ┌────────┐     ┌─────────┐     ┌────────┐            │
│  │ Kafka  │     │ Connect │     │  JMX   │            │
│  │Brokers │     │ Worker  │     │Exporter│            │
│  │ :7778  │     │  :7778  │     │        │            │
│  └────────┘     └─────────┘     └────────┘            │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## 🎯 Key Metrics URLs

### Prometheus Queries

```
# Connector Status
http://20.235.28.252:9090/graph?g0.expr=kafka_connect_connector_status

# CDC Throughput
http://20.235.28.252:9090/graph?g0.expr=rate(kafka_connect_source_connector_source_record_poll_total[1m])

# Connector Lag
http://20.235.28.252:9090/graph?g0.expr=kafka_connect_source_connector_source_record_poll_total-kafka_connect_source_connector_source_record_write_total
```

### Grafana Dashboards

```
# After importing, access at:
http://20.235.34.175:3000/d/debezium-overview/debezium-sql-server-cdc-overview
```

---

## 🔧 Management Commands

### Check Status

```bash
# All monitoring components
kubectl get pods,svc -n monitoring

# Prometheus instance
kubectl get prometheus -n monitoring

# Alert rules
kubectl get prometheusrule -n monitoring | grep confluent
```

### View Logs

```bash
# Grafana logs
kubectl logs -n monitoring deployment/grafana -f

# Prometheus logs
kubectl logs -n monitoring prometheus-confluent-monitoring-0 -f

# Prometheus Operator logs
kubectl logs -n monitoring deployment/prometheus-operator -f
```

### Restart Components

```bash
# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring

# Restart Prometheus Operator
kubectl rollout restart deployment/prometheus-operator -n monitoring

# Delete Prometheus pod (auto-recreated)
kubectl delete pod prometheus-confluent-monitoring-0 -n monitoring
```

---

## 📊 Metrics Available

### Debezium Connector Metrics

- `kafka_connect_connector_status` - Connector running state
- `kafka_connect_connector_task_status` - Task health
- `kafka_connect_source_connector_source_record_poll_total` - Records polled
- `kafka_connect_source_connector_source_record_write_total` - Records written
- `kafka_connect_connector_failed_task_restarts_total` - Task failures
- `debezium_snapshot_completed_tables` - Snapshot progress
- `debezium_snapshot_total_tables_count` - Total tables
- `debezium_metrics_Connected` - DB connection status

### Kafka Broker Metrics

- `kafka_server_replicamanager_underreplicatedpartitions` - Replication issues
- `kafka_server_replicamanager_isrshrinks_total` - ISR problems
- `kafka_network_requestmetrics_totaltimems` - Request latency

### Connect Worker Metrics

- `kafka_connect_worker_connector_count` - Active connectors
- `kafka_connect_worker_task_count` - Active tasks
- `kafka_connect_connector_count` - Total connectors

---

## 🔍 Troubleshooting Guide

### Problem: No Metrics in Grafana

**Solution:**
1. Check Prometheus datasource connection
2. Verify JMX exporter is enabled on Connect
3. Check Prometheus targets: http://20.235.28.252:9090/targets

### Problem: Dashboard Shows "No Data"

**Solution:**
1. Wait 1-2 minutes for first scrape
2. Verify metrics endpoint: `kubectl exec connect-0 -n confluent -- curl localhost:7778/metrics`
3. Check time range in Grafana (try "Last 5 minutes")

### Problem: Alerts Not Firing

**Solution:**
1. Check alert rules exist: http://20.235.28.252:9090/rules
2. Verify metrics are being collected
3. Check alert evaluation interval (30s default)

### Problem: Cannot Access Grafana

**Solution:**
```bash
# Check service
kubectl get svc grafana -n monitoring

# Check pod
kubectl get pods -n monitoring | grep grafana

# Port forward if LoadBalancer pending
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Then access: http://localhost:3000
```

---

## 🎓 Learning Resources

- **Monitoring Setup:** `monitoring/MONITORING-SETUP.md`
- **Quick Start:** `monitoring/QUICK-START.md`
- **Prometheus Docs:** https://prometheus.io/docs/
- **Grafana Docs:** https://grafana.com/docs/
- **Debezium Monitoring:** https://debezium.io/documentation/reference/stable/operations/monitoring.html

---

## ✅ Deployment Checklist

- [x] Prometheus Operator deployed
- [x] Prometheus instance created
- [x] Grafana deployed
- [x] ServiceMonitors configured
- [x] Alert rules deployed
- [x] Dashboard JSON created
- [x] External IPs assigned
- [x] Documentation created
- [ ] Grafana password changed (do this now!)
- [ ] Dashboard imported to Grafana
- [ ] JMX metrics enabled on Connect
- [ ] Metrics verified in dashboards
- [ ] Alert notifications configured

---

## 🚨 Important Notes

### Security

⚠️ **Change Grafana password immediately!**
- Default: admin/admin
- Change via: Grafana UI → Profile → Change Password

⚠️ **Prometheus has no authentication**
- For production, add auth proxy or use Grafana only

### Resource Usage

Current allocation:
- Prometheus: 500m CPU, 2Gi RAM (limits: 1 CPU, 4Gi RAM)
- Grafana: 250m CPU, 512Mi RAM (limits: 500m CPU, 1Gi RAM)
- Storage: 20Gi PV for Prometheus (7 days retention)

### Costs

LoadBalancer IPs may incur cloud provider costs:
- Grafana: 20.235.34.175
- Prometheus: 20.235.28.252

For cost savings, use ClusterIP + Ingress instead.

---

## 📞 Next Steps

1. ✅ Access Grafana: http://20.235.34.175:3000
2. ✅ Change admin password
3. ✅ Import dashboard from `monitoring/dashboard-debezium-overview.json`
4. ✅ Enable JMX metrics if needed
5. ✅ Verify data flowing in dashboard
6. ✅ Configure alert notifications (Slack/Email)
7. ✅ Create custom dashboards for your use case
8. ✅ Set up long-term storage (optional)
9. ✅ Configure HTTPS/TLS (production)
10. ✅ Document runbooks for alerts

---

**Monitoring deployment complete! 📊✅**

**Start monitoring now:** http://20.235.34.175:3000

**Read first:** `monitoring/QUICK-START.md`
