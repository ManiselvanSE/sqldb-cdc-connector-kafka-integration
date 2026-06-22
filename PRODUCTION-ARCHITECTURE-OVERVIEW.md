# Production Architecture Overview
## Debezium CDC on Kubernetes - Azure Environment

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AZURE CLOUD                                    │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         AZURE SQL SERVER                             │  │
│  │                                                                      │  │
│  │  ┌──────────────┐              ┌──────────────┐                    │  │
│  │  │   Primary    │──Geo-Rep───▶ │  Secondary   │                    │  │
│  │  │  Database    │              │  Database    │                    │  │
│  │  │  (Write)     │              │   (CDC Read) │                    │  │
│  │  └──────┬───────┘              └──────┬───────┘                    │  │
│  │         │                              │                            │  │
│  │         │ Port 1433 (TLS)              │ Port 1433 (TLS)            │  │
│  └─────────┼──────────────────────────────┼────────────────────────────┘  │
│            │                              │                               │
│            │ CDC Events                   │ Failover CDC                  │
│            ▼                              ▼                               │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                    AZURE KUBERNETES SERVICE (AKS)                   │  │
│  │                                                                     │  │
│  │  ┌───────────────────────────────────────────────────────────────┐ │  │
│  │  │               CONFLUENT NAMESPACE                             │ │  │
│  │  │                                                               │ │  │
│  │  │  ┌─────────────────────────────────────────────────────────┐ │ │  │
│  │  │  │            KAFKA CONNECT CLUSTER                        │ │ │  │
│  │  │  │                                                         │ │ │  │
│  │  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐       │ │ │  │
│  │  │  │  │ Connect-0  │  │ Connect-1  │  │ Connect-2  │       │ │ │  │
│  │  │  │  │ (Worker)   │  │ (Worker)   │  │ (Worker)   │       │ │ │  │
│  │  │  │  │            │  │            │  │            │       │ │ │  │
│  │  │  │  │ Debezium   │  │ Debezium   │  │ Debezium   │       │ │ │  │
│  │  │  │  │ Connector  │  │ Tasks      │  │ Tasks      │       │ │ │  │
│  │  │  │  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘       │ │ │  │
│  │  │  │        │                │                │             │ │ │  │
│  │  │  │        │ Produce CDC Events              │             │ │ │  │
│  │  │  └────────┼────────────────┼────────────────┼─────────────┘ │ │  │
│  │  │           │                │                │               │ │  │
│  │  │           ▼                ▼                ▼               │ │  │
│  │  │  ┌─────────────────────────────────────────────────────┐   │ │  │
│  │  │  │              KAFKA CLUSTER                          │   │ │  │
│  │  │  │                                                     │   │ │  │
│  │  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐   │   │ │  │
│  │  │  │  │  Kafka-0   │  │  Kafka-1   │  │  Kafka-2   │   │   │ │  │
│  │  │  │  │  (Broker)  │  │  (Broker)  │  │  (Broker)  │   │   │ │  │
│  │  │  │  │            │  │            │  │            │   │   │ │  │
│  │  │  │  │  Topics:   │  │  Topics:   │  │  Topics:   │   │   │ │  │
│  │  │  │  │  - dbo.t1  │  │  - dbo.t1  │  │  - dbo.t1  │   │   │ │  │
│  │  │  │  │  - dbo.t2  │  │  - dbo.t2  │  │  - dbo.t2  │   │   │ │  │
│  │  │  │  │  - schema  │  │  - schema  │  │  - schema  │   │   │ │  │
│  │  │  │  │            │  │            │  │            │   │   │ │  │
│  │  │  │  │ RF: 3      │  │ RF: 3      │  │ RF: 3      │   │   │ │  │
│  │  │  │  └────────────┘  └────────────┘  └────────────┘   │   │ │  │
│  │  │  │                                                     │   │ │  │
│  │  │  └─────────────────────────────────────────────────────┘   │ │  │
│  │  │                                                             │ │  │
│  │  │  ┌─────────────────────────────────────────────────────┐   │ │  │
│  │  │  │            ZOOKEEPER ENSEMBLE                       │   │ │  │
│  │  │  │                                                     │   │ │  │
│  │  │  │  ┌──────────┐    ┌──────────┐    ┌──────────┐     │   │ │  │
│  │  │  │  │  ZK-0    │    │  ZK-1    │    │  ZK-2    │     │   │ │  │
│  │  │  │  └──────────┘    └──────────┘    └──────────┘     │   │ │  │
│  │  │  │                                                     │   │ │  │
│  │  │  └─────────────────────────────────────────────────────┘   │ │  │
│  │  │                                                             │ │  │
│  │  └─────────────────────────────────────────────────────────────┘ │  │
│  │                                                                   │  │
│  │  ┌───────────────────────────────────────────────────────────┐   │  │
│  │  │               MONITORING NAMESPACE                        │   │  │
│  │  │                                                           │   │  │
│  │  │  ┌──────────────┐         ┌──────────────┐              │   │  │
│  │  │  │  Prometheus  │────────▶│   Grafana    │              │   │  │
│  │  │  │              │         │              │              │   │  │
│  │  │  │  - Metrics   │         │  - Dashboard │              │   │  │
│  │  │  │  - Alerts    │         │  - Alerts    │              │   │  │
│  │  │  │  - 7d Retain │         │  - Visualize │              │   │  │
│  │  │  └──────┬───────┘         └──────────────┘              │   │  │
│  │  │         │                                                │   │  │
│  │  │         │ Scrape Metrics (every 30s)                    │   │  │
│  │  │         │                                                │   │  │
│  │  │         └─────────────┬──────────────┬─────────────┐    │   │  │
│  │  │                       │              │             │    │   │  │
│  │  │                   JMX :7778      JMX :7778    JMX :7778 │   │  │
│  │  │                       │              │             │    │   │  │
│  │  └───────────────────────┼──────────────┼─────────────┼────┘   │  │
│  │                          │              │             │        │  │
│  └──────────────────────────┼──────────────┼─────────────┼────────┘  │
│                             │              │             │           │
│                        (Connect)       (Kafka)      (ZooKeeper)      │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │                    EXTERNAL ACCESS                            │   │
│  │                                                               │   │
│  │  LoadBalancer IPs:                                           │   │
│  │  - Grafana:    http://XX.XX.XX.XX:3000                       │   │
│  │  - Prometheus: http://XX.XX.XX.XX:9090                       │   │
│  │                                                               │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Component Summary

