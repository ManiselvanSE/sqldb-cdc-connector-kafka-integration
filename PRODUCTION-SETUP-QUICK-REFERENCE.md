# Production Setup - Quick Reference Guide

**Debezium CDC on Kubernetes - Production Deployment**

---

## 📋 Pre-Deployment Checklist

### Infrastructure Requirements
- [ ] Kubernetes cluster (AKS recommended)
  - 5+ nodes (8 vCPU, 32GB RAM each)
  - Version 1.24+
  - Storage: Azure Disk CSI driver
  - LoadBalancer or Ingress controller
- [ ] Azure SQL Server
  - Standard S2+ tier
  - CDC enabled
  - SQL Agent running
  - Network access from K8s cluster

### Access & Tools
- [ ] kubectl with cluster-admin access
- [ ] Azure CLI installed
- [ ] Helm 3.x installed
- [ ] Git for configuration management

---

## 🚀 Deployment Commands - Quick Copy/Paste

### 1. Create Namespaces
```bash
kubectl create namespace confluent
kubectl create namespace monitoring
```

### 2. Install Confluent Operator
```bash
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
helm upgrade --install confluent-operator \
  confluentinc/confluent-for-kubernetes \
  --namespace confluent
```

### 3. Deploy ZooKeeper
```bash
kubectl apply -f zookeeper.yaml
kubectl get zookeeper -n confluent -w
```

### 4. Deploy Kafka
```bash
kubectl apply -f kafka.yaml
kubectl get kafka -n confluent -w
```

### 5. Deploy Kafka Connect
```bash
kubectl apply -f connect.yaml
kubectl get connect -n confluent -w
```

### 6. Create SQL Server Secret
```bash
kubectl create secret generic sqlserver-credentials \
  --from-literal=username='debezium_user' \
  --from-literal=password='YourPassword' \
  -n confluent
```

### 7. Deploy Debezium Connector
```bash
kubectl apply -f sqlserver-connector.yaml
kubectl get connector -n confluent
```

### 8. Deploy Monitoring
```bash
kubectl apply -f monitoring/prometheus-operator.yaml
kubectl apply -f monitoring/prometheus-direct.yaml
kubectl apply -f monitoring/grafana.yaml
kubectl apply -f monitoring/servicemonitors.yaml
kubectl apply -f monitoring/prometheus-rules.yaml
```

---

## 📊 Verification Commands

### Check All Components
```bash
# Confluent components
kubectl get all -n confluent

# Monitoring components
kubectl get all -n monitoring

# Connector status
kubectl get connector -n confluent
kubectl describe connector sqlserver-debezium-connector -n confluent
```

### Check CDC Events
```bash
# List topics
kubectl exec kafka-0 -n confluent -- kafka-topics \
  --bootstrap-server kafka:9071 --list

# Consume from CDC topic
kubectl exec kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka:9071 \
  --topic sqlserver.dbo.your_table \
  --from-beginning --max-messages 10
```

### Access Monitoring
```bash
# Get service IPs
kubectl get svc -n monitoring

# Access Grafana: http://<GRAFANA_IP>:3000
# Access Prometheus: http://<PROMETHEUS_IP>:9090
```

---

## 🔧 Common Operations

### Restart Connector
```bash
kubectl delete connector sqlserver-debezium-connector -n confluent
kubectl apply -f sqlserver-connector.yaml
```

### Scale Connect Workers
```bash
kubectl scale connect connect --replicas=3 -n confluent
```

### View Logs
```bash
# Connect logs
kubectl logs connect-0 -n confluent -f

# Connector logs
kubectl logs connect-0 -n confluent | grep -i debezium

# Kafka logs
kubectl logs kafka-0 -n confluent -f
```

### Check Metrics
```bash
# Connect metrics
kubectl exec connect-0 -n confluent -- curl -s localhost:7778/metrics

# Kafka metrics
kubectl exec kafka-0 -n confluent -- curl -s localhost:7778/metrics
```

---

## 🚨 Troubleshooting Quick Fixes

### Connector Not Starting
```bash
# Check connector status
kubectl describe connector sqlserver-debezium-connector -n confluent

# Check Connect logs
kubectl logs connect-0 -n confluent | grep -i error

# Common fix: Recreate connector
kubectl delete connector sqlserver-debezium-connector -n confluent
kubectl apply -f sqlserver-connector.yaml
```

### No Metrics in Grafana
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring prometheus-0 9090:9090
# Open: http://localhost:9090/targets

# Check JMX exporter
kubectl exec connect-0 -n confluent -- curl -s localhost:7778/metrics | head

# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring
```

### High Lag
```bash
# Check lag metric
curl 'http://<PROMETHEUS_IP>:9090/api/v1/query?query=debezium_sql_server_connector_metrics_millisecondsbehindsource'

# Scale up Connect workers
kubectl scale connect connect --replicas=3 -n confluent

# Increase connector tasks (if supported)
# Edit sqlserver-connector.yaml: tasks.max: 2
kubectl apply -f sqlserver-connector.yaml
```

---

## 🔐 Security Hardening

### Enable TLS for SQL Server
```yaml
# In sqlserver-connector.yaml
database.encrypt: "true"
database.ssl.trustServerCertificate: "false"
```

### Use Azure Key Vault (Recommended)
```bash
# Install CSI driver
helm repo add csi-secrets-store-provider-azure \
  https://azure.github.io/secrets-store-csi-driver-provider-azure/charts

helm install csi csi-secrets-store-provider-azure/csi-secrets-store-provider-azure

# Create SecretProviderClass (refer to Azure documentation)
```

### Change Grafana Password
```bash
kubectl exec -it deployment/grafana -n monitoring -- \
  grafana-cli admin reset-admin-password <NEW_PASSWORD>
