---
marp: true
theme: default
paginate: true
---

# Debezium CDC on Kubernetes
## Production Setup Guide

**Change Data Capture from Azure SQL Server to Kafka**

---

## Agenda

1. Architecture Overview
2. Prerequisites & Planning
3. Infrastructure Setup
4. Confluent Platform Deployment
5. SQL Server Configuration
6. Debezium Connector Setup
7. Monitoring Stack
8. Security & Best Practices
9. Operations & Troubleshooting

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     AZURE SQL SERVER                        │
│                  (CDC Enabled Database)                     │
└──────────────────────┬──────────────────────────────────────┘
                       │ CDC Read (Port 1433)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              DEBEZIUM SQL SERVER CONNECTOR                  │
│                  (Kafka Connect Worker)                     │
└──────────────────────┬──────────────────────────────────────┘
                       │ Events Stream
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    KAFKA CLUSTER                            │
│              (3 Brokers - High Availability)                │
└──────────────────────┬──────────────────────────────────────┘
                       │ Consume Events
                       ▼
┌─────────────────────────────────────────────────────────────┐
│               DOWNSTREAM CONSUMERS                          │
│        (Applications, Analytics, Data Warehouse)            │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Components

| Component | Purpose | HA Setup |
|-----------|---------|----------|
| **Azure SQL Server** | Source database with CDC enabled | Geo-replication (Primary + Secondary) |
| **Kafka Brokers** | Event streaming platform | 3 brokers, replication factor 3 |
| **Kafka Connect** | Connector runtime | 2+ workers for HA |
| **Debezium Connector** | CDC capture engine | Distributed across Connect workers |
| **Prometheus** | Metrics collection | 1 instance with persistent storage |
| **Grafana** | Visualization & dashboards | 1 instance with HA optional |

---

## Prerequisites - Infrastructure

### Kubernetes Cluster
- **Provider:** Azure AKS (or any K8s cluster)
- **Version:** 1.24+
- **Nodes:** 
  - Minimum: 3 nodes (4 vCPU, 16GB RAM each)
  - Production: 5+ nodes (8 vCPU, 32GB RAM each)
- **Storage:** Azure Disk CSI driver for persistent volumes
- **Networking:** Load Balancer support or Ingress controller

### Access Requirements
- `kubectl` access with cluster-admin privileges
- Azure CLI (for AKS management)
- Helm 3.x installed

---

## Prerequisites - SQL Server

### Azure SQL Database
- **Edition:** Standard S2 or higher
- **Version:** SQL Server 2016+ (Azure SQL Database supported)
- **CDC Enabled:** Yes (mandatory)
- **Agent Running:** SQL Server Agent must be running
- **Network Access:** 
  - Allow Kubernetes cluster IPs
  - Port 1433 open
  - SSL/TLS enabled

### Database User Permissions
```sql
-- Required permissions for CDC user
GRANT SELECT ON SCHEMA::cdc TO debezium_user;
GRANT SELECT ON SCHEMA::dbo TO debezium_user;
GRANT EXECUTE ON SCHEMA::cdc TO debezium_user;
GRANT VIEW DATABASE STATE TO debezium_user;
```

---

## Step 1: Enable CDC on SQL Server

### Enable CDC on Database
```sql
-- Connect to your database
USE YourDatabase;
GO

-- Enable CDC on database
EXEC sys.sp_cdc_enable_db;
GO

-- Verify CDC is enabled
SELECT name, is_cdc_enabled 
FROM sys.databases 
WHERE name = 'YourDatabase';
GO
```

### Enable CDC on Tables
```sql
-- Enable CDC on specific tables
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'YourTableName',
    @role_name = NULL,
    @supports_net_changes = 1;
GO
```

---

## Step 2: Create Kubernetes Namespace

```bash
# Create namespace for Confluent Platform
kubectl create namespace confluent

# Create namespace for monitoring
kubectl create namespace monitoring

# Verify namespaces
kubectl get namespaces
```

---

## Step 3: Install Confluent for Kubernetes