| Component | Purpose | Instances | Resources | Storage |
|-----------|---------|-----------|-----------|---------|
| **Azure SQL Server** | Source database with CDC | Primary + Secondary | Managed | Managed |
| **Kafka Brokers** | Event streaming & storage | 3 (HA) | 4 CPU, 8GB RAM | 200GB each |
| **ZooKeeper** | Kafka coordination | 3 (Quorum) | 1 CPU, 2GB RAM | 50GB each |
| **Kafka Connect** | Connector runtime | 2-3 (HA) | 2 CPU, 8GB RAM | - |
| **Debezium Connector** | CDC capture engine | 1 connector, 1 task | - | - |
| **Prometheus** | Metrics & alerting | 1 | 1 CPU, 4GB RAM | 50GB |
| **Grafana** | Dashboards & UI | 1 | 0.5 CPU, 1GB RAM | 1GB |

---

## Data Flow

```
1. SQL Server CDC → Captures changes to change tables (CT)
                     │
2. Debezium        → Reads CT tables via JDBC
                     │
3. Transformation  → Converts to Kafka event format
                     │
4. Kafka Producer  → Writes to Kafka topics
                     │
5. Kafka Brokers   → Replicates across 3 brokers (RF=3)
                     │
6. Consumers       → Read events for downstream processing
```

**Latency:** < 1 second (typical)  
**Throughput:** 1K-10K events/sec (depending on configuration)

---

## Network Architecture