```

---

## 📈 Production Sizing Guide

### Small Environment (< 100 tables, < 1K events/sec)
| Component | Replicas | CPU | Memory | Storage |
|-----------|----------|-----|--------|---------|
| Kafka | 3 | 2 | 4Gi | 100Gi |
| Connect | 2 | 1 | 4Gi | - |
| ZooKeeper | 3 | 0.5 | 1Gi | 50Gi |
| Prometheus | 1 | 0.5 | 2Gi | 20Gi |

### Medium Environment (100-500 tables, 1K-10K events/sec)
| Component | Replicas | CPU | Memory | Storage |
|-----------|----------|-----|--------|---------|
| Kafka | 3 | 4 | 8Gi | 200Gi |
| Connect | 3 | 2 | 8Gi | - |
| ZooKeeper | 3 | 1 | 2Gi | 50Gi |
| Prometheus | 1 | 1 | 4Gi | 50Gi |

### Large Environment (500+ tables, 10K+ events/sec)
| Component | Replicas | CPU | Memory | Storage |
|-----------|----------|-----|--------|---------|
| Kafka | 5 | 8 | 16Gi | 500Gi |
| Connect | 5 | 4 | 16Gi | - |
| ZooKeeper | 5 | 2 | 4Gi | 100Gi |
| Prometheus | 1 | 2 | 8Gi | 100Gi |

---

## 🎯 Performance Tuning

### Connector Optimization
```yaml
# In sqlserver-connector.yaml
max.batch.size: 4096
max.queue.size: 16384
poll.interval.ms: 1000
tasks.max: 2  # If connector supports it
```

### Kafka Topic Configuration
```yaml
# For CDC topics
cleanup.policy: delete
retention.ms: 604800000  # 7 days
compression.type: snappy
min.insync.replicas: 2
replication.factor: 3
```

### Connect Worker JVM Tuning
```yaml
# In connect.yaml
env:
  - name: KAFKA_HEAP_OPTS
    value: "-Xms4g -Xmx4g"
  - name: KAFKA_JVM_PERFORMANCE_OPTS
    value: "-XX:+UseG1GC -XX:MaxGCPauseMillis=20"
```

---

## 📝 SQL Server CDC Setup

### Enable CDC on Database
```sql
USE YourDatabase;
EXEC sys.sp_cdc_enable_db;
```

### Enable CDC on Tables
```sql
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'TableName',
    @role_name = NULL,
    @supports_net_changes = 1;
```

### Create Debezium User
```sql
CREATE LOGIN debezium_user WITH PASSWORD = 'SecurePassword123!';
USE YourDatabase;
CREATE USER debezium_user FOR LOGIN debezium_user;

GRANT SELECT ON SCHEMA::cdc TO debezium_user;
GRANT SELECT ON SCHEMA::dbo TO debezium_user;
GRANT EXECUTE ON SCHEMA::cdc TO debezium_user;
GRANT VIEW DATABASE STATE TO debezium_user;
```

### Verify CDC Status
```sql
-- Check database CDC status
SELECT name, is_cdc_enabled 
FROM sys.databases 
WHERE name = 'YourDatabase';

-- Check table CDC status
SELECT name, is_tracked_by_cdc
FROM sys.tables
WHERE is_tracked_by_cdc = 1;

-- Check CDC jobs
EXEC sys.sp_cdc_help_jobs;
```

---

## 🔄 Maintenance Schedule

### Daily
- [ ] Check connector status
- [ ] Monitor lag metrics
- [ ] Review error logs
- [ ] Check disk usage

### Weekly
- [ ] Review resource utilization
- [ ] Analyze performance trends
- [ ] Check for Kubernetes updates
- [ ] Review alert history

### Monthly
- [ ] Apply security patches
- [ ] Test backup/restore
- [ ] Review and optimize configs
- [ ] Update documentation
- [ ] Rotate credentials

---

## 📞 Support Resources

### Documentation Locations
- Production slides: `PRODUCTION-SETUP-SLIDES.md`
- Monitoring guide: `monitoring/MONITORING-SETUP.md`
- Quick start: `monitoring/QUICK-START.md`
- CLI commands: `CLI-COMMANDS.md`

### External Resources
- Debezium Docs: https://debezium.io/documentation/
- Confluent Docs: https://docs.confluent.io/
- Prometheus Docs: https://prometheus.io/docs/
- Grafana Docs: https://grafana.com/docs/

### Community Support
- Debezium Mailing List
- Confluent Community Slack
- Stack Overflow (#debezium, #kafka)

---

## 🚀 Deployment Time Estimates

| Task | Estimated Time |
|------|----------------|
| Infrastructure provisioning | 30-60 min |
| Confluent operator installation | 5 min |
| ZooKeeper deployment | 5 min |
| Kafka deployment | 10 min |
| Connect deployment | 15 min (plugin download) |
| Connector deployment | 5 min |
| Monitoring stack | 10 min |
| Testing & verification | 30 min |
| **Total** | **~2 hours** |

*Note: Times exclude infrastructure provisioning wait times*

---

## ✅ Go-Live Checklist

### Pre-Production
- [ ] All components deployed
- [ ] High availability tested (3+ Kafka, 2+ Connect)
- [ ] CDC enabled on all tables
- [ ] Events flowing to Kafka
- [ ] Monitoring dashboards working
- [ ] Alerts configured and tested
- [ ] Security hardening complete
- [ ] Performance testing done
- [ ] DR procedures documented

### Production
- [ ] Runbooks created
- [ ] Team trained
- [ ] On-call rotation established
- [ ] Support contacts documented
- [ ] Backup schedules confirmed
- [ ] Change management process
- [ ] Incident response plan

---

**Last Updated:** 2026-06-22  
**Version:** 1.0