### Add Confluent Helm Repository
```bash
# Add Confluent Helm repo
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

# Install Confluent for Kubernetes operator
helm upgrade --install confluent-operator \
  confluentinc/confluent-for-kubernetes \
  --namespace confluent \
  --set namespaced=false
```

### Verify Operator Installation
```bash
kubectl get pods -n confluent
# Should see: confluent-operator-xxxxx running
```

---

## Step 4: Deploy Kafka Cluster

### Create Kafka Custom Resource
```yaml
# kafka.yaml
apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
  namespace: confluent
spec:
  replicas: 3
  image:
    application: confluentinc/cp-server:7.8.0
    init: confluentinc/confluent-init-container:2.9.0
  dataVolumeCapacity: 100Gi
  metricReporter:
    enabled: true
  resources:
    requests:
      cpu: 2000m
      memory: 4Gi
    limits:
      cpu: 4000m
      memory: 8Gi
```

---

## Step 4: Deploy Kafka Cluster (cont.)

```bash
# Apply Kafka configuration
kubectl apply -f kafka.yaml

# Wait for Kafka to be ready (5-10 minutes)
kubectl get kafka -n confluent -w

# Verify Kafka pods
kubectl get pods -n confluent | grep kafka
# Should see: kafka-0, kafka-1, kafka-2 running
```

---

## Step 5: Deploy ZooKeeper

### Create ZooKeeper Custom Resource
```yaml
# zookeeper.yaml
apiVersion: platform.confluent.io/v1beta1
kind: Zookeeper
metadata:
  name: zookeeper
  namespace: confluent
spec:
  replicas: 3
  image:
    application: confluentinc/cp-zookeeper:7.8.0
    init: confluentinc/confluent-init-container:2.9.0
  dataVolumeCapacity: 50Gi
  logVolumeCapacity: 20Gi
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
```

```bash
kubectl apply -f zookeeper.yaml
```

---

## Step 6: Deploy Kafka Connect

### Create Connect Custom Resource
```yaml
# connect.yaml
apiVersion: platform.confluent.io/v1beta1
kind: Connect
metadata:
  name: connect
  namespace: confluent
spec:
  replicas: 2
  image:
    application: confluentinc/cp-server-connect:7.8.0
    init: confluentinc/confluent-init-container:2.9.0
  build:
    type: onDemand
    onDemand:
      plugins:
        locationType: confluentHub
        confluentHub:
          - name: debezium-debezium-connector-sqlserver
            owner: debezium
            version: "2.5.4"
```

---

## Step 6: Deploy Kafka Connect (cont.)

```yaml
# connect.yaml (continued)
  podTemplate:
    resources:
      requests:
        cpu: 1000m
        memory: 4Gi
      limits:
        cpu: 2000m
        memory: 8Gi
  dependencies:
    kafka:
      bootstrapEndpoint: kafka:9071
```

```bash
# Deploy Connect
kubectl apply -f connect.yaml

# Wait for Connect to be ready (10-15 minutes for plugin download)
kubectl get connect -n confluent -w
```

---

## Step 7: Create Database Credentials Secret

```bash
# Create Kubernetes secret for SQL Server credentials
kubectl create secret generic sqlserver-credentials \
  --from-literal=username='debezium_user' \
  --from-literal=password='YourSecurePassword123!' \
  -n confluent

# Verify secret
kubectl get secret sqlserver-credentials -n confluent
```

**Production Best Practice:**
- Use Azure Key Vault or HashiCorp Vault
- Rotate credentials regularly
- Use managed identities where possible

---

## Step 8: Deploy Debezium Connector

### Create Connector Configuration
```yaml
# sqlserver-connector.yaml
apiVersion: platform.confluent.io/v1beta1
kind: Connector
metadata:
  name: sqlserver-debezium-connector
  namespace: confluent
spec:
  class: "io.debezium.connector.sqlserver.SqlServerConnector"
  taskMax: 1
  connectClusterRef:
    name: connect
  configs:
    database.hostname: "yourserver.database.windows.net"
    database.port: "1433"
    database.user: "${file:/mnt/secrets/sqlserver-credentials/username}"
    database.password: "${file:/mnt/secrets/sqlserver-credentials/password}"
    database.names: "YourDatabaseName"
```

