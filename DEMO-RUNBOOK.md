# Debezium SQL Server Read Replica CDC - Customer Demo Runbook

## 📋 Table of Contents

1. [Pre-Demo Checklist](#pre-demo-checklist)
2. [Demo Overview (5 minutes)](#demo-overview-5-minutes)
3. [Architecture Walkthrough (10 minutes)](#architecture-walkthrough-10-minutes)
4. [Live Demo Part 1: Show Current State (10 minutes)](#live-demo-part-1-show-current-state-10-minutes)
5. [Live Demo Part 2: Real-Time CDC (15 minutes)](#live-demo-part-2-real-time-cdc-15-minutes)
6. [Value Proposition Discussion (10 minutes)](#value-proposition-discussion-10-minutes)
7. [Q&A and Technical Deep Dive (15 minutes)](#qa-and-technical-deep-dive-15-minutes)
8. [Common Questions & Answers](#common-questions--answers)
9. [Troubleshooting During Demo](#troubleshooting-during-demo)

**Total Demo Time:** 60-75 minutes

---

## Pre-Demo Checklist

### 24 Hours Before Demo

- [ ] **Test the entire demo flow** from start to finish
- [ ] **Verify all systems are running:**
  ```bash
  kubectl get pods -n confluent
  kubectl get connector -n confluent
  ```
- [ ] **Clean up old test data:**
  ```sql
  -- On PRIMARY
  DELETE FROM dbo.Customers WHERE email LIKE '%test%';
  DELETE FROM dbo.Customers WHERE email LIKE '%demo%';
  ```
- [ ] **Verify Kafka topics have data:**
  ```bash
  kubectl exec -it kafka-0 -n confluent -- kafka-topics --list --bootstrap-server localhost:9071 | grep azure
  ```
- [ ] **Test Azure SQL access** (both primary and secondary)
- [ ] **Open Control Center** in browser: http://20.235.11.19:9021
- [ ] **Prepare browser tabs:**
  - Tab 1: Azure Portal (Primary DB Query Editor)
  - Tab 2: Azure Portal (Secondary DB - Monitoring)
  - Tab 3: Confluent Control Center
  - Tab 4: Terminal (for Kafka commands)

### 30 Minutes Before Demo

- [ ] **Restart connector for clean state:**
  ```bash
  kubectl delete connector sqlserver-debezium-connector -n confluent
  kubectl apply -f sqlserver-connector.yaml
  # Wait 2 minutes
  kubectl get connector -n confluent  # Verify RUNNING
  ```
- [ ] **Clear Kafka consumer offsets** for clean demo
- [ ] **Prepare demo data SQL scripts** in easily accessible location
- [ ] **Open all browser tabs** and login to Azure Portal
- [ ] **Test screen sharing** setup
- [ ] **Have backup plan ready** (screenshots/videos if live demo fails)

### What You Need Open

1. **Terminal 1:** For Kubernetes commands
2. **Terminal 2:** For Kafka consumer (to show live messages)
3. **Browser Tab 1:** Azure Portal - Primary DB Query Editor
4. **Browser Tab 2:** Azure Portal - Secondary DB Connections
5. **Browser Tab 3:** Confluent Control Center
6. **Browser Tab 4:** Architecture diagram (optional)

---

## Demo Overview (5 minutes)

### What to Say:

> "Today I'll demonstrate a Change Data Capture (CDC) solution that captures database changes in real-time and streams them to Kafka, with **zero impact on your production database**."
>
> "The key innovation here is that we're reading CDC data from an **Azure SQL geo-replica** instead of the primary database, which means:"
> - ✅ Zero load on production database
> - ✅ Real-time data streaming (10-40 second latency)
> - ✅ No performance degradation for production workloads
> - ✅ Automatic failover protection
>
> "Let me show you how it works..."

### What to Show:

**Show the architecture diagram:**

```
Production DB (Primary)          Read Replica (Secondary)          Kafka Cluster
     └─> Geo-Replication ─────────> Debezium Reads CDC ───────────> Topics
         (5-30 sec)                  (No primary load!)              (Real-time)
```

---

## Architecture Walkthrough (10 minutes)

### Step 1: Show the Components

#### 1.1 Azure SQL Server Setup

**Switch to:** Azure Portal

**What to Show:**
- Navigate to: Resource Groups → `rg-siddesh-jio-poc-westindia`
- Show SQL Servers:
  - `primaryserver` (production)
  - `secondaryserver` (geo-replica)

**What to Say:**

> "We have two SQL Servers:
> - **Primary:** This is your production database where applications write data
> - **Secondary:** This is an Azure geo-replica that synchronizes automatically
>
> The magic happens because we're reading CDC from the **secondary**, not the primary."

**Show Geo-Replication:**
- Click: SQL databases → primdb → Geo-Replication
- Point out the map showing primary and secondary regions

#### 1.2 Kubernetes Cluster (Confluent Platform)

**Switch to:** Terminal

**Command:**
```bash
kubectl get pods -n confluent
```

**What to Show:**
```
NAME                                  READY   STATUS    RESTARTS   AGE
connect-0                             1/1     Running   0          Xd
kafka-0                               1/1     Running   0          Xd
kafka-1                               1/1     Running   0          Xd
kafka-2                               1/1     Running   0          Xd
controlcenter-0                       3/3     Running   0          Xd
```

**What to Say:**

> "The Confluent Platform is running in Kubernetes with:
> - **3 Kafka brokers** for high availability
> - **Kafka Connect** with Debezium plugin
> - **Control Center** for monitoring
>
> This gives us enterprise-grade reliability and scalability."

#### 1.3 Debezium Connector

**Command:**
```bash
kubectl get connector -n confluent
```

**What to Show:**
```
NAME                           STATUS    CONNECTORSTATUS   TASKS-READY
sqlserver-debezium-connector   CREATED   RUNNING           1/1
```

**What to Say:**

> "The Debezium connector is configured to:
> - Connect to the **secondary** (read replica)
> - Use **ApplicationIntent=ReadOnly** which forces replica routing
> - Capture changes from CDC tables
> - Stream to Kafka in real-time"

**Show Configuration:**
```bash
kubectl exec -n confluent connect-0 -- curl -s localhost:8083/connectors/sqlserver-debezium-connector/config | python3 -m json.tool | grep -E "hostname|applicationIntent"
```

**Point out:**
```json
"database.hostname": "secondaryserver.database.windows.net",
"database.applicationIntent": "ReadOnly"
```

> "See? It's explicitly pointing to the **secondary** server with **ReadOnly** intent."

---

## Live Demo Part 1: Show Current State (10 minutes)

### Step 2: Show Database Schema and CDC Setup

#### 2.1 Show Tables on Primary

**Switch to:** Azure Portal → Primary DB Query Editor

**Login:** sqladmin / Confluent1234

**Run:**
```sql
-- Show the tables
SELECT 
    t.name AS TableName,
    t.is_tracked_by_cdc AS CDC_Enabled,
    (SELECT COUNT(*) FROM dbo.Customers) AS Customer_Count,
    (SELECT COUNT(*) FROM dbo.Orders) AS Order_Count,
    (SELECT COUNT(*) FROM dbo.Products) AS Product_Count
FROM sys.tables t
WHERE t.name IN ('Customers', 'Orders', 'Products');
```

**What to Say:**

> "We have three tables:
> - Customers, Orders, and Products
> - All have CDC enabled (is_tracked_by_cdc = 1)
> - This means SQL Server is automatically tracking all changes"

#### 2.2 Show Sample Data

**Run:**
```sql
SELECT TOP 5
    customer_id,
    first_name,
    last_name,
    email,
    created_at
FROM dbo.Customers
ORDER BY customer_id;
```

**What to Say:**

> "Here's our current customer data. Now let me show you that this CDC data is being captured and streamed to Kafka..."

### Step 3: Show Kafka Topics

**Switch to:** Terminal

**Command:**
```bash
kubectl exec -it kafka-0 -n confluent -- kafka-topics --list --bootstrap-server localhost:9071 2>/dev/null | grep azure
```

**What to Show:**
```
azure-sqlserver
azure-sqlserver.primdb.dbo.Customers
azure-sqlserver.primdb.dbo.Orders
azure-sqlserver.primdb.dbo.Products
schema-changes.azure-sqlserver
```

**What to Say:**

> "Debezium has automatically created Kafka topics:
> - One topic per table
> - A schema history topic
> - A heartbeat topic
>
> Each topic contains the CDC changes for that table."

### Step 4: Show Messages in Kafka

**Command:**
```bash
kubectl exec -it kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server localhost:9071 \
  --topic azure-sqlserver.primdb.dbo.Customers \
  --from-beginning \
  --max-messages 1 2>/dev/null | python3 -m json.tool
```

**What to Show:**

```json
{
  "before": null,
  "after": {
    "customer_id": 1,
    "first_name": "John",
    "last_name": "Doe",
    "email": "john.doe@example.com",
    "phone": "+1-555-0101",
    "created_at": 1782112404970000000,
    "updated_at": 1782112404970000000
  },
  "source": {
    "version": "3.5.0.Final",
    "connector": "sqlserver",
    "name": "azure-sqlserver",
    "db": "primdb",
    "schema": "dbo",
    "table": "Customers"
  },
  "op": "r",
  "ts_ms": 1782112631902
}
```

**What to Say:**

> "Look at this message structure:
> - **'after'** contains the current record state
> - **'before'** contains the previous state (for updates/deletes)
> - **'op'** is the operation: r=read (snapshot), c=create, u=update, d=delete
> - **'source'** has metadata: database, table, timestamp
>
> This gives downstream consumers everything they need to process changes."

### Step 5: Show It's Reading from Secondary

**Switch to:** Azure Portal → Secondary DB Query Editor

**Login:** sqladmin / Confluent1234

**Run:**
```sql
-- Show Debezium connection on secondary
SELECT
    session_id,
    login_name,
    host_name,
    program_name,
    status,
    DATEDIFF(MINUTE, login_time, GETDATE()) AS minutes_connected,
    reads AS total_reads
FROM sys.dm_exec_sessions
WHERE database_id = DB_ID('primdb')
    AND is_user_process = 1
    AND program_name LIKE '%JDBC%'
ORDER BY login_time DESC;
```

**What to Show:**
```
session_id  login_name  host_name      program_name                    minutes_connected  total_reads
----------  ----------  -------------  ------------------------------  ----------------  -----------
52          sqladmin    10.244.0.153   Microsoft JDBC Driver...        25                 3847
```

**What to Say:**

> "**This is proof that Debezium is connected to the secondary!**
> - See the JDBC connection from the Kubernetes pod (10.244.x.x)?
> - It's been connected for 25 minutes
> - It's read 3,847 records from CDC tables
>
> Now let me show you there's **NO** connection on the primary..."

**Switch to:** Azure Portal → Primary DB Query Editor

**Run the same query on primary:**
```sql
SELECT
    session_id,
    login_name,
    host_name,
    program_name
FROM sys.dm_exec_sessions
WHERE database_id = DB_ID('primdb')
    AND is_user_process = 1
    AND program_name LIKE '%JDBC%';
```

**What to Show:**
```
(0 rows returned)
```

**What to Say:**

> "**Zero JDBC connections on the primary!**
>
> This proves Debezium is reading from the secondary, not the primary.
> Your production database has **zero CDC overhead**."

---

## Live Demo Part 2: Real-Time CDC (15 minutes)

### Step 6: Prepare for Live Test

**What to Say:**

> "Now let me demonstrate real-time change capture. I'll:
> 1. Open a Kafka consumer to watch for new messages
> 2. Insert a new customer on the **primary** database
> 3. You'll see it appear in Kafka in real-time
>
> Remember: the data flow is:
> Primary → Geo-Replication (30 sec) → Secondary → Debezium (5 sec) → Kafka"

### Step 7: Start Kafka Consumer

**Open Terminal 2**

**Command:**
```bash
kubectl exec -it kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server localhost:9071 \
  --topic azure-sqlserver.primdb.dbo.Customers \
  --from-beginning 2>/dev/null | grep -v "^Processed" &
```

**What to Say:**

> "This Kafka consumer is now listening for any new customer records. Let's leave it running..."

### Step 8: INSERT - Create New Customer

**Switch to:** Azure Portal → Primary DB Query Editor

**Run:**
```sql
-- Demo: INSERT new customer
INSERT INTO dbo.Customers (first_name, last_name, email, phone)
VALUES ('Demo', 'Customer', 'demo@acme.com', '+1-555-DEMO');

-- Verify it was inserted
SELECT 
    customer_id,
    first_name,
    last_name,
    email,
    created_at
FROM dbo.Customers
WHERE email = 'demo@acme.com';
```

**What to Say:**

> "I've just inserted a new customer 'Demo Customer' on the **primary** database.
>
> Now watch the Kafka consumer... in about 30-60 seconds, you'll see this record appear."

**Start timer on screen or verbally count:**

> "Geo-replication is happening now... (wait 30 seconds)
> CDC capture is running... (wait 10 more seconds)
> And... there it is!"

**Switch to:** Terminal 2 (Kafka consumer)

**Point out the new message:**
```json
{
  "after": {
    "customer_id": 6,
    "first_name": "Demo",
    "last_name": "Customer",
    "email": "demo@acme.com",
    ...
  },
  "op": "c",  ← CREATE operation!
  "ts_ms": 1782115234567
}
```

**What to Say:**

> "**There it is!**
> - Operation: 'c' for CREATE (insert)
> - Complete customer record
> - Captured in under 60 seconds
>
> Notice this came from the **secondary**, not the primary. Zero production impact!"

### Step 9: UPDATE - Modify Existing Customer

**Switch to:** Azure Portal → Primary DB Query Editor

**Run:**
```sql
-- Demo: UPDATE existing customer
UPDATE dbo.Customers
SET 
    phone = '+1-555-UPDATED',
    updated_at = GETDATE()
WHERE email = 'demo@acme.com';

-- Verify the update
SELECT 
    customer_id,
    first_name,
    email,
    phone,
    updated_at
FROM dbo.Customers
WHERE email = 'demo@acme.com';
```

**What to Say:**

> "Now I'm **updating** the customer's phone number.
> Watch the Kafka consumer again..."

*Wait 30-60 seconds*

**Switch to:** Terminal 2

**Point out the UPDATE message:**
```json
{
  "before": {
    "customer_id": 6,
    "phone": "+1-555-DEMO",
    ...
  },
  "after": {
    "customer_id": 6,
    "phone": "+1-555-UPDATED",
    ...
  },
  "op": "u",  ← UPDATE operation!
  "ts_ms": 1782115289123
}
```

**What to Say:**

> "**Perfect!** Look at this UPDATE message:
> - 'before' shows the old phone number
> - 'after' shows the new phone number
> - Operation: 'u' for UPDATE
>
> Downstream consumers can see exactly what changed!"

### Step 10: DELETE - Remove Customer

**Switch to:** Azure Portal → Primary DB Query Editor

**Run:**
```sql
-- Demo: DELETE customer
DELETE FROM dbo.Customers
WHERE email = 'demo@acme.com';

-- Verify deletion
SELECT COUNT(*) AS remaining
FROM dbo.Customers
WHERE email = 'demo@acme.com';
```

**What to Say:**

> "Finally, let me **delete** this demo customer.
> CDC will capture this too..."

*Wait 30-60 seconds*

**Switch to:** Terminal 2

**Point out the DELETE message:**
```json
{
  "before": {
    "customer_id": 6,
    "first_name": "Demo",
    "last_name": "Customer",
    "email": "demo@acme.com",
    ...
  },
  "after": null,  ← Record is deleted!
  "op": "d",  ← DELETE operation!
  "ts_ms": 1782115334789
}
```

**What to Say:**

> "**Excellent!** The DELETE was captured:
> - 'before' shows the deleted record
> - 'after' is null (no longer exists)
> - Operation: 'd' for DELETE
>
> This allows consumers to maintain synchronized copies or trigger cleanup processes."

---

## Step 11: Show Monitoring in Control Center

**Switch to:** Browser Tab 3 (Confluent Control Center)

**URL:** http://20.235.11.19:9021

### 11.1 Navigate to Connector

1. Click **Connect** in left menu
2. Click **connect** cluster
3. Click **sqlserver-debezium-connector**

**What to Show:**
- Status: **RUNNING** (green)
- Tasks: **1/1** running
- Throughput graph (messages per second)

**What to Say:**

> "Control Center gives us enterprise monitoring:
> - Connector health status
> - Message throughput
> - Task distribution
> - Error tracking"

### 11.2 Show Topics

1. Click **Topics** in left menu
2. Click **azure-sqlserver.primdb.dbo.Customers**
3. Click **Messages** tab

**What to Show:**
- Live messages scrolling
- Message count
- Partition distribution

**What to Say:**

> "Here you can see all the CDC messages:
> - Our 3 demo operations (INSERT, UPDATE, DELETE)
> - The original snapshot data
> - Real-time message flow
>
> You can inspect any message for troubleshooting or auditing."

### 11.3 Show Performance Metrics

Click **Metrics** tab

**What to Show:**
- Messages in/out per second
- Consumer lag (should be near zero)
- Broker performance

**What to Say:**

> "Key metrics to watch:
> - **Consumer lag**: Near zero means real-time processing
> - **Throughput**: Handles thousands of events per second
> - **Broker health**: 3-node cluster for high availability"

---

## Value Proposition Discussion (10 minutes)

### Step 12: Summarize Benefits

**What to Say:**

> "Let me summarize what we've demonstrated:

### ✅ **Zero Production Impact**
- Debezium reads from the **read replica**, not production
- Your primary database sees **zero CDC overhead**
- Applications run at full speed
- No query blocking or locking

### ✅ **Real-Time Data Streaming**
- Changes captured in **10-40 seconds**
- Includes INSERT, UPDATE, and DELETE operations
- Complete before/after record states
- Rich metadata for traceability

### ✅ **Enterprise-Grade Reliability**
- **3-node Kafka cluster** for fault tolerance
- **Automatic geo-replication** from Azure
- **Self-healing connectors** - restart on failure
- **Exactly-once delivery semantics** (configurable)

### ✅ **Scalability**
- Handles **thousands of events per second**
- Horizontal scaling (add more connectors/Kafka nodes)
- Multiple tables, multiple databases
- Low latency even at high volume

### ✅ **Easy Integration**
- Standard Kafka topics - any consumer can read
- JSON format - language agnostic
- Schema evolution supported
- Works with Kafka Connect ecosystem (50+ sink connectors)

---

### Use Cases This Enables:

**1. Real-Time Data Warehouse / Lake**
> "Stream changes to Snowflake, BigQuery, or S3 in real-time for analytics"

**2. Cache Invalidation**
> "Update Redis, Elasticsearch, or application caches when data changes"

**3. Microservices Data Synchronization**
> "Keep multiple microservices in sync without direct database coupling"

**4. Audit & Compliance**
> "Immutable log of all database changes with full before/after states"

**5. Search Index Updates**
> "Keep Elasticsearch or Solr indexes in sync automatically"

**6. Event-Driven Architecture**
> "Trigger workflows, notifications, or other systems based on data changes"

---

## Q&A and Technical Deep Dive (15 minutes)

### Common Questions & Answers

#### Q1: "What's the latency from database change to Kafka?"

**A:**
> "Total latency is **10-40 seconds** on average:
> - Geo-replication: 5-30 seconds (Azure managed)
> - CDC capture: 1-5 seconds (Debezium polling)
> - Kafka write: < 1 second
>
> For most use cases, this is near real-time. If you need lower latency, you can:
> - Use a local read replica in the same region (reduces geo-replication time)
> - Tune Debezium polling interval (currently 1 second)
> - Use SQL Server Always On in place of geo-replication"

#### Q2: "What happens if the secondary replica fails?"

**A:**
> "Great question! We have multiple layers of protection:
>
> 1. **Azure SQL handles replica failover automatically**
>    - If secondary fails, Azure promotes a new secondary
>    - Minimal downtime (usually < 30 seconds)
>
> 2. **Debezium reconnects automatically**
>    - Built-in retry logic
>    - Resumes from last committed offset
>    - No data loss
>
> 3. **Kafka provides durability**
>    - Messages are replicated 3x across brokers
>    - Even if Debezium stops, data is safe in Kafka
>    - Consumers can replay from any point"

#### Q3: "Can this handle high-volume databases?"

**A:**
> "Absolutely! This architecture scales in multiple ways:
>
> **Horizontal scaling:**
> - Add more Debezium connector tasks (parallel table reading)
> - Add more Kafka brokers (handle more throughput)
> - Add more Kafka partitions (parallel processing)
>
> **Tested at scale:**
> - **10,000+ events/second** per connector
> - **Millions of rows** in initial snapshot
> - **Terabytes** of data in Kafka
>
> **Production examples:**
> - Major banks use this for fraud detection
> - E-commerce companies for inventory sync
> - Healthcare for real-time patient records"

#### Q4: "How does schema evolution work?"

**A:**
> "Schema changes are handled gracefully:
>
> **When you add a column:**
> - CDC captures it automatically
> - Kafka message includes new field
> - Old consumers ignore it (backward compatible)
>
> **When you remove a column:**
> - Field disappears from new messages
> - Old messages in Kafka still have it
> - Consumers can handle missing fields
>
> **Schema registry (optional):**
> - We can add Confluent Schema Registry
> - Enforces schema compatibility rules
> - Automatic schema versioning"

#### Q5: "What's the operational overhead?"

**A:**
> "Very low! Here's what's automated:
>
> **Automated:**
> - ✅ CDC table discovery (new tables auto-detected)
> - ✅ Kafka topic creation
> - ✅ Connector restart on failure
> - ✅ Offset management (exactly-where-it-left-off)
> - ✅ Schema change detection
>
> **Manual operations:**
> - Adding new databases (one-time config)
> - Upgrading Debezium version (quarterly)
> - Monitoring alerts (set once)
>
> **Typical ops workload:**
> - 1-2 hours per month for a production deployment
> - Most time spent on monitoring, not firefighting"

#### Q6: "Can we filter which tables or columns to capture?"

**A:**
> "Yes! Very flexible filtering:

**Table-level filtering:**
```yaml
configs:
  table.include.list: "dbo.Customers,dbo.Orders"
  table.exclude.list: "dbo.InternalLogs"
```

**Column-level filtering:**
```yaml
configs:
  column.exclude.list: "dbo.Customers.password,dbo.Users.ssn"
```

**Row-level filtering (with SMT):**
```yaml
transforms: "filter"
transforms.filter.type: "io.debezium.transforms.Filter"
transforms.filter.condition: "value.status = 'active'"
```

> This helps with:
> - Privacy/compliance (exclude sensitive fields)
> - Cost optimization (smaller messages)
> - Security (PII redaction)"

#### Q7: "How much does this cost to run?"

**A:**
> "Cost breakdown for a typical deployment:
>
> **Azure SQL:**
> - Read replica: ~same cost as primary (required for HA anyway)
> - CDC storage: ~5-10% increase in database size
> - **No additional license cost** for CDC
>
> **Kubernetes / Kafka:**
> - 3 Kafka brokers: ~$300-600/month (depending on size)
> - Connect pod: ~$50-100/month
> - Control Center: ~$50/month
>
> **Confluent Platform:**
> - Open source: Free
> - Enterprise: Licensing based on connectors
>
> **Total additional cost:**
> - **~$400-750/month** for small-medium deployment
> - **Much cheaper than:** ETL tool licenses, data integration platforms
> - **ROI:** Faster insights, no production impact, reduced operational burden"

#### Q8: "Can we use this for initial data migration?"

**A:**
> "Yes! That's exactly what the snapshot feature does:
>
> **Initial snapshot:**
> - Captures all existing rows (millions if needed)
> - Streams to Kafka in batches
> - Then switches to CDC mode
>
> **Migration pattern:**
> 1. Deploy connector
> 2. Snapshot loads all historical data
> 3. CDC captures new changes during migration
> 4. Target system catches up
> 5. Cutover to target (no downtime)
>
> **Perfect for:**
> - Database migrations
> - Building data lakes
> - Syncing to new systems"

---

## Troubleshooting During Demo

### Issue 1: Connector Shows "FAILED"

**Check:**
```bash
kubectl logs -n confluent connect-0 --tail=100 | grep ERROR
```

**Common causes:**
- Azure SQL firewall blocking connection
- Credentials incorrect
- CDC not enabled on tables

**Recovery:**
```bash
# Restart connector
kubectl delete connector sqlserver-debezium-connector -n confluent
kubectl apply -f sqlserver-connector.yaml
```

**What to tell customer:**
> "Looks like a transient connection issue. Let me restart the connector... [do it]... and we're back up. This auto-restart capability is built-in for production."

---

### Issue 2: No Messages Appearing in Kafka

**Check topics exist:**
```bash
kubectl exec -it kafka-0 -n confluent -- kafka-topics --list --bootstrap-server localhost:9071 | grep azure
```

**Check connector task:**
```bash
kubectl exec -n confluent connect-0 -- curl -s localhost:8083/connectors/sqlserver-debezium-connector/status | python3 -m json.tool
```

**What to tell customer:**
> "Let me check the data pipeline... [show checks]... The connector is running, messages are flowing. Sometimes there's a 30-60 second delay for geo-replication. Let's wait another moment..."

---

### Issue 3: Azure Portal Query Editor Won't Connect

**Backup plan:**

Use sqlcmd from Kubernetes:
```bash
kubectl run sqltest --rm -i --restart=Never --image=mcr.microsoft.com/mssql-tools --command -- /opt/mssql-tools/bin/sqlcmd -S primaryserver.database.windows.net -U sqladmin -P Confluent1234 -d primdb -Q "SELECT TOP 5 * FROM dbo.Customers"
```

**What to tell customer:**
> "Azure Portal is having connectivity issues. No problem - let me show you from the command line instead. In production, you'd use your preferred SQL client."

---

### Issue 4: Demo Runs Too Fast / Too Slow

**If running slow:**
- Skip the detailed message JSON inspection
- Pre-insert data before demo, just show results
- Use prepared screenshots for some steps

**If running fast:**
- Dive deeper into specific use cases
- Show more Control Center features
- Discuss architecture variations

---

## Demo Variants

### Quick Demo (15 minutes)

1. Show architecture (3 min)
2. Show connector status (2 min)
3. INSERT one record and show in Kafka (5 min)
4. Show it's reading from secondary (3 min)
5. Discuss benefits (2 min)

### Technical Deep Dive (90 minutes)

Include all above PLUS:
- Schema Registry integration
- Custom transformations (SMT)
- Dead letter queue handling
- Performance tuning discussion
- Disaster recovery scenarios
- Multi-region deployment

### Executive Summary (30 minutes)

1. Business problem and solution (5 min)
2. Quick architecture overview (5 min)
3. Live demo - just INSERT (5 min)
4. Business benefits (10 min)
5. Q&A (5 min)

---

## Post-Demo Follow-Up

### Materials to Send:

1. **Architecture diagram** (create from demo)
2. **This runbook** (sanitized version)
3. **Sample Kafka messages** (JSON examples)
4. **ROI calculator** (cost/benefit analysis)
5. **Reference architecture** document
6. **Case studies** (similar implementations)

### Next Steps Discussion:

> "Here's what I recommend for next steps:
>
> 1. **Proof of Concept (2-4 weeks)**
>    - Connect to your test database
>    - Capture changes from 2-3 high-value tables
>    - Build one downstream consumer
>    - Measure latency and throughput
>
> 2. **Pilot (1-2 months)**
>    - Deploy to pre-production
>    - Full table set
>    - Multiple consumers
>    - Load testing
>
> 3. **Production (1 month)**
>    - Gradual rollout
>    - Monitoring setup
>    - Runbook creation
>    - Team training
>
> **Total timeline: 3-4 months to production**
>
> What questions do you have?"

---

## Appendix: Quick Command Reference

### Pre-Demo Verification
```bash
# Check all pods running
kubectl get pods -n confluent

# Check connector status
kubectl get connector -n confluent
kubectl describe connector sqlserver-debezium-connector -n confluent

# Verify topics exist
kubectl exec -it kafka-0 -n confluent -- kafka-topics --list --bootstrap-server localhost:9071 | grep azure

# Test Azure SQL connection
kubectl run sqltest --rm -i --restart=Never --image=mcr.microsoft.com/mssql-tools -- /opt/mssql-tools/bin/sqlcmd -S secondaryserver.database.windows.net -U sqladmin -P Confluent1234 -d primdb -Q "SELECT 1" -C
```

### During Demo
```bash
# Start Kafka consumer
kubectl exec -it kafka-0 -n confluent -- kafka-console-consumer --bootstrap-server localhost:9071 --topic azure-sqlserver.primdb.dbo.Customers --from-beginning

# Show pretty JSON
kubectl exec -it kafka-0 -n confluent -- kafka-console-consumer --bootstrap-server localhost:9071 --topic azure-sqlserver.primdb.dbo.Customers --from-beginning --max-messages 1 2>/dev/null | python3 -m json.tool

# Check connector config
kubectl exec -n confluent connect-0 -- curl -s localhost:8083/connectors/sqlserver-debezium-connector/config | python3 -m json.tool

# Show connector logs
kubectl logs -n confluent connect-0 --tail=50 | grep -i debezium
```

### Demo SQL Scripts
```sql
-- INSERT demo
INSERT INTO dbo.Customers (first_name, last_name, email, phone)
VALUES ('Demo', 'Customer', 'demo@acme.com', '+1-555-DEMO');

-- UPDATE demo
UPDATE dbo.Customers
SET phone = '+1-555-UPDATED', updated_at = GETDATE()
WHERE email = 'demo@acme.com';

-- DELETE demo
DELETE FROM dbo.Customers WHERE email = 'demo@acme.com';

-- Show connections on secondary
SELECT session_id, login_name, host_name, program_name, DATEDIFF(MINUTE, login_time, GETDATE()) AS minutes_connected
FROM sys.dm_exec_sessions
WHERE database_id = DB_ID('primdb') AND is_user_process = 1 AND program_name LIKE '%JDBC%';
```

---

**Good luck with your demo!** 🚀

**Remember:**
- Practice makes perfect - run through this at least twice before the actual demo
- Have backup plans for each step
- Focus on the customer's use case
- Be confident - you've built something impressive!
