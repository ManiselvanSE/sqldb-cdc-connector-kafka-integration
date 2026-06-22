# Architecture & Data Flow

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AZURE SQL SERVER                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌───────────────────────────┐         ┌──────────────────────────┐ │
│  │   PRIMARY SERVER          │         │   SECONDARY SERVER       │ │
│  │  primdbprimaryserver      │────────▶│  primdbsecondaryserver   │ │
│  │                           │  Geo-   │                          │ │
│  │  Database: primdb         │  Repli- │  Database: primdb        │ │
│  │  Mode: Read-Write         │  cation │  Mode: Read-Only         │ │
│  │  CDC: Enabled ✓           │ (5-30s) │  CDC: Replicated ✓       │ │
│  │                           │         │                          │ │
│  │  Tables:                  │         │  Tables:                 │ │
│  │  - dbo.Customers          │         │  - dbo.Customers         │ │
│  │  - dbo.Orders             │         │  - dbo.Orders            │ │
│  │  - dbo.Products           │         │  - dbo.Products          │ │
│  │                           │         │                          │ │
│  │  User: sqladmin           │         │  User: sqladmin          │ │
│  │  Pass: Confluent1234      │         │  Pass: Confluent1234     │ │
│  └───────────────────────────┘         └──────────────────────────┘ │
│                                                     │                 │
│                                                     │                 │
└─────────────────────────────────────────────────────┼─────────────────┘
                                                      │
                                                      │ TCP 1433
                                                      │ SSL/TLS
                                                      │ ApplicationIntent=ReadOnly
                                                      │
┌─────────────────────────────────────────────────────┼─────────────────┐
│                    KUBERNETES CLUSTER                │                 │
│                    (Confluent Platform)              │                 │
├──────────────────────────────────────────────────────┼─────────────────┤
│                                                      ▼                 │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │              KAFKA CONNECT (connect-0)                         │  │
│  │                                                                 │  │
│  │  ┌──────────────────────────────────────────────────────────┐ │  │
│  │  │   Debezium SQL Server Connector                          │ │  │
│  │  │   - Name: sqlserver-debezium-connector                   │ │  │
│  │  │   - Version: 3.5.0                                       │ │  │
│  │  │   - Tasks: 1                                             │ │  │
│  │  │   - Topic Prefix: azure-sqlserver                        │ │  │
│  │  └──────────────────────────────────────────────────────────┘ │  │
│  │                             │                                   │  │
│  └─────────────────────────────┼───────────────────────────────────┘  │
│                                │                                       │
│                                ▼                                       │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                    KAFKA CLUSTER                                │  │
│  │                    (3 brokers)                                  │  │
│  │                                                                 │  │
│  │  Brokers:                                                       │  │
│  │  - kafka-0 (20.235.46.215:9092)                               │  │
│  │  - kafka-1 (20.235.8.132:9092)                                │  │
│  │  - kafka-2 (20.235.177.55:9092)                               │  │
│  │                                                                 │  │
│  │  Topics Created:                                               │  │
│  │  ├─ azure-sqlserver                                           │  │
│  │  ├─ azure-sqlserver.dbo.Customers                             │  │
│  │  ├─ azure-sqlserver.dbo.Orders                                │  │
│  │  ├─ azure-sqlserver.dbo.Products                              │  │
│  │  └─ schema-changes.azure-sqlserver                            │  │
│  │                                                                 │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                │                                       │
│                                ▼                                       │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │              CONTROL CENTER                                     │  │
│  │              http://20.235.11.19:9021                          │  │
│  │              - Monitor connector                                │  │
│  │              - View topics & messages                           │  │
│  │              - Check metrics & health                           │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Sequence

### 1. Initial Snapshot (First Run)

```
Step 1: User deploys connector
   │
   ├─▶ Debezium connects to primdbsecondaryserver (read replica)
   │   - Uses ApplicationIntent=ReadOnly
   │   - SSL/TLS encrypted connection
   │
   ├─▶ Takes consistent snapshot of existing data
   │   - Reads all rows from CDC-enabled tables
   │   - Marks each record with "op": "r" (read)
   │
   └─▶ Publishes to Kafka topics
       - azure-sqlserver.dbo.Customers (5 messages)
       - azure-sqlserver.dbo.Orders (5 messages)
       - azure-sqlserver.dbo.Products (5 messages)
       
       Total: 15 initial messages

Timeline: 1-5 minutes
```

### 2. Streaming CDC Changes (Ongoing)