---

## Step 8: Deploy Debezium Connector (cont.)

```yaml
# sqlserver-connector.yaml (continued)
    table.include.list: "dbo.table1,dbo.table2"
    topic.prefix: "sqlserver"
    schema.history.internal.kafka.bootstrap.servers: "kafka:9071"
    schema.history.internal.kafka.topic: "schema-changes.sqlserver"
    database.encrypt: "true"
    database.ssl.trustServerCertificate: "false"
    snapshot.mode: "initial"
    key.converter: "org.apache.kafka.connect.json.JsonConverter"
    value.converter: "org.apache.kafka.connect.json.JsonConverter"
    transforms: "unwrap"
    transforms.unwrap.type: "io.debezium.transforms.ExtractNewRecordState"
    transforms.unwrap.drop.tombstones: "false"
```

---

## Step 8: Deploy Debezium Connector (cont.)

### Mount Secrets to Connect
```yaml
# Update connect.yaml to mount secrets
spec:
  podTemplate:
    volumes:
      - name: sqlserver-credentials
        secret:
          secretName: sqlserver-credentials
    volumeMounts:
      - name: sqlserver-credentials
        mountPath: /mnt/secrets/sqlserver-credentials
        readOnly: true
```

```bash
# Apply updated Connect config
kubectl apply -f connect.yaml

# Deploy connector
kubectl apply -f sqlserver-connector.yaml
```

---

## Step 9: Verify Connector Deployment

```bash
# Check connector status
kubectl get connector -n confluent

# Check connector details
kubectl describe connector sqlserver-debezium-connector -n confluent

# View connector logs
kubectl logs connect-0 -n confluent | grep -i debezium

# Check if topics are created
kubectl exec kafka-0 -n confluent -- kafka-topics \
  --bootstrap-server kafka:9071 \
  --list | grep sqlserver
```

**Expected Topics:**
- `sqlserver.dbo.table1`
- `sqlserver.dbo.table2`
- `schema-changes.sqlserver`

---

## Step 10: Monitor CDC Events

### Consume CDC Events
```bash
# Consume from a CDC topic
kubectl exec kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka:9071 \
  --topic sqlserver.dbo.your_table \
  --from-beginning \
  --max-messages 10
```

### Insert Test Data
```sql
-- On SQL Server
INSERT INTO dbo.your_table (id, name, created_at)
VALUES (1, 'Test Record', GETDATE());
```

**Verify:** Event appears in Kafka topic within seconds

---

## Step 11: Deploy Monitoring Stack

### Install Prometheus Operator
```bash
# Deploy Prometheus Operator
kubectl apply -f monitoring/prometheus-operator.yaml

# Verify operator is running
kubectl get pods -n monitoring | grep prometheus-operator
```

### Deploy Prometheus Instance
```bash
# Deploy Prometheus with persistent storage
kubectl apply -f monitoring/prometheus-direct.yaml

# Verify Prometheus pod
kubectl get pods -n monitoring | grep prometheus-0
# Should be Running with 1/1 ready
```

---

## Step 12: Deploy Grafana

```bash
# Deploy Grafana
kubectl apply -f monitoring/grafana.yaml

# Get Grafana LoadBalancer IP
kubectl get svc grafana -n monitoring

# Default credentials
# Username: admin
# Password: admin (CHANGE THIS IMMEDIATELY!)
```

### Configure ServiceMonitors
```bash
# Deploy ServiceMonitors for Kafka and Connect
kubectl apply -f monitoring/servicemonitors.yaml

# This configures Prometheus to scrape:
# - Kafka brokers on port 7778
# - Connect workers on port 7778
```

---

## Step 13: Configure Alerts

```bash
# Deploy alert rules
kubectl apply -f monitoring/prometheus-rules.yaml
```

