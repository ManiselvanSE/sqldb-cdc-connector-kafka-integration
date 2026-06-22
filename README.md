# SQL Server CDC Connector - Kafka Integration

Real-time Change Data Capture (CDC) from Azure SQL Server to Apache Kafka using Debezium on Kubernetes.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.24+-blue.svg)](https://kubernetes.io/)
[![Kafka](https://img.shields.io/badge/Kafka-3.x-orange.svg)](https://kafka.apache.org/)
[![Debezium](https://img.shields.io/badge/Debezium-2.5.4-red.svg)](https://debezium.io/)

---

## 🎯 Overview

Production-ready deployment of Debezium SQL Server CDC connector on Kubernetes, streaming change events from Azure SQL Server to Apache Kafka in real-time.

### Key Features

- ✅ **Real-time CDC** - Capture database changes with <1 second latency
- ✅ **High Availability** - Multi-broker Kafka cluster with replication
- ✅ **Production Monitoring** - Prometheus + Grafana with pre-built dashboards
- ✅ **Enterprise Ready** - Security, scaling, and operational best practices
- ✅ **Complete Documentation** - Setup guides, runbooks, and presentations

---

## 🏗️ Architecture

\`\`\`
Azure SQL Server (CDC Enabled)
        │
        │ Read Change Tables
        ▼
Debezium SQL Server Connector
  (Kafka Connect Workers)
        │
        │ Stream Events
        ▼
    Kafka Cluster
  (3 Brokers, HA)
        │
        │ Consume
        ▼
  Downstream Apps
\`\`\`

---

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster (AKS, GKE, EKS, or on-prem)
- kubectl configured with cluster access
- Azure SQL Server with CDC enabled
- Helm 3.x installed

### Deployment Steps

\`\`\`bash
# 1. Clone repository
git clone https://github.com/ManiselvanSE/sqldb-cdc-connector-kafka-integration.git
cd sqldb-cdc-connector-kafka-integration

# 2. Create namespaces
kubectl create namespace confluent
kubectl create namespace monitoring

# 3. Install Confluent Operator
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
helm install confluent-operator \\
  confluentinc/confluent-for-kubernetes \\
  --namespace confluent

# 4. Deploy Kafka Connect
kubectl apply -f deployment/connect-cluster.yaml

# 5. Create SQL Server credentials secret
kubectl create secret generic sqlserver-credentials \\
  --from-literal=username='your-user' \\
  --from-literal=password='your-password' \\
  -n confluent

# 6. Deploy Debezium connector
kubectl apply -f deployment/sqlserver-connector.yaml

# 7. Deploy monitoring stack
kubectl apply -f monitoring/prometheus-operator.yaml
kubectl apply -f monitoring/prometheus-direct.yaml
kubectl apply -f monitoring/grafana.yaml
kubectl apply -f monitoring/servicemonitors.yaml
kubectl apply -f monitoring/prometheus-rules.yaml

# 8. Verify deployment
kubectl get pods -n confluent
kubectl get connector -n confluent
\`\`\`

**Detailed Setup:** See [PRODUCTION-SETUP-QUICK-REFERENCE.md](PRODUCTION-SETUP-QUICK-REFERENCE.md)

---

## 📁 Project Structure

\`\`\`
.
├── deployment/
│   ├── connect-cluster.yaml           # Kafka Connect deployment
│   └── sqlserver-connector.yaml       # Debezium connector config
│
├── monitoring/
│   ├── prometheus-operator.yaml       # Prometheus operator
│   ├── prometheus-direct.yaml         # Prometheus instance
│   ├── grafana.yaml                   # Grafana deployment
│   ├── servicemonitors.yaml           # Metrics scrape configs
│   ├── prometheus-rules.yaml          # Alert rules (9 alerts)
│   ├── dashboard-debezium-working.json # Working Grafana dashboard
│   ├── MONITORING-SETUP.md            # Monitoring guide
│   ├── QUICK-START.md                 # Quick monitoring setup
│   └── README.md                      # Monitoring overview
│
├── scripts/
│   └── quick-commands.sh              # Helper utility script
│
├── setup-document.md         # 45-slide presentation
├── PRODUCTION-SETUP-QUICK-REFERENCE.md # Operations cheat sheet
├── PRODUCTION-ARCHITECTURE-OVERVIEW.md # Architecture guide
├── PRESENTATION-README.md             # Presentation materials guide
├── CLI-COMMANDS.md                    # Useful CLI commands
├── CONFLUENT-LICENSE.md               # License information
└── README.md                          # This file
\`\`\`

---

## 📊 Monitoring

### Access Dashboards

After deployment, access monitoring interfaces:

- **Grafana**: \`http://<GRAFANA_IP>:3000\` (admin/admin)
- **Prometheus**: \`http://<PROMETHEUS_IP>:9090\`

### Pre-Built Dashboard

Import the working dashboard: \`monitoring/dashboard-debezium-working.json\`

**Metrics Displayed:**
- Connector status and health
- CDC throughput (records/second)
- Replication lag (milliseconds)
- Database connection status
- Error metrics
- Queue utilization

### Alerts (9 pre-configured)

- DebeziumConnectorDown (Critical)
- DebeziumTaskFailed (Critical)  
- DebeziumHighLag (Warning)
- KafkaBrokerDown (Critical)
- And more...

---

## 🔧 Configuration

### SQL Server Setup

\`\`\`sql
-- Enable CDC on database
USE YourDatabase;
EXEC sys.sp_cdc_enable_db;

-- Enable CDC on tables
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'YourTable',
    @role_name = NULL,
    @supports_net_changes = 1;

-- Create Debezium user with permissions
CREATE LOGIN debezium_user WITH PASSWORD = 'SecurePassword123!';
USE YourDatabase;
CREATE USER debezium_user FOR LOGIN debezium_user;
GRANT SELECT ON SCHEMA::cdc TO debezium_user;
GRANT EXECUTE ON SCHEMA::cdc TO debezium_user;
GRANT VIEW DATABASE STATE TO debezium_user;
\`\`\`

### Connector Configuration

Edit \`deployment/sqlserver-connector.yaml\`:

\`\`\`yaml
database.hostname: "yourserver.database.windows.net"
database.port: "1433"
database.names: "YourDatabase"
table.include.list: "dbo.table1,dbo.table2"
snapshot.mode: "initial"
\`\`\`

---

## 🔍 Operations

### Quick Commands

Use the helper script:

\`\`\`bash
# Check full status
./scripts/quick-commands.sh status

# View connector logs
./scripts/quick-commands.sh logs

# Consume CDC events
./scripts/quick-commands.sh consume
\`\`\`

### Manual Commands

\`\`\`bash
# Check connector status
kubectl get connector -n confluent

# View logs
kubectl logs connect-0 -n confluent | grep -i debezium

# List CDC topics
kubectl exec kafka-0 -n confluent -- kafka-topics \\
  --bootstrap-server kafka:9071 --list

# Consume events
kubectl exec kafka-0 -n confluent -- kafka-console-consumer \\
  --bootstrap-server kafka:9071 \\
  --topic sqlserver.dbo.your_table \\
  --from-beginning --max-messages 10
\`\`\`

**More commands:** See [CLI-COMMANDS.md](CLI-COMMANDS.md)

---

## 📖 Documentation

### Quick References
- **[Quick Start Guide](PRODUCTION-SETUP-QUICK-REFERENCE.md)** - Commands and operations
- **[CLI Commands](CLI-COMMANDS.md)** - Useful kubectl and Kafka commands  
- **[Monitoring Guide](monitoring/MONITORING-SETUP.md)** - Complete monitoring setup

### Production Guides
- **[Production Setup Slides](setup-document.md)** - 45-slide presentation
- **[Architecture Overview](PRODUCTION-ARCHITECTURE-OVERVIEW.md)** - System design
- **[Failover & High Availability](FAILOVER-AND-HIGH-AVAILABILITY.md)** - AG setup and failover handling
- **[Demo Runbook](DEMO-RUNBOOK.md)** - Live demonstration guide

### Troubleshooting

| Issue | Solution |
|-------|----------|
| Connector not starting | Check logs: \`kubectl logs connect-0 -n confluent\` |
| No metrics in Grafana | Verify JMX: \`kubectl exec connect-0 -n confluent -- curl localhost:7778/metrics\` |
| High lag | Scale Connect: \`kubectl scale connect connect --replicas=3 -n confluent\` |

---

## 🔐 Security

### Production Checklist

- [ ] Enable TLS for SQL Server connections
- [ ] Use Azure Key Vault for secrets
- [ ] Enable Kafka SASL/SCRAM or mTLS
- [ ] Configure network policies
- [ ] Use private endpoints for SQL Server
- [ ] Enable audit logging
- [ ] Rotate credentials regularly

---

## 📈 Performance

### Sizing Guidelines

| Environment | Tables | Events/sec | Kafka (CPU/Mem) | Connect (CPU/Mem) |
|-------------|--------|------------|-----------------|-------------------|
| Small | <100 | <1K | 2 / 4GB | 1 / 4GB |
| Medium | 100-500 | 1K-10K | 4 / 8GB | 2 / 8GB |
| Large | 500+ | 10K+ | 8 / 16GB | 4 / 16GB |

### Tuning

\`\`\`yaml
# Connector optimization
max.batch.size: 4096
max.queue.size: 16384
poll.interval.ms: 1000

# Kafka topic settings
compression.type: snappy
retention.ms: 604800000  # 7 days
min.insync.replicas: 2
\`\`\`

---

## 💰 Cost Estimate (Azure, Monthly)

| Resource | Specification | Cost (USD) |
|----------|---------------|------------|
| AKS Cluster | 5 nodes (Standard_D8s_v3) | ~$1,400 |
| Azure SQL | Standard S2 | ~$150 |
| Storage | 1TB managed disks | ~$100 |
| Load Balancer | 2 public IPs | ~$20 |
| **Total** | | **~$1,670** |

*Use Reserved Instances for 30-50% savings*

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Push and open a Pull Request

---

## 📝 License

MIT License - See LICENSE file

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/ManiselvanSE/sqldb-cdc-connector-kafka-integration/issues)
- **Documentation**: See docs above
- **Debezium**: https://debezium.io/documentation/

---

**⭐ Star this repo if you find it useful!**

**Built with ❤️ for real-time data streaming**