```
Step 1: User executes INSERT/UPDATE/DELETE on PRIMARY

    INSERT INTO dbo.Customers (...) VALUES (...);
    │
    │
    ▼

Step 2: Primary SQL Server CDC captures change

    Primary captures to CDC tables:
    - cdc.dbo_Customers_CT (change table)
    - Records operation type, LSN, timestamp
    │
    │ Geo-Replication (5-30 seconds)
    ▼

Step 3: Change replicates to SECONDARY (read replica)

    Secondary receives:
    - Table data changes
    - CDC metadata
    - LSN tracking
    │
    │ Debezium polling (1-5 seconds)
    ▼

Step 4: Debezium reads CDC changes from SECONDARY

    Connector queries CDC tables:
    - Reads changes since last LSN
    - Transforms to JSON format
    - Enriches with metadata
    │
    │
    ▼

Step 5: Publishes to Kafka

    Message format:
    {
      "before": { ... },        // Record before change (null for INSERT)
      "after": { ... },         // Record after change (null for DELETE)
      "op": "c",                // Operation: c=create, u=update, d=delete
      "ts_ms": 1719057000000,  // Timestamp
      "source": { ... }         // Source metadata (server, DB, table, LSN)
    }
    │
    │
    ▼

Step 6: Available for consumers

    Topic: azure-sqlserver.dbo.Customers
    Partition: 0
    Offset: auto-incremented
    
    Consumers can read immediately

Total Latency: 10-40 seconds (primary → Kafka)
```

---

## Network & Connection Details

### Azure SQL Server Connection

**Primary Server (for making changes):**
```
Endpoint: primdbprimaryserver.database.windows.net:1433
Database: primdb
Auth: SQL Authentication (sqladmin/Confluent1234)
SSL: Required
Purpose: User makes INSERT/UPDATE/DELETE here
```

**Secondary Server (Debezium connects here):**
```
Endpoint: primdbsecondaryserver.database.windows.net:1433
Database: primdb
Auth: SQL Authentication (sqladmin/Confluent1234)
SSL: Required
ApplicationIntent: ReadOnly (forces read replica)
Purpose: Debezium reads CDC changes from here
```

### Kubernetes Network

**Namespace:** confluent

**Connect Pod:**
```
Pod: connect-0
Container: connect
Port: 8083 (REST API)
Image: confluentinc/cp-server-connect:7.8.0
Plugins: debezium-connector-sqlserver:3.5.0
```

**Kafka Cluster:**
```
Internal Bootstrap: kafka:9071
External LB: 20.235.46.215:9092 (kafka-0)
Replication Factor: 3
Partitions per topic: 1 (default)
```

**Control Center:**
```
External LB: 20.235.11.19:9021
Protocol: HTTP
UI: Web-based monitoring
```

---

## Security Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     SECURITY LAYERS                             │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Network Security                                           │
│     ├─ Azure SQL Firewall Rules                               │
│     ├─ Allow Azure Services: Enabled                          │
│     └─ Client IP Allowlist                                    │
│                                                                 │
│  2. Transport Security                                         │
│     ├─ TLS 1.2 encryption (Azure SQL)                         │
│     ├─ Certificate validation                                 │
│     └─ Encrypted at rest (Azure SQL)                          │
│                                                                 │
│  3. Authentication                                             │
│     ├─ SQL Authentication (sqladmin)                          │
│     ├─ Password: Confluent1234                                │
│     └─ Read-only intent for replica                           │
│                                                                 │
│  4. Authorization                                              │
│     ├─ SELECT on dbo schema                                   │
│     ├─ SELECT on cdc schema                                   │
│     ├─ EXECUTE on cdc schema                                  │
│     └─ VIEW DATABASE STATE                                    │
│                                                                 │
│  5. Kubernetes RBAC                                            │
│     ├─ Namespace isolation (confluent)                        │
│     ├─ CRD-based access control                               │
│     └─ Pod security policies                                  │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

**Production Recommendations:**
1. **Credentials:** Move to Kubernetes Secrets or Azure Key Vault
2. **Network:** Use Private Link for Azure SQL
3. **Monitoring:** Enable Azure SQL threat detection
4. **Audit:** Enable CDC audit logging

---

## Message Format Examples

### INSERT Operation

```json
{
  "schema": { ... },
  "payload": {
    "before": null,
    "after": {
      "customer_id": 6,
      "first_name": "Sarah",
      "last_name": "Davis",
      "email": "sarah.davis@example.com",
      "phone": "+1-555-0106",
      "created_at": 1719057600000,
      "updated_at": 1719057600000
    },
    "source": {
      "version": "3.5.0.Final",
      "connector": "sqlserver",
      "name": "azure-sqlserver",
      "ts_ms": 1719057601234,
      "snapshot": "false",
      "db": "primdb",
      "sequence": null,
      "schema": "dbo",
      "table": "Customers",
      "change_lsn": "00000027:00000420:0001",
      "commit_lsn": "00000027:00000420:0002",
      "event_serial_no": 1
    },
    "op": "c",
    "ts_ms": 1719057601456,
    "transaction": null
  }
}
```

### UPDATE Operation

```json
{
  "payload": {
    "before": {
      "customer_id": 1,
      "email": "john.doe@example.com",
      ...
    },
    "after": {
      "customer_id": 1,
      "email": "john.doe.updated@example.com",
      ...
    },
    "op": "u",
    "ts_ms": 1719057602123
  }
}
```