### Key Alerts Configured
- **DebeziumConnectorDown** - Connector stopped
- **DebeziumTaskFailed** - Task failure
- **DebeziumHighLag** - >10K pending records
- **DebeziumNoRecordsProcessed** - No activity for 10min
- **KafkaConnectWorkerDown** - Worker unavailable
- **KafkaBrokerDown** - Broker offline

---

## Step 14: Import Grafana Dashboard

1. **Access Grafana:** http://<GRAFANA_IP>:3000
2. **Login** with credentials
3. **Change default password**
4. **Import Dashboard:**
   - Go to Dashboards → Import
   - Upload: `dashboard-debezium-working.json`
   - Select datasource: Prometheus
   - Click Import

### Dashboard Metrics
- Active connectors & tasks
- Database connection status
- CDC throughput (records/sec)
- Replication lag
- Error metrics
- Queue utilization

---

## Production Best Practices - High Availability

### Kafka Cluster
- **Replicas:** 3+ brokers
- **Replication Factor:** 3
- **Min In-Sync Replicas:** 2
- **Unclean Leader Election:** Disabled

### Kafka Connect
- **Workers:** 2+ instances
- **Distribution:** Across availability zones
- **Connector Tasks:** Distribute across workers

### SQL Server
- **Geo-Replication:** Primary + Secondary replicas
- **Read from Secondary:** Use secondary for CDC reads
- **Failover:** Test failover procedures

---

## Production Best Practices - Resource Sizing

### Kafka Brokers
```yaml
resources:
  requests:
    cpu: 4000m
    memory: 8Gi
  limits:
    cpu: 8000m
    memory: 16Gi
storage: 200Gi per broker
```

### Connect Workers
```yaml
resources:
  requests:
    cpu: 2000m
    memory: 4Gi
  limits:
    cpu: 4000m
    memory: 8Gi
```

### Monitor and adjust based on:
- Message throughput
- Number of tables
- Retention period

---

## Production Best Practices - Security

### Network Security
- **Private Endpoints:** Use Azure Private Link for SQL Server
- **Network Policies:** Restrict pod-to-pod communication
- **TLS/SSL:** Enable encryption in transit
  - SQL Server connections
  - Kafka client connections
  - Kafka inter-broker communication

### Authentication & Authorization
- **Kafka:** SASL/SCRAM or mTLS
- **SQL Server:** Azure AD authentication preferred
- **RBAC:** Kubernetes RBAC for resource access
- **Secrets:** Use Azure Key Vault or HashiCorp Vault

---

## Production Best Practices - Data Management

### Kafka Topic Configuration
```yaml
# For CDC topics
cleanup.policy: delete
retention.ms: 604800000  # 7 days
retention.bytes: 1073741824  # 1GB per partition
compression.type: snappy
min.insync.replicas: 2
```

### Schema Management
- **Topic:** `schema-changes.sqlserver`
- **Retention:** Long-term (90+ days)
- **Backup:** Regular backups of schema history

### Dead Letter Queue
- Configure DLQ for failed records
- Monitor and process DLQ regularly

---

## Production Best Practices - Monitoring

### Key Metrics to Monitor

**Connector Health:**
- Connector status (running/failed)
- Task status
- Last processed event timestamp

**Performance:**
- CDC lag (milliseconds behind source)
- Records per second
- Snapshot progress

**Resources:**
- CPU/Memory utilization
- Disk I/O
- Network throughput

---

## Production Best Practices - Monitoring (cont.)

### Alert Notification Channels

Configure alerts to send to:
- **Slack/Teams:** Immediate team notifications
- **PagerDuty/Opsgenie:** On-call escalation
- **Email:** Management reports

```yaml
# Example: Alertmanager configuration
receivers:
  - name: 'team-slack'
    slack_configs:
      - api_url: 'https://hooks.slack.com/...'
        channel: '#kafka-alerts'
        
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '<key>'
```

---

## Production Best Practices - Backup & DR

### Backup Strategy
1. **Kafka Data:**
   - Mirror to secondary cluster (MirrorMaker 2)
   - Backup to object storage (S3/Azure Blob)
   
