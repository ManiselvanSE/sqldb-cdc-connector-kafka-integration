# Debezium CDC - Live Demo Runbook

Complete step-by-step guide for demonstrating the Debezium CDC pipeline from Azure SQL Server to Kafka.

---

## 📋 Pre-Demo Checklist

### Before the Demo (15 minutes before)

- [ ] **Verify all services are running**
  ```bash
  kubectl get pods -n confluent
  kubectl get pods -n monitoring
  ```

- [ ] **Check connector status**
  ```bash
  kubectl get connector -n confluent
  kubectl describe connector sqlserver-debezium-connector -n confluent
  ```

- [ ] **Open required browser tabs**
  - Grafana: `http://<GRAFANA_IP>:3000`
  - Prometheus: `http://<PROMETHEUS_IP>:9090`
  - Terminal windows (at least 2)

- [ ] **Test database connection**
  ```bash
  # Test connectivity to SQL Server
  sqlcmd -S yourserver.database.windows.net -U username -P password -Q "SELECT @@VERSION"
  ```

- [ ] **Have sample data ready**
  - Prepare INSERT/UPDATE/DELETE statements
  - Have customer data examples

---

## 🎬 Demo Flow (30 minutes)

### Part 1: Architecture Overview (5 minutes)

**Show the architecture diagram and explain:**

```
Azure SQL Server (Primary)
        │
        │ Geo-Replication
        ▼
Azure SQL Server (Secondary/Read Replica)
        │
        │ CDC Read
        ▼
Debezium Connector (Kafka Connect)
        │
        │ Stream Events
        ▼
Kafka Topics
        │
        │ Consume
        ▼
Downstream Applications
```

**Key Points to Mention:**
- Change Data Capture enabled on SQL Server
- Reading from read replica to avoid production impact
- Real-time streaming with <1 second latency
- All changes (INSERT, UPDATE, DELETE) captured
- High availability with 3 Kafka brokers

---

### Part 2: Show Running Infrastructure (5 minutes)

#### Terminal 1: Check Kubernetes Resources

```bash
# Show all Confluent components
echo "=== Confluent Platform Components ==="
kubectl get pods -n confluent

# Show connector status
echo -e "\n=== Debezium Connector ==="
kubectl get connector -n confluent

# Show Kafka topics
echo -e "\n=== CDC Topics in Kafka ==="
kubectl exec kafka-0 -n confluent -- kafka-topics \
  --bootstrap-server kafka:9071 --list | grep sqlserver
```

**Expected Output:**
- 3 Kafka pods running
- 1 Connect pod running  
- 1 Connector showing RUNNING
- Multiple CDC topics (one per table)

#### Terminal 2: Check Monitoring Stack

```bash
# Show monitoring components
echo "=== Monitoring Stack ==="
kubectl get pods -n monitoring

# Check Prometheus targets
echo -e "\n=== Prometheus Scrape Targets ==="
kubectl exec prometheus-0 -n monitoring -- \
  wget -q -O- http://localhost:9090/api/v1/targets 2>/dev/null | \
  grep -o '"job":"[^"]*"' | sort -u
```

**Expected Output:**
- Prometheus pod running
- Grafana pod running
- Kafka and Connect targets being scraped

---

### Part 3: Show Grafana Dashboard (5 minutes)

**Browser: Open Grafana**

1. Navigate to `http://<GRAFANA_IP>:3000`
2. Login (credentials should already be saved)
3. Open "Debezium SQL Server CDC Overview" dashboard

**Walk Through Dashboard Panels:**

**Panel 1: Active Connectors**
- Show: Number of active connectors
- Explain: "We have 1 connector running"

**Panel 2: Database Connection Status**
- Show: Connected = 1 (green)
- Explain: "Debezium is connected to SQL Server and reading CDC data"

**Panel 3: CDC Throughput**
- Show: Records per second graph
- Explain: "Real-time view of change events flowing through the pipeline"

**Panel 4: Committed Transactions**
- Show: Total transactions processed
- Explain: "Every database transaction captured and streamed to Kafka"

**Panel 5: Replication Lag**
- Show: Milliseconds behind source
- Explain: "Typically under 1 second - near real-time replication"

**Panel 6: Error Metrics**
- Show: Should be 0 errors
- Explain: "Monitoring for any failures in the pipeline"

---

### Part 4: Live Data Change Demo (10 minutes)

This is the **main demo** showing real-time CDC in action.

#### Setup: Open 3 Terminal Windows

**Terminal 1: Continuous Consumer (run this first)**
```bash
# Start consuming from Customers topic in real-time
kubectl exec -it kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka:9071 \
  --topic sqlserver.dbo.Customers \
  --from-beginning

# Leave this running to see events appear in real-time
```

**Terminal 2: Database Operations**
```bash
# Connect to SQL Server
sqlcmd -S yourserver.database.windows.net \
  -U username -P password \
  -d YourDatabase
```

**Terminal 3: Metrics Monitoring**
```bash
# Watch connector metrics in real-time
watch -n 2 'kubectl exec connect-0 -n confluent -- \
  curl -s localhost:7778/metrics | \
  grep "debezium_sql_server_connector_metrics_numberofcommittedtransactions"'
```