### DELETE Operation

```json
{
  "payload": {
    "before": {
      "product_id": 6,
      "product_name": "Webcam HD",
      ...
    },
    "after": null,
    "op": "d",
    "ts_ms": 1719057603456
  }
}
```

---

## Performance Characteristics

### Throughput

| Metric | Expected Value | Notes |
|--------|---------------|-------|
| **Initial Snapshot** | 1,000-10,000 rows/sec | Depends on table size |
| **Streaming CDC** | 100-1,000 events/sec | Per connector task |
| **Network Latency** | 10-50 ms | Azure → Kubernetes |
| **Geo-Replication Lag** | 5-30 seconds | Azure managed |
| **Debezium Processing** | 1-5 seconds | Poll interval |
| **Total E2E Latency** | 10-40 seconds | Insert → Kafka |

### Resource Usage

**Connect Pod:**
- CPU: 1 core (can burst to 2)
- Memory: 2 GB (limit 4 GB)
- Disk: Minimal (logs only)

**Kafka Topics:**
- Partitions: 1 per topic (default)
- Replication: 3x (across brokers)
- Retention: 7 days (default)
- Compression: Producer-side (snappy)

---

## Monitoring Metrics

### Key Metrics to Track

1. **Connector Health**
   - State: RUNNING/FAILED/PAUSED
   - Task count: 1/1 running
   - Restart count: 0

2. **Throughput**
   - Messages produced/sec
   - Bytes produced/sec
   - Offset commit rate

3. **Latency**
   - Snapshot progress %
   - Streaming lag (ms)
   - Source-to-Kafka latency

4. **Errors**
   - Task failures
   - Connection errors
   - Serialization errors

### Access Metrics

**Control Center:**
```
http://20.235.11.19:9021
→ Connect → connect → sqlserver-debezium-connector
→ View metrics dashboard
```

**Kafka Connector API:**
```bash
kubectl exec -n confluent connect-0 -- \
  curl -s localhost:8083/connectors/sqlserver-debezium-connector/status
```

---

## Scaling Considerations

### Vertical Scaling (Single Connector)

**Increase throughput per connector:**
```yaml
configs:
  max.batch.size: "4096"          # Default: 2048
  max.queue.size: "16384"         # Default: 8192
  poll.interval.ms: "500"         # Default: 1000
  snapshot.fetch.size: "10240"    # Rows per batch
```

### Horizontal Scaling (Multiple Tasks)

**For multiple tables:**
```yaml
spec:
  taskMax: 3  # One task per table group
```

**Note:** SQL Server CDC has limitations on parallel reads

### Connect Cluster Scaling

**Increase Connect replicas:**
```yaml
spec:
  replicas: 3  # High availability
```

**Benefits:**
- Load distribution
- Fault tolerance
- Zero-downtime restarts

---

## High Availability Setup

```
┌─────────────────────────────────────────────────────────────┐
│              PRODUCTION HA ARCHITECTURE                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Azure SQL Server                                           │
│  ├─ Primary (Read-Write)                                    │
│  ├─ Secondary 1 (Read Replica - Debezium)                   │
│  └─ Secondary 2 (Read Replica - Failover)                   │
│                                                              │
│  Kafka Connect Cluster                                      │
│  ├─ connect-0 (Active)                                      │
│  ├─ connect-1 (Active)                                      │
│  └─ connect-2 (Active)                                      │
│     - Connector tasks distributed                           │
│     - Automatic failover                                    │
│                                                              │
│  Kafka Cluster                                              │
│  ├─ kafka-0 (Leader for some partitions)                    │
│  ├─ kafka-1 (Leader for some partitions)                    │
│  └─ kafka-2 (Leader for some partitions)                    │
│     - Replication factor: 3                                 │
│     - Min in-sync replicas: 2                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Disaster Recovery

### Connector Failure
**Detection:** Control Center shows FAILED state

**Recovery:**
```bash
# Restart connector
kubectl delete connector sqlserver-debezium-connector -n confluent
kubectl apply -f sqlserver-connector.yaml

# Connector resumes from last committed offset
```

### Database Failover
**Scenario:** Primary SQL Server fails

**Action:**
1. Azure automatically fails over to secondary
2. Update connector configuration to new secondary endpoint
3. Redeploy connector

### Kafka Broker Failure
**Automatic:** Kafka rebalances partitions to remaining brokers

**No action needed** (if replication factor ≥ 2)

---

## Cost Optimization

### Azure SQL Server
- Use read replica for Debezium (reduces load on primary)
- Enable CDC only on required tables
- Regular cleanup of CDC tables (retention policy)

### Kafka
- Tune topic retention (7 days vs 30 days)
- Enable compression (snappy/lz4)
- Right-size partition count

### Kubernetes
- Right-size Connect pod resources
- Use node affinity for better placement
- Enable cluster autoscaling

---

This architecture provides a robust, scalable CDC pipeline from Azure SQL Server to Kafka!