2. **Schema History:**
   - Regular exports of schema-changes topic
   - Store in version control

3. **Connector Configs:**
   - Store all YAML configs in Git
   - Version control and CI/CD

### Disaster Recovery
- Document failover procedures
- Regular DR drills
- RTO/RPO targets defined

---

## Operations - Common Tasks

### Restart Connector
```bash
# Delete and recreate connector
kubectl delete connector sqlserver-debezium-connector -n confluent
kubectl apply -f sqlserver-connector.yaml
```

### Scale Connect Workers
```bash
# Edit connect.yaml and change replicas
kubectl edit connect connect -n confluent

# Or use kubectl scale
kubectl scale connect connect --replicas=3 -n confluent
```

### View Connector Status
```bash
# Get connector status
kubectl get connector -n confluent

# Describe connector
kubectl describe connector sqlserver-debezium-connector -n confluent
```

---

## Operations - Add New Tables

### 1. Enable CDC on SQL Server
```sql
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'new_table',
    @role_name = NULL,
    @supports_net_changes = 1;
```

### 2. Update Connector Config
```yaml
# Edit sqlserver-connector.yaml
table.include.list: "dbo.table1,dbo.table2,dbo.new_table"
```

### 3. Apply Changes
```bash
kubectl apply -f sqlserver-connector.yaml
```

**Note:** Connector will automatically create new Kafka topic

---

## Troubleshooting - Connector Not Starting

### Check 1: Connector Status
```bash
kubectl describe connector sqlserver-debezium-connector -n confluent
```

### Check 2: Connect Worker Logs
```bash
kubectl logs connect-0 -n confluent | grep -i error
```

### Common Issues:
- **Database connection:** Check credentials, network access
- **CDC not enabled:** Verify CDC is enabled on database/tables
- **Plugin missing:** Verify Debezium plugin installed in Connect
- **Resource limits:** Check CPU/memory limits

---

## Troubleshooting - High Lag

### Check Lag Metrics
```bash
# Query Prometheus
curl 'http://prometheus:9090/api/v1/query?query=debezium_sql_server_connector_metrics_millisecondsbehindsource'
```

### Possible Causes:
1. **High transaction volume:** Scale Connect workers
2. **Large transactions:** Increase `max.batch.size`
3. **Network latency:** Check SQL Server connectivity
4. **Resource constraints:** Increase CPU/memory

### Solutions:
```yaml
# Increase connector parallelism
taskMax: 2

# Tune batch settings
max.batch.size: 4096
max.queue.size: 16384
```

---

## Troubleshooting - Missing Events

### Verify CDC Capture Job
```sql
-- Check if CDC capture job is running
EXEC sys.sp_cdc_help_jobs;

-- Check CDC errors
SELECT * FROM sys.dm_cdc_errors;
```

### Check Connector Offset
```bash
# View connector offsets (internal topic)
kubectl exec kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka:9071 \
  --topic connect-offsets \
  --from-beginning | grep sqlserver
```

### Force Snapshot
```yaml
# Update connector config
snapshot.mode: "schema_only_recovery"
```

---

## Troubleshooting - Prometheus Not Scraping

### Check Targets
```bash
# Access Prometheus UI
kubectl port-forward -n monitoring prometheus-0 9090:9090

# Open: http://localhost:9090/targets
```

### Verify JMX Exporter
```bash
# Test metrics endpoint
kubectl exec connect-0 -n confluent -- \
  curl -s localhost:7778/metrics | head -20
```

### Common Issues:
- ServiceMonitor not created
- JMX exporter port not exposed
- Network policies blocking scrape

---

## Cost Optimization

### Resource Right-Sizing
- Start with minimum specs
- Monitor actual usage
- Scale up based on metrics
- Use Horizontal Pod Autoscaler (HPA)

### Storage Optimization
- **Kafka retention:** 7 days (adjust based on needs)
- **Prometheus retention:** 15 days
- **Compression:** Enable Kafka compression (snappy/lz4)