#### Demo Script: Execute These in Order

**1. INSERT Demo**

In Terminal 2 (SQL):
```sql
-- Insert a new customer
INSERT INTO dbo.Customers (first_name, last_name, email, phone)
VALUES ('Demo', 'User', 'demo@example.com', '+1-555-0100');
GO
```

**Point to Terminal 1** - Watch the event appear within 1-2 seconds!

**Explain the CDC Event Structure:**
```json
{
  "before": null,
  "after": {
    "customer_id": 1001,
    "first_name": "Demo",
    "last_name": "User",
    "email": "demo@example.com",
    "phone": "+1-555-0100",
    "created_at": 1719069600000
  },
  "op": "c",  // "c" = CREATE (INSERT)
  "ts_ms": 1719069600123
}
```

**2. UPDATE Demo**

In Terminal 2 (SQL):
```sql
-- Update the customer
UPDATE dbo.Customers
SET phone = '+1-555-9999'
WHERE email = 'demo@example.com';
GO
```

**Point to Terminal 1** - Another event appears!

**Explain:**
- `before`: Shows old values
- `after`: Shows new values  
- `op`: "u" = UPDATE
- Can see exactly what changed

**3. DELETE Demo**

In Terminal 2 (SQL):
```sql
-- Delete the customer
DELETE FROM dbo.Customers
WHERE email = 'demo@example.com';
GO
```

**Point to Terminal 1** - Delete event appears!

**Explain:**
- `before`: Shows the deleted record
- `after`: null
- `op`: "d" = DELETE
- Tombstone event for log compaction

**4. Batch Operations Demo**

In Terminal 2 (SQL):
```sql
-- Insert multiple records at once
INSERT INTO dbo.Customers (first_name, last_name, email, phone)
VALUES 
  ('Alice', 'Smith', 'alice@example.com', '+1-555-0201'),
  ('Bob', 'Jones', 'bob@example.com', '+1-555-0202'),
  ('Carol', 'White', 'carol@example.com', '+1-555-0203');
GO
```

**Point to Terminal 1** - All 3 events stream through!

**Switch to Terminal 3** - Show transaction count increasing!

**Switch to Grafana** - Show throughput spike in real-time graph!

---

### Part 5: Monitoring & Alerting (3 minutes)

**Browser: Switch to Prometheus**

Navigate to `http://<PROMETHEUS_IP>:9090/alerts`

**Show Configured Alerts:**

1. **DebeziumConnectorDown**
   - Explain: "Fires if connector stops running"
   - Show query: `kafka_connect_connect_worker_metrics_connector_count == 0`

2. **DebeziumHighLag**
   - Explain: "Fires if we fall behind by >10,000 records"
   - Show query: Lag metric threshold

3. **DebeziumTaskFailed**
   - Explain: "Fires if connector task fails"

**Navigate to Prometheus Targets:**
`http://<PROMETHEUS_IP>:9090/targets`

**Show:**
- Kafka brokers being scraped
- Connect workers being scraped
- All targets showing "UP" status

---

### Part 6: Query Real Data (2 minutes)

**Show how consumers can query the data:**

```bash
# Get the latest record from Customers topic
kubectl exec kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka:9071 \
  --topic sqlserver.dbo.Customers \
  --max-messages 1 \
  --from-beginning | jq '.'
```

**Show the full event structure with pretty formatting**

**Explain possible use cases:**
- Real-time analytics
- Data synchronization to data warehouse
- Event-driven microservices
- Audit logging
- Cache invalidation
- Search index updates

---

## 🎯 Key Demo Talking Points

### Technical Highlights

1. **Near Real-Time**
   - Sub-second latency from database to Kafka
   - Show actual lag metrics in Grafana

2. **Capture Everything**
   - INSERT, UPDATE, DELETE operations
   - Before and after values for updates
   - Transaction metadata (timestamp, LSN)

3. **High Availability**
   - 3 Kafka brokers with replication factor 3
   - No single point of failure
   - Automatic failover

4. **Production Ready**
   - Complete monitoring with Prometheus/Grafana
   - Pre-configured alerts
   - Scalable architecture

5. **Minimal Impact**
   - Reading from secondary replica
   - Asynchronous CDC capture
   - No triggers or application changes needed

### Business Value

1. **Real-Time Insights**
   - Data available for analytics immediately
   - No batch processing delays

2. **Data Consistency**
   - Single source of truth (SQL Server)
   - Guaranteed capture of all changes

3. **Flexibility**
   - Multiple consumers can read the same stream
   - Easy to add new downstream systems

4. **Reliability**
   - Full observability and monitoring
   - Automated alerting on issues

---

## 🔧 Troubleshooting During Demo

### If Connector Shows FAILED

```bash
# Check connector logs
kubectl logs connect-0 -n confluent | grep -i error | tail -20

# Restart connector
kubectl delete connector sqlserver-debezium-connector -n confluent
kubectl apply -f deployment/sqlserver-connector.yaml

# Wait 30 seconds and check again
kubectl get connector -n confluent
```