```
┌────────────────────────────────────────────────────────────┐
│                     VIRTUAL NETWORK                        │
│                                                            │
│  ┌─────────────────┐         ┌──────────────────────┐    │
│  │  Subnet 1       │         │  Subnet 2            │    │
│  │  (AKS Nodes)    │         │  (SQL Server)        │    │
│  │                 │         │                      │    │
│  │  10.0.0.0/24    │────────▶│  Private Endpoint    │    │
│  │                 │  TLS    │  (SQL Connection)    │    │
│  │  - Kafka        │         │                      │    │
│  │  - Connect      │         │  10.0.1.0/24         │    │
│  │  - ZooKeeper    │         │                      │    │
│  └─────────────────┘         └──────────────────────┘    │
│                                                            │
│  ┌─────────────────┐                                      │
│  │  Load Balancer  │                                      │
│  │  (Public IPs)   │                                      │
│  │                 │                                      │
│  │  - Grafana      │◀──────── External Users             │
│  │  - Prometheus   │                                      │
│  └─────────────────┘                                      │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Security:**
- SQL Server: Private endpoint, TLS encryption
- Kafka: Internal cluster traffic only
- Monitoring: LoadBalancer with optional authentication
- Secrets: Kubernetes secrets or Azure Key Vault

---

## Key Metrics Monitored

### CDC Health
- ✅ Connector status (up/down)
- ✅ Task status
- ✅ Database connection
- ✅ Last event timestamp

### Performance
- ✅ CDC throughput (events/sec)
- ✅ Replication lag (milliseconds)
- ✅ Snapshot progress
- ✅ Queue utilization

### Reliability
- ✅ Error count
- ✅ Task restart count
- ✅ Kafka broker availability
- ✅ Connect worker availability

---

## Alert Thresholds

| Alert | Severity | Threshold | Action |
|-------|----------|-----------|--------|
| ConnectorDown | Critical | Connector stopped | Immediate investigation |
| TaskFailed | Critical | Task failure | Check logs, restart if needed |
| HighLag | Warning | >10,000 records behind | Scale resources |
| NoRecords | Warning | No events for 10min | Check CDC capture job |
| BrokerDown | Critical | Kafka broker offline | Check Kafka cluster |
| WorkerDown | Critical | Connect worker offline | Check Connect cluster |

---

## Disaster Recovery

### Backup Strategy
1. **Kafka Data:** Replicated across 3 brokers (no single point of failure)
2. **Schema History:** Backed up to Azure Blob Storage daily
3. **Connector Configs:** Version controlled in Git
4. **Prometheus Data:** 7-day retention, non-critical (historical only)

### Recovery Scenarios

| Scenario | RTO | RPO | Procedure |
|----------|-----|-----|-----------|
| Single broker failure | 0 min | 0 | Auto-recovery (Kafka handles) |
| Connect worker failure | 0 min | 0 | Auto-recovery (K8s recreates) |
| Connector failure | 5 min | ~0 | Redeploy connector |
| AKS cluster failure | 30 min | <5 min | Restore from backups |
| SQL Server failover | 0 min | 0 | Geo-replica auto-failover |

---

## Deployment Timeline

```
Week 1: Planning & Infrastructure
├─ Day 1-2: Requirements gathering
├─ Day 3-4: Infrastructure provisioning
└─ Day 5:   Network configuration

Week 2: Platform Deployment
├─ Day 1:   Confluent operator install
├─ Day 2:   ZooKeeper & Kafka deployment
├─ Day 3:   Connect deployment
├─ Day 4:   SQL Server CDC setup
└─ Day 5:   Debezium connector deployment

Week 3: Monitoring & Testing
├─ Day 1-2: Monitoring stack deployment
├─ Day 3:   Dashboard configuration
├─ Day 4:   Performance testing
└─ Day 5:   DR testing

Week 4: Production Hardening
├─ Day 1-2: Security hardening
├─ Day 3:   Documentation
├─ Day 4:   Team training
└─ Day 5:   Go-live preparation
```

**Total:** 4 weeks from start to production

---

## Cost Estimate (Monthly)

### Azure Costs
| Resource | Specification | Monthly Cost (USD) |
|----------|---------------|-------------------|
| AKS Cluster | 5 nodes (Standard_D8s_v3) | ~$1,400 |
| Azure SQL Database | Standard S2 | ~$150 |
| Storage (Managed Disks) | 1TB total | ~$100 |
| Load Balancer | 2 public IPs | ~$20 |
| Network egress | 100GB/month | ~$10 |
| **Total** | | **~$1,680** |

**Notes:**
- Costs vary by region
- Reserved instances can save 30-50%
- Development environment can use smaller instances

---

## Success Criteria

### Technical
- [ ] CDC latency < 1 second (p95)
- [ ] 99.9% uptime for Kafka cluster
- [ ] 99.9% uptime for Connect workers
- [ ] Zero data loss during normal operations
- [ ] All alerts configured and tested

### Operational
- [ ] Team trained on operations
- [ ] Runbooks documented
- [ ] DR procedures tested
- [ ] Monitoring dashboards operational
- [ ] On-call rotation established

---

## Contact & Resources

**Project Documentation:**
- Architecture: `PRODUCTION-ARCHITECTURE-OVERVIEW.md`
- Setup Guide: `setup-document.md`
- Quick Reference: `PRODUCTION-SETUP-QUICK-REFERENCE.md`
- Monitoring: `monitoring/MONITORING-SETUP.md`

**Support:**
- Debezium: https://debezium.io/documentation/
- Confluent: https://docs.confluent.io/
- Community: Slack, Stack Overflow

---

**Document Version:** 1.0  
**Last Updated:** 2026-06-22  
**Architecture Status:** Production-Ready