### Cloud Cost Savings
- Use Azure Reserved Instances
- Use spot/preemptible nodes for non-critical workloads
- Regular cleanup of unused topics
- Archive historical data to cheaper storage (Blob/S3)

---

## Performance Tuning

### Connector Level
```yaml
# Increase throughput
max.batch.size: 4096
max.queue.size: 16384
poll.interval.ms: 1000

# Parallel processing
tasks.max: 2  # If supported by connector
```

### Kafka Level
```yaml
# Producer settings
compression.type: snappy
linger.ms: 10
batch.size: 32768

# Broker settings
num.network.threads: 8
num.io.threads: 16
```

---

## Upgrade Strategy

### Upgrade Order
1. **ZooKeeper** (if version supports rolling upgrade)
2. **Kafka Brokers** (one at a time)
3. **Kafka Connect Workers**
4. **Debezium Connector** (update version)

### Before Upgrade:
- Review release notes
- Test in staging environment
- Backup configurations
- Plan rollback procedure

### During Upgrade:
- Monitor metrics closely
- Check for errors in logs
- Verify CDC events flowing

---

## License Considerations

### Confluent Platform Licensing

**Options:**
1. **Confluent Cloud:** Fully managed, pay-as-you-go
2. **Confluent Enterprise:** Self-managed, enterprise support
3. **Apache Kafka:** Open source, community support

**Trial Limitations:**
- Confluent Control Center (UI)
- Some monitoring features
- Enterprise connectors

**Production:** Purchase license or use Apache Kafka OSS

---

## Checklist - Go-Live Preparation

- [ ] All components deployed and running
- [ ] High availability configured (3+ Kafka brokers, 2+ Connect)
- [ ] CDC enabled on all required tables
- [ ] Connector successfully processing events
- [ ] Monitoring and alerting configured
- [ ] Grafana dashboards imported and working
- [ ] Security hardening completed (TLS, RBAC, secrets)
- [ ] Backup and DR procedures documented
- [ ] Performance testing completed
- [ ] Runbooks created for common operations
- [ ] Team trained on operations and troubleshooting
- [ ] On-call rotation established

---

## Maintenance Windows

### Regular Maintenance Tasks

**Daily:**
- Check connector status
- Monitor lag metrics
- Review error logs

**Weekly:**
- Review resource utilization
- Check disk usage
- Analyze performance trends

**Monthly:**
- Apply security patches
- Review and optimize configurations
- Test backup/restore procedures
- Update documentation

---

## Support & Resources

### Documentation
- **Debezium:** https://debezium.io/documentation/
- **Confluent:** https://docs.confluent.io/
- **Prometheus:** https://prometheus.io/docs/
- **Grafana:** https://grafana.com/docs/

### Community
- Debezium Google Group
- Confluent Community Slack
- Stack Overflow (#debezium, #kafka)

### Professional Support
- Confluent Enterprise Support
- Red Hat Support (for Debezium)
- Cloud provider support (Azure)

---

## Summary

### What We Built
✅ **Kafka Cluster** - 3 brokers for high availability  
✅ **Kafka Connect** - 2 workers with Debezium plugin  
✅ **SQL Server CDC** - Real-time change capture  
✅ **Monitoring Stack** - Prometheus + Grafana  
✅ **Dashboards** - Pre-built CDC metrics visualization  
✅ **Alerts** - 9 critical alerts configured  

### Benefits
- **Real-time data streaming** from SQL Server
- **Scalable architecture** supporting high throughput
- **Full observability** with metrics and dashboards
- **Production-ready** with HA and security

---

## Next Steps

1. **Review this deck** with your team
2. **Provision infrastructure** (AKS cluster, SQL Server)
3. **Follow deployment steps** 1-14
4. **Test with sample data** before production
5. **Train operations team** on common tasks
6. **Schedule go-live** with proper testing

### Questions?

**Contact Information:**
- Documentation: `/Users/maniselvank/Mani/connector/sqldb/`
- Monitoring Guide: `MONITORING-SETUP.md`
- Quick Start: `QUICK-START.md`

---

# Thank You!

**Good luck with your production deployment!**