### If No Events Appear in Kafka

```bash
# Verify CDC is enabled on table
sqlcmd -S yourserver.database.windows.net -Q \
  "SELECT name, is_tracked_by_cdc FROM sys.tables WHERE name = 'Customers'"

# Check if CDC capture job is running
sqlcmd -Q "EXEC sys.sp_cdc_help_jobs"

# Verify connector is reading from correct server
kubectl describe connector sqlserver-debezium-connector -n confluent | grep hostname
```

### If Grafana Dashboard Shows No Data

```bash
# Check Prometheus is scraping metrics
kubectl exec prometheus-0 -n monitoring -- \
  wget -q -O- http://localhost:9090/api/v1/targets

# Verify JMX exporter is running on Connect
kubectl exec connect-0 -n confluent -- \
  curl -s localhost:7778/metrics | grep kafka_connect | head -5
```

---

## 📊 Demo Data Examples

### Sample INSERT Statements

```sql
-- Individual customer
INSERT INTO dbo.Customers (first_name, last_name, email, phone)
VALUES ('John', 'Doe', 'john.doe@example.com', '+1-555-1234');

-- Batch insert
INSERT INTO dbo.Customers (first_name, last_name, email, phone)
VALUES 
  ('Emily', 'Brown', 'emily.brown@example.com', '+1-555-2001'),
  ('Michael', 'Davis', 'michael.davis@example.com', '+1-555-2002'),
  ('Sarah', 'Wilson', 'sarah.wilson@example.com', '+1-555-2003'),
  ('David', 'Taylor', 'david.taylor@example.com', '+1-555-2004');
```

### Sample UPDATE Statements

```sql
-- Update single field
UPDATE dbo.Customers
SET phone = '+1-555-9999'
WHERE email = 'john.doe@example.com';

-- Update multiple fields
UPDATE dbo.Customers
SET 
  first_name = 'Johnny',
  phone = '+1-555-8888'
WHERE email = 'john.doe@example.com';
```

### Sample DELETE Statements

```sql
-- Delete single record
DELETE FROM dbo.Customers
WHERE email = 'john.doe@example.com';

-- Delete multiple records
DELETE FROM dbo.Customers
WHERE email LIKE '%@example.com';
```

---

## 🎤 Demo Script Template

**Opening (1 minute):**
> "Today I'll demonstrate our real-time Change Data Capture pipeline that streams changes from Azure SQL Server to Apache Kafka using Debezium. This gives us sub-second latency for data replication without any impact to our production database."

**Architecture (3 minutes):**
> "Let me show you the architecture. We're reading CDC data from an Azure SQL Server read replica, processing it through Debezium connector running on Kafka Connect, and streaming it to Kafka topics. We have complete monitoring with Prometheus and Grafana."

**Live Demo (15 minutes):**
> "Now for the exciting part - let's make some changes in the database and watch them flow through in real-time. I'll insert a new customer record... and there it is in Kafka within a second! Notice the event structure includes the operation type, timestamp, and all field values."

**Monitoring (5 minutes):**
> "Here's our Grafana dashboard showing real-time metrics. You can see throughput, lag, connection status, and error rates. We also have automated alerts configured in Prometheus that will notify us immediately if anything goes wrong."

**Q&A (6 minutes):**
> "Let me show you how this integrates with downstream systems... Any questions about the architecture, performance, or implementation?"

---

## ✅ Post-Demo Checklist

- [ ] Stop all running consumer terminals (Ctrl+C)
- [ ] Close SQL connection
- [ ] Clean up demo data if needed
  ```sql
  DELETE FROM dbo.Customers WHERE email LIKE '%@example.com';
  ```
- [ ] Check for any errors in connector
  ```bash
  kubectl logs connect-0 -n confluent | grep -i error
  ```
- [ ] Verify connector is still running
  ```bash
  kubectl get connector -n confluent
  ```

---

## 📝 Demo Variations

### Short Demo (10 minutes)
1. Show architecture (2 min)
2. Show Grafana dashboard (3 min)
3. One INSERT operation (3 min)
4. Q&A (2 min)

### Technical Deep Dive (45 minutes)
1. Full architecture walkthrough (10 min)
2. Infrastructure setup explanation (10 min)
3. Live data operations (15 min)
4. Monitoring and troubleshooting (10 min)

### Executive Demo (15 minutes)
1. Business value overview (3 min)
2. Architecture overview (2 min)
3. Live demo - one operation (5 min)
4. ROI and benefits (3 min)
5. Q&A (2 min)

---

## 🔗 Additional Resources

- **Full Setup Guide:** See PRODUCTION-SETUP-SLIDES.md
- **Operations Guide:** See PRODUCTION-SETUP-QUICK-REFERENCE.md
- **Architecture Details:** See PRODUCTION-ARCHITECTURE-OVERVIEW.md
- **CLI Commands:** See CLI-COMMANDS.md
- **Scripts:** See scripts/ directory

---

**Demo Preparation Time:** 15 minutes  
**Demo Duration:** 30 minutes (adjustable)  
**Audience:** Technical teams, architects, management  

**Last Updated:** 2026-06-22
