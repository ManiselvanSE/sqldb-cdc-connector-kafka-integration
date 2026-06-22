# SQL Server Failover & High Availability Guide
## Debezium CDC with Always On Availability Groups

Complete guide for configuring, testing, and managing Debezium CDC connector with SQL Server Always On Availability Groups (AG), including automatic failover handling.

---

## 📋 Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Always On Availability Groups Setup](#always-on-availability-groups-setup)
3. [Debezium Connector Configuration](#debezium-connector-configuration)
4. [How Failover Works](#how-failover-works)
5. [Testing Runbook](#testing-runbook)
6. [DBA Considerations](#dba-considerations)
7. [Monitoring & Verification](#monitoring--verification)
8. [Troubleshooting](#troubleshooting)

---

## 🏗️ Architecture Overview

### Standard Setup (Without AG)

```
┌─────────────────────────────────────────┐
│         SQL Server Primary              │
│                                         │
│  ┌────────────────────────────────┐    │
│  │   Database (Read-Write)        │    │
│  │   CDC Enabled                  │    │
│  └────────────────────────────────┘    │
│                │                        │
└────────────────┼────────────────────────┘
                 │
                 │ Debezium Reads CDC
                 ▼
      ┌─────────────────────┐
      │  Debezium Connector │
      └─────────────────────┘
```

**Issues:**
- ❌ Single point of failure
- ❌ Downtime during maintenance
- ❌ No automatic recovery

---

### High Availability Setup (With AG + Listener)

```
┌──────────────────────────────────────────────────────────────────────┐
│                    ALWAYS ON AVAILABILITY GROUP                      │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                    AG LISTENER (Virtual)                       │ │
│  │         listener-name.database.windows.net:1433                │ │
│  │                                                                │ │
│  │  • Single DNS name for clients                                │ │
│  │  • Automatic routing to current primary                       │ │
│  │  • ApplicationIntent=ReadOnly → Routes to secondary           │ │
│  └──────────────┬─────────────────────────┬─────────────────────┘ │
│                 │                         │                        │
│                 ▼                         ▼                        │
│  ┌──────────────────────┐    ┌──────────────────────┐            │
│  │   PRIMARY REPLICA    │    │  SECONDARY REPLICA   │            │
│  │  (Read-Write)        │───▶│   (Read-Only)        │            │
│  │                      │    │                      │            │
│  │  • Synchronous sync  │    │  • Real-time sync    │            │
│  │  • Auto-failover     │    │  • Can become primary│            │
│  │  • CDC enabled       │◀───│  • CDC replicated    │            │
│  └──────────────────────┘    └──────────────────────┘            │
│         ACTIVE                      STANDBY                        │
│                                                                    │
└────────────────────────────┬───────────────────────────────────────┘
                             │
                             │ Single Connection String
                             │ + ApplicationIntent=ReadOnly
                             ▼
                  ┌─────────────────────┐
                  │ Debezium Connector  │
                  │                     │
                  │ Connection:         │
                  │ - Host: AG Listener │
                  │ - Intent: ReadOnly  │
                  │                     │
                  │ Automatic Routing:  │
                  │ → Reads from        │
                  │   Secondary Replica │
                  └─────────────────────┘
                             │
                             ▼
                     ┌──────────────┐
                     │ Kafka Topics │
                     └──────────────┘
```

**Benefits:**
- ✅ Automatic failover (typically 10-30 seconds)
- ✅ No connection string changes needed
- ✅ Read from secondary (reduced primary load)
- ✅ Zero data loss with synchronous replication
- ✅ Seamless Debezium reconnection

---

## 📊 Failover Scenarios

### Scenario 1: Planned Failover (Maintenance)

**Timeline:**
```
Time    Primary         Secondary       AG Listener    Debezium
------  --------------  --------------  -------------  -----------------
T+0     ACTIVE          STANDBY         → Primary     Reading from 
        (Read-Write)    (Read-Only)                   Secondary

T+10s   Syncing final   Receiving       → Primary     Connection still
        transactions    updates                       alive

T+15s   Becomes         Becomes         Switching     TCP keepalive
        SECONDARY       PRIMARY         → Secondary   detecting change

T+20s   STANDBY         ACTIVE          → Secondary   Connection closed
        (Read-Only)     (Read-Write)                  by SQL Server

T+25s   Ready           Processing      → Secondary   Debezium retries
                        writes                        connection

T+30s   Accepting       Fully ready     → Secondary   Connected to new
        reads                                         secondary (old primary)

T+35s   -               -               -             CDC resumed, 
                                                      no data loss
```

**Key Points:**
- Total downtime: ~15-30 seconds
- Debezium automatically reconnects
- No manual intervention required
- Zero data loss (synchronous mode)

---

### Scenario 2: Automatic Failover (Server Failure)

**Timeline:**
```
Time    Event                           Debezium Status
------  ------------------------------  ---------------------------
T+0     Primary server crashes          Reading from Secondary

T+5s    AG detects primary failure      Still connected to Secondary
        (health checks timeout)         Reading CDC normally

T+10s   AG initiates failover           Connection remains active
        Secondary promoted to Primary    

T+15s   AG Listener updates routing     ApplicationIntent=ReadOnly
        (DNS/connection redirects)      now returns "no replica available"

T+20s   Old Secondary (now Primary)     Connection terminated
        stops accepting readonly        by SQL Server

T+25s   Debezium connection fails       Connector enters retry loop
        (ApplicationIntent conflict)    

T+30s   DBA updates connector config    OR wait for new Secondary
        (remove ApplicationIntent)      to come online

T+35s   Debezium reconnects to          CDC resumes
        new Primary (read-write)        
```

**Options After Failover:**

**Option A: Wait for New Secondary (Recommended)**
- Old primary recovers and joins as secondary
- Debezium reconnects to new secondary
- No config change needed
- Typical recovery: 2-10 minutes

**Option B: Read from New Primary (Immediate)**
- Update connector: Remove `ApplicationIntent=ReadOnly`
- Debezium reads from primary
- Impact on production load
- Switch back when secondary available

---

## 🔧 Always On Availability Groups Setup

### Prerequisites

**SQL Server Requirements:**
- SQL Server 2016 Enterprise Edition or higher
- OR Azure SQL Managed Instance (AG built-in)
- Windows Server Failover Cluster (WSFC) OR Azure managed

**Database Configuration:**
- Full recovery model (mandatory)
- Regular transaction log backups
- CDC enabled on primary (automatically replicates)

---

### Step 1: Enable Always On Availability Groups

**On Primary Server:**
```sql
-- Enable Always On AG (requires restart)
-- Run in SQL Server Configuration Manager or PowerShell

-- PowerShell (run as Administrator)
Enable-SqlAlwaysOn -ServerInstance 'SERVER1' -Force

-- Restart SQL Server service
Restart-Service -Name MSSQLSERVER
```

**On Secondary Server:**
```sql
-- Enable Always On AG (requires restart)
Enable-SqlAlwaysOn -ServerInstance 'SERVER2' -Force
Restart-Service -Name MSSQLSERVER
```

---

### Step 2: Create Availability Group

**On Primary Server:**
```sql
-- 1. Backup database
BACKUP DATABASE YourDatabase 
TO DISK = 'C:\Backup\YourDatabase.bak' 
WITH COMPRESSION, INIT;

BACKUP LOG YourDatabase 
TO DISK = 'C:\Backup\YourDatabase_log.trn';

-- 2. Create AG endpoint (if not exists)
CREATE ENDPOINT Hadr_endpoint
    STATE = STARTED
    AS TCP (LISTENER_PORT = 5022)
    FOR DATABASE_MIRRORING (
        ROLE = ALL,
        AUTHENTICATION = WINDOWS NEGOTIATE,
        ENCRYPTION = REQUIRED ALGORITHM AES
    );

-- 3. Create Availability Group
CREATE AVAILABILITY GROUP AG_YourDatabase
WITH (
    AUTOMATED_BACKUP_PREFERENCE = SECONDARY,
    FAILURE_CONDITION_LEVEL = 3,
    HEALTH_CHECK_TIMEOUT = 30000
)
FOR DATABASE YourDatabase
REPLICA ON 
    'SERVER1' WITH (
        ENDPOINT_URL = 'TCP://server1.domain.com:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = AUTOMATIC,
        SECONDARY_ROLE(ALLOW_CONNECTIONS = ALL)  -- Important for CDC reads
    ),
    'SERVER2' WITH (
        ENDPOINT_URL = 'TCP://server2.domain.com:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = AUTOMATIC,
        SECONDARY_ROLE(ALLOW_CONNECTIONS = ALL)  -- Important for CDC reads
    );
```

**On Secondary Server:**
```sql
-- 1. Restore database (NO RECOVERY mode)
RESTORE DATABASE YourDatabase 
FROM DISK = '\\NetworkPath\YourDatabase.bak' 
WITH NORECOVERY;

RESTORE LOG YourDatabase 
FROM DISK = '\\NetworkPath\YourDatabase_log.trn' 
WITH NORECOVERY;

-- 2. Join AG
ALTER AVAILABILITY GROUP AG_YourDatabase JOIN;

-- 3. Join database to AG
ALTER DATABASE YourDatabase SET HADR AVAILABILITY GROUP = AG_YourDatabase;
```

---

### Step 3: Create AG Listener

**On Primary Server:**
```sql
-- Create listener (virtual network name)
ALTER AVAILABILITY GROUP AG_YourDatabase
ADD LISTENER 'AG_Listener_YourDB' (
    WITH IP (
        ('10.0.1.100', '255.255.255.0')  -- Adjust for your network
    ),
    PORT = 1433
);
```

**For Azure SQL Managed Instance:**
```
-- Listener is automatically created
-- Format: ag-name.zone-id.database.windows.net
```

---

### Step 4: Enable CDC on Primary

```sql
-- Connect to PRIMARY replica
USE YourDatabase;

-- Enable CDC on database
EXEC sys.sp_cdc_enable_db;

-- Enable CDC on tables
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'Customers',
    @role_name = NULL,
    @supports_net_changes = 1;

-- Verify CDC is enabled
SELECT name, is_cdc_enabled 
FROM sys.databases 
WHERE name = 'YourDatabase';

-- CDC automatically replicates to secondary replicas
```

---

### Step 5: Verify AG Configuration

```sql
-- Check AG status
SELECT 
    ag.name AS AG_Name,
    ar.replica_server_name,
    ar.availability_mode_desc,
    ar.failover_mode_desc,
    ars.role_desc,
    ars.synchronization_health_desc,
    ars.connected_state_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar 
    ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars 
    ON ar.replica_id = ars.replica_id;

-- Expected output:
-- SERVER1: PRIMARY, SYNCHRONIZED, CONNECTED
-- SERVER2: SECONDARY, SYNCHRONIZED, CONNECTED

-- Check listener
SELECT 
    listener_name = dns_name,
    port,
    ip_configuration_string_from_cluster AS ip_address
FROM sys.availability_group_listeners;
```

---

## 🔌 Debezium Connector Configuration

### Configuration for AG Listener

**deployment/sqlserver-connector.yaml**
```yaml
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
    # Use AG LISTENER instead of direct server name
    database.hostname: "AG_Listener_YourDB.domain.com"
    # OR for Azure: "your-ag-listener.zone.database.windows.net"
    
    database.port: "1433"
    database.user: "debezium_user"
    database.password: "your_password"
    database.names: "YourDatabase"
    
    # CRITICAL: Route to readable secondary
    database.applicationIntent: "ReadOnly"
    
    # CRITICAL: Enable multiSubnetFailover for faster failover detection
    database.multiSubnetFailover: "true"
    
    # Connection timeout and retry settings
    database.connectTimeout: "30000"           # 30 seconds
    database.socketTimeout: "0"                # No socket timeout
    
    # SSL/TLS
    database.encrypt: "true"
    database.trustServerCertificate: "false"
    
    # Debezium retry configuration
    errors.retry.delay.initial.ms: "1000"      # 1 second
    errors.retry.delay.max.ms: "60000"         # 60 seconds
    errors.retry.timeout: "300000"             # 5 minutes total retry
    
    # Snapshot configuration
    snapshot.mode: "initial"
    snapshot.isolation.mode: "snapshot"
    
    # Schema history
    schema.history.internal.kafka.bootstrap.servers: "kafka:9071"
    schema.history.internal.kafka.topic: "schema-changes.sqlserver"
    
    # Topic prefix
    topic.prefix: "sqlserver"
```

---

### Key Configuration Parameters for Failover

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `database.hostname` | AG Listener name | Single endpoint, automatic routing |
| `database.applicationIntent` | `ReadOnly` | Route to secondary replica |
| `database.multiSubnetFailover` | `true` | Faster failover detection (5-10s vs 30s+) |
| `database.connectTimeout` | `30000` | Initial connection timeout |
| `errors.retry.timeout` | `300000` | Keep retrying for 5 minutes during failover |

---

### Connection String Comparison

**❌ BAD: Direct Server Connection**
```yaml
database.hostname: "server1.domain.com"
# Issues:
# - Hardcoded to one server
# - Manual config change needed during failover
# - Downtime until manual update
```

**✅ GOOD: AG Listener Connection**
```yaml
database.hostname: "AG_Listener_YourDB.domain.com"
database.applicationIntent: "ReadOnly"
database.multiSubnetFailover: "true"
# Benefits:
# - Automatic routing to current secondary
# - No config changes during failover
# - Faster failover detection
```

---

## 🔄 How Failover Works

### Normal Operation (Before Failover)

```
1. Debezium connects to: AG_Listener_YourDB.domain.com
2. AG Listener receives: ApplicationIntent=ReadOnly
3. AG Listener routes to: Current SECONDARY replica (Server2)
4. Debezium reads CDC: From Server2 (secondary)
5. Data flow:
   Primary (Server1) → Secondary (Server2) → Debezium → Kafka
```

---

### During Planned Failover

**Step-by-Step Process:**

**1. DBA Initiates Failover (T+0)**
```sql
-- On primary (Server1)
ALTER AVAILABILITY GROUP AG_YourDatabase FAILOVER;
```

**2. AG Begins Synchronization (T+0 to T+10s)**
- Primary (Server1) stops accepting writes
- Final transactions sync to Secondary (Server2)
- Both replicas fully synchronized

**3. Roles Switch (T+10s to T+15s)**
- Server1: PRIMARY → SECONDARY
- Server2: SECONDARY → PRIMARY
- AG Listener updates internal routing

**4. Debezium Connection Handling (T+15s to T+30s)**
```
T+15s: Debezium still connected to old secondary (Server1)
T+20s: Server1 (now secondary) remains available for reads
T+25s: Debezium continues reading CDC from Server1
T+30s: Seamless operation, zero downtime
```

**5. Result**
- ✅ Debezium experienced ZERO downtime
- ✅ No configuration changes needed
- ✅ No data loss
- ✅ CDC reading continues from new secondary (Server1)

---

### During Automatic Failover (Server Crash)

**Step-by-Step Process:**

**1. Primary Server Crashes (T+0)**
```
Server1 (PRIMARY): ❌ CRASHED
Server2 (SECONDARY): ✅ RUNNING
Debezium: Still reading from Server2 ✅
```

**2. AG Detects Failure (T+0 to T+10s)**
- AG health checks fail (default: 30s timeout, can be tuned)
- WSFC cluster detects node failure
- AG initiates automatic failover

**3. Secondary Promoted to Primary (T+10s)**
```sql
-- Automatic promotion (no manual intervention)
Server2: SECONDARY → PRIMARY (ACTIVE, Read-Write)
```

**4. AG Listener Updates (T+15s)**
- Listener routing updated
- Primary endpoint: Server2
- Secondary endpoint: NONE (until Server1 recovers)

**5. Debezium Connection Impact (T+20s to T+30s)**

**Scenario A: ApplicationIntent=ReadOnly** (Current Config)
```
T+20s: Server2 (primary) rejects ReadOnly connections
       "No readable secondary replica available"
T+25s: Debezium connection fails
T+30s: Debezium enters retry loop
```

**Actions Required:**

**Option 1: Wait for Server1 to Recover (Recommended)**
```bash
# Monitor AG status
kubectl logs connect-0 -n confluent -f | grep -i error

# Wait for Server1 to rejoin as secondary (usually 2-10 minutes)
# Debezium will automatically reconnect when secondary is available
```

**Option 2: Temporarily Read from Primary**
```yaml
# Update connector config
kubectl edit connector sqlserver-debezium-connector -n confluent

# Change:
database.applicationIntent: "ReadOnly"
# To:
# database.applicationIntent: "ReadWrite"  # Or remove the line

# Connector will reconnect to primary
# Switch back when Server1 recovers as secondary
```

---

### Server Recovery Timeline

**Server1 Rejoins as Secondary:**

```
Time    Server1         Server2         Debezium
------  --------------  --------------  -----------------
T+0     ❌ CRASHED      PRIMARY         Connection failed,
                                        retrying

T+2m    Booting up      PRIMARY         Still retrying

T+5m    Starting SQL    PRIMARY         Still retrying
        Server          

T+7m    Joining AG      PRIMARY         Still retrying
        as SECONDARY    

T+8m    Syncing data    PRIMARY         Still retrying
        from Server2    

T+9m    ✅ READY        PRIMARY         Detects secondary
        (SECONDARY)                     available

T+10m   Accepting       PRIMARY         ✅ CONNECTED
        read requests                   Reading from Server1
                                       CDC resumed
```

---

## 📝 Testing Runbook

### Test 1: Planned Failover Test

**Objective:** Verify seamless failover with zero data loss

**Prerequisites:**
- [ ] AG properly configured and synchronized
- [ ] Debezium connector running and healthy
- [ ] Grafana dashboard open for monitoring
- [ ] Two terminal windows ready

---

#### Test 1 Procedure

**Terminal 1: Monitor Kafka Consumer**
```bash
# Start consuming CDC events in real-time
kubectl exec -it kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka:9071 \
  --topic sqlserver.dbo.Customers \
  --from-beginning
```

**Terminal 2: Monitor Connector**
```bash
# Watch connector status
watch -n 2 'kubectl get connector -n confluent && echo "" && \
  kubectl logs connect-0 -n confluent --tail=5 | grep -i "error\|connected"'
```

**Step 1: Verify Current State (Before Failover)**
```sql
-- On primary replica
SELECT 
    ag.name AS AG_Name,
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_health_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
ORDER BY ars.role_desc DESC;

-- Expected output:
-- Server1: PRIMARY, HEALTHY
-- Server2: SECONDARY, HEALTHY
```

**Step 2: Insert Test Data (Before Failover)**
```sql
-- On primary replica
INSERT INTO dbo.Customers (first_name, last_name, email, phone)
VALUES ('PreFailover', 'Test1', 'pre-failover-1@test.com', '+1-555-0001');

-- Verify in Kafka (Terminal 1)
-- Should see event within 1-2 seconds
```

**Step 3: Initiate Planned Failover**
```sql
-- On primary replica (Server1)
ALTER AVAILABILITY GROUP AG_YourDatabase FAILOVER;
```

**Step 4: Monitor Failover Progress**
```bash
# Watch connector logs (Terminal 2)
# Should see NO errors, connection remains active

# Check Grafana dashboard
# - Database Connection: Should stay green (1)
# - Throughput: May dip slightly for 5-10 seconds
# - Errors: Should remain 0
```

**Step 5: Verify New Primary**
```sql
-- Run on both servers to check roles
SELECT 
    @@SERVERNAME AS CurrentServer,
    ar.replica_server_name,
    ars.role_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars 
    ON ar.replica_id = ars.replica_id
WHERE ars.is_local = 1;

-- Expected output:
-- Server1: SECONDARY (switched from PRIMARY)
-- Server2: PRIMARY (switched from SECONDARY)
```

**Step 6: Insert Test Data (After Failover)**
```sql
-- On NEW primary replica (Server2)
INSERT INTO dbo.Customers (first_name, last_name, email, phone)
VALUES ('PostFailover', 'Test2', 'post-failover-2@test.com', '+1-555-0002');

-- Verify in Kafka (Terminal 1)
-- Should see event within 1-2 seconds
```

**Step 7: Verify Debezium is Reading from New Secondary**
```bash
# Check which server Debezium is connected to
kubectl exec connect-0 -n confluent -- curl -s localhost:7778/metrics | \
  grep "debezium_sql_server_connector_metrics_connected"

# Should show: connected=1

# On old primary (Server1), check connections
sqlcmd -S server1.domain.com -Q \
  "SELECT session_id, login_name, host_name, program_name 
   FROM sys.dm_exec_sessions 
   WHERE login_name = 'debezium_user' AND program_name LIKE '%Debezium%'"

-- Should see active connection from Debezium
```

**Expected Results:**
- ✅ Zero data loss (both test records in Kafka)
- ✅ Zero downtime for Debezium
- ✅ Automatic reconnection (no manual intervention)
- ✅ Connector reading from new secondary (old primary)
- ✅ Events continue flowing to Kafka

**Cleanup:**
```sql
-- Delete test records
DELETE FROM dbo.Customers 
WHERE email IN ('pre-failover-1@test.com', 'post-failover-2@test.com');
```

---

### Test 2: Automatic Failover (Simulated Server Crash)

**Objective:** Test behavior during unplanned failover

**⚠️ WARNING:** This test will simulate a server crash. Only perform in non-production!

---

#### Test 2 Procedure

**Step 1: Verify Current State**
```sql
-- Same as Test 1, Step 1
```

**Step 2: Start Monitoring (Same terminals as Test 1)**

**Step 3: Insert Test Data Stream**
```sql
-- On primary, start inserting records every 5 seconds
DECLARE @i INT = 1;
WHILE @i <= 20
BEGIN
    INSERT INTO dbo.Customers (first_name, last_name, email, phone)
    VALUES (
        'AutoFailover',
        'Test' + CAST(@i AS VARCHAR),
        'auto-failover-' + CAST(@i AS VARCHAR) + '@test.com',
        '+1-555-' + RIGHT('0000' + CAST(@i AS VARCHAR), 4)
    );
    
    WAITFOR DELAY '00:00:05';  -- 5 second delay
    SET @i = @i + 1;
END
```

**Step 4: Simulate Server Crash (During inserts)**
```powershell
# Method 1: Stop SQL Server service (cleaner)
Stop-Service -Name MSSQLSERVER -Force

# Method 2: Shutdown server (more realistic)
Stop-Computer -Force

# Method 3: Network disconnect (test network partition)
Disable-NetAdapter -Name "Ethernet" -Confirm:$false
```

**Step 5: Monitor Failover (Timing)**
```bash
# Terminal 2: Watch for errors and reconnection
# Note timestamps:
# - When connection fails
# - When AG promotes secondary
# - When Debezium reconnects
```

**Step 6: Verify Data Consistency**
```sql
-- After failover completes, count test records
SELECT COUNT(*) AS records_received
FROM dbo.Customers
WHERE email LIKE 'auto-failover-%@test.com';

-- Compare with Kafka
kubectl exec kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka:9071 \
  --topic sqlserver.dbo.Customers \
  --from-beginning | \
  grep "auto-failover" | wc -l

-- Counts should match (may need to wait for final events)
```

**Step 7: Bring Server1 Back Online**
```powershell
# Start SQL Server service
Start-Service -Name MSSQLSERVER

# Or restart server
Restart-Computer

# Or re-enable network
Enable-NetAdapter -Name "Ethernet"
```

**Step 8: Monitor Server1 Rejoining**
```sql
-- On Server2 (current primary), monitor sync status
SELECT 
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_health_desc,
    ars.connected_state_desc,
    drs.synchronization_state_desc,
    drs.log_send_queue_size,
    drs.log_send_rate
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id;

-- Wait for:
-- Server1: SECONDARY, SYNCHRONIZED, CONNECTED
```

**Step 9: Verify Debezium Reconnects to Server1**
```bash
# Wait for "ApplicationIntent=ReadOnly" to route to new secondary (Server1)
# Check connector logs for successful reconnection

kubectl logs connect-0 -n confluent --tail=50 | grep -i "connected\|established"
```

**Expected Results:**
- ✅ Automatic failover within 30 seconds
- ✅ All pre-crash events in Kafka
- ✅ Debezium reconnects when secondary available
- ✅ No manual intervention required
- ⚠️ Brief CDC gap (events during transition may be delayed)

**Cleanup:**
```sql
DELETE FROM dbo.Customers WHERE email LIKE 'auto-failover-%@test.com';
```

---

### Test 3: Multi-Subnet Failover Performance

**Objective:** Verify multiSubnetFailover setting improves failover speed

**Test A: With multiSubnetFailover=true (Current)**
```yaml
database.multiSubnetFailover: "true"
```

**Test B: With multiSubnetFailover=false**
```yaml
database.multiSubnetFailover: "false"
```

**Procedure:**
1. Run Test 1 with setting = true
2. Note failover detection time
3. Update connector, set to false
4. Run Test 1 again
5. Compare detection times

**Expected Results:**
- With `true`: 5-10 second failover detection
- With `false`: 20-30 second failover detection

**Recommendation:** Always use `multiSubnetFailover: true`

---

## 👨‍💼 DBA Considerations

### Pre-Deployment Checklist

**Infrastructure:**
- [ ] Windows Server Failover Cluster configured (or Azure managed)
- [ ] Quorum witness configured (file share or cloud witness)
- [ ] Network connectivity between replicas (port 5022)
- [ ] Shared storage or separate disks per node
- [ ] Sufficient disk space on all replicas

**SQL Server:**
- [ ] Enterprise Edition (or Azure SQL MI)
- [ ] Same SQL Server version on all replicas
- [ ] Same patch level on all replicas
- [ ] Database in FULL recovery model
- [ ] Regular transaction log backups

**Database Configuration:**
- [ ] CDC enabled on primary
- [ ] CDC retention appropriate (default 3 days)
- [ ] Transaction log sized appropriately
- [ ] SECONDARY_ROLE(ALLOW_CONNECTIONS = ALL)
- [ ] AG_Listener configured with static IP

**Network:**
- [ ] Low latency between replicas (<5ms for sync mode)
- [ ] Sufficient bandwidth for replication
- [ ] Firewall rules for port 1433 (listener) and 5022 (endpoint)
- [ ] DNS properly configured for listener name

---

### Monitoring Queries for DBAs

**1. Check AG Health**
```sql
-- Overall AG health
SELECT 
    ag.name AS AG_Name,
    ar.replica_server_name,
    ar.availability_mode_desc,
    ars.role_desc,
    ars.operational_state_desc,
    ars.connected_state_desc,
    ars.synchronization_health_desc,
    ars.last_connect_error_description
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
ORDER BY ars.role_desc DESC, ar.replica_server_name;
```

**2. Check Synchronization Status**
```sql
-- Database sync state and lag
SELECT 
    db.name AS DatabaseName,
    ar.replica_server_name,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.log_send_queue_size / 1024.0 AS log_send_queue_MB,
    drs.log_send_rate / 1024.0 AS log_send_rate_MB_per_sec,
    drs.redo_queue_size / 1024.0 AS redo_queue_MB,
    drs.redo_rate / 1024.0 AS redo_rate_MB_per_sec,
    CASE 
        WHEN drs.redo_rate = 0 THEN NULL
        ELSE CAST(drs.redo_queue_size / drs.redo_rate AS DECIMAL(10,2))
    END AS redo_time_remaining_seconds
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
JOIN sys.databases db ON drs.database_id = db.database_id;
```

**3. Monitor CDC Capture Job**
```sql
-- CDC capture job status
EXEC sys.sp_cdc_help_jobs;

-- CDC table row counts (monitor growth)
SELECT 
    OBJECT_NAME(ct.source_object_id) AS source_table,
    ct.capture_instance,
    p.rows AS cdc_table_rows,
    (p.rows * 8 / 1024.0 / 1024.0) AS cdc_table_size_GB
FROM cdc.change_tables ct
JOIN sys.partitions p ON p.object_id = ct.object_id AND p.index_id < 2
ORDER BY p.rows DESC;
```

**4. Identify Active Debezium Connections**
```sql
-- Find Debezium sessions
SELECT 
    s.session_id,
    s.login_time,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status,
    c.local_net_address,
    c.client_net_address,
    s.reads,
    s.writes,
    s.cpu_time,
    DATEDIFF(MINUTE, s.last_request_start_time, GETDATE()) AS minutes_since_last_request
FROM sys.dm_exec_sessions s
JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
WHERE s.program_name LIKE '%Debezium%' 
   OR s.login_name = 'debezium_user'
ORDER BY s.login_time DESC;
```

**5. Check Listener Status**
```sql
-- AG Listener configuration
SELECT 
    agl.dns_name AS ListenerName,
    agl.port,
    agip.ip_address,
    agip.ip_subnet_mask,
    agip.is_dhcp,
    agip.state_desc
FROM sys.availability_group_listeners agl
JOIN sys.availability_group_listener_ip_addresses agip 
    ON agl.listener_id = agip.listener_id;
```

---

### Maintenance Operations

**1. Planned Maintenance on Primary**
```sql
-- Step 1: Verify sync status (must be SYNCHRONIZED)
SELECT synchronization_health_desc 
FROM sys.dm_hadr_availability_replica_states
WHERE is_local = 1;

-- Step 2: Initiate planned failover
ALTER AVAILABILITY GROUP AG_YourDatabase FAILOVER;

-- Step 3: Perform maintenance on old primary (now secondary)
-- - Apply patches
-- - Perform backups
-- - etc.

-- Step 4: When ready, failover back (optional)
-- Connect to new primary and execute:
ALTER AVAILABILITY GROUP AG_YourDatabase FAILOVER;
```

**2. Adding a Table to CDC (on AG)**
```sql
-- IMPORTANT: Only run on PRIMARY replica
-- CDC changes automatically replicate to secondaries

-- Connect to primary
SELECT @@SERVERNAME, 
       (SELECT role_desc FROM sys.dm_hadr_availability_replica_states WHERE is_local = 1);

-- Enable CDC on new table
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'NewTable',
    @role_name = NULL,
    @supports_net_changes = 1;

-- Wait for replication to secondary (usually immediate)
-- Verify on secondary (read-only, just checking):
SELECT is_tracked_by_cdc FROM sys.tables WHERE name = 'NewTable';
```

**3. Removing a Replica (Scaling Down)**
```sql
-- Step 1: Remove replica from AG
ALTER AVAILABILITY GROUP AG_YourDatabase
REMOVE REPLICA ON 'SERVER2';

-- Step 2: On SERVER2, drop database
DROP DATABASE YourDatabase;

-- Step 3: Update listener if needed (remove IP)
```

**4. Adding a Replica (Scaling Up)**
```sql
-- On existing primary, add new replica
ALTER AVAILABILITY GROUP AG_YourDatabase
ADD REPLICA ON 'SERVER3'
WITH (
    ENDPOINT_URL = 'TCP://server3.domain.com:5022',
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
    FAILOVER_MODE = AUTOMATIC,
    SECONDARY_ROLE(ALLOW_CONNECTIONS = ALL)
);

-- On SERVER3, join and add database (see Step 2 earlier)
```

---

### Performance Tuning

**1. Optimize CDC Capture Job**
```sql
-- Adjust CDC scan interval (default: 5 seconds)
-- Lower = more frequent scans, higher CPU
-- Higher = less frequent scans, higher lag

EXEC sys.sp_cdc_change_job 
    @job_type = N'capture',
    @pollinginterval = 3;  -- 3 seconds

-- Adjust max scan batch
EXEC sys.sp_cdc_change_job 
    @job_type = N'capture',
    @maxtrans = 1000,      -- Max transactions per scan
    @maxscans = 20;        -- Max scans per cycle
```

**2. Transaction Log Management**
```sql
-- Monitor log growth
SELECT 
    name,
    (size * 8.0 / 1024) AS size_MB,
    (FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024) AS used_MB,
    ((size - FILEPROPERTY(name, 'SpaceUsed')) * 8.0 / 1024) AS free_MB
FROM sys.database_files
WHERE type_desc = 'LOG';

-- If log is growing excessively:
-- 1. Check if log backups are running
-- 2. Check CDC cleanup job
EXEC sys.sp_cdc_help_jobs;

-- 3. Manually cleanup old CDC data if needed
EXEC sys.sp_cdc_cleanup_change_table 
    @capture_instance = 'dbo_Customers',
    @low_water_mark = NULL,  -- NULL = default retention
    @threshold = 5000;
```

**3. Monitor Replication Lag**
```sql
-- Alert if lag exceeds threshold
DECLARE @threshold_seconds INT = 10;

SELECT 
    ar.replica_server_name,
    CASE 
        WHEN drs.redo_rate = 0 THEN 999999
        ELSE drs.redo_queue_size / drs.redo_rate
    END AS estimated_lag_seconds
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
WHERE drs.is_local = 0
  AND (drs.redo_queue_size / NULLIF(drs.redo_rate, 0)) > @threshold_seconds;
  
-- If lag is high:
-- - Check network bandwidth
-- - Check secondary server resources
-- - Consider async replication for distant replicas
```

---

## 📊 Monitoring & Verification

### Grafana Dashboard Metrics

**Add these queries to your Grafana dashboard:**

**1. Database Connection Status**
```promql
# Should always be 1 (connected)
debezium_sql_server_connector_metrics_connected
```

**2. Failover Detection**
```promql
# Spikes indicate connection drops (potential failover)
rate(kafka_connect_connector_failed_task_restarts_total[5m])
```

**3. CDC Lag During Failover**
```promql
# Monitor lag increase during failover
debezium_sql_server_connector_metrics_millisecondsbehindsource
```

---

### Alert Rules for Failover

**Add to monitoring/prometheus-rules.yaml:**

```yaml
- alert: DebeziumConnectionLost
  expr: debezium_sql_server_connector_metrics_connected == 0
  for: 1m
  labels:
    severity: warning
  annotations:
    summary: "Debezium lost connection to SQL Server"
    description: "May indicate ongoing failover or network issue"

- alert: DebeziumHighFailoverLag
  expr: debezium_sql_server_connector_metrics_millisecondsbehindsource > 30000
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "Debezium lag exceeded 30 seconds"
    description: "Possible failover in progress or replication delay"

- alert: DebeziumFrequentReconnections
  expr: rate(kafka_connect_connector_failed_task_restarts_total[10m]) > 0.1
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Debezium connector restarting frequently"
    description: "May indicate AG flapping or configuration issue"
```

---

### Health Check Scripts

**scripts/check-ag-health.sql**
```sql
-- Comprehensive AG health check
-- Run daily or after failover

SET NOCOUNT ON;

PRINT '========================================';
PRINT 'Always On Availability Group Health Check';
PRINT 'Timestamp: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '========================================';

-- AG Status
PRINT '';
PRINT '1. Availability Group Status:';
SELECT 
    ag.name AS AG_Name,
    ars.role_desc AS Role,
    ars.operational_state_desc AS State,
    ars.connected_state_desc AS Connected,
    ars.synchronization_health_desc AS Sync_Health
FROM sys.availability_groups ag
JOIN sys.dm_hadr_availability_replica_states ars 
    ON ag.group_id = ars.group_id
WHERE ars.is_local = 1;

-- Replica Status
PRINT '';
PRINT '2. All Replicas Status:';
SELECT 
    ar.replica_server_name AS Server,
    ars.role_desc AS Role,
    ars.synchronization_health_desc AS Sync_Health,
    ars.connected_state_desc AS Connected
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id;

-- Database Sync
PRINT '';
PRINT '3. Database Synchronization:';
SELECT 
    db.name AS DatabaseName,
    drs.synchronization_state_desc AS Sync_State,
    drs.log_send_queue_size / 1024 AS log_send_queue_KB,
    CASE 
        WHEN drs.redo_rate = 0 THEN 0
        ELSE drs.redo_queue_size / drs.redo_rate
    END AS estimated_lag_seconds
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.databases db ON drs.database_id = db.database_id
WHERE drs.is_local = 1;

-- Listener Status
PRINT '';
PRINT '4. Listener Status:';
SELECT 
    dns_name AS Listener,
    port AS Port,
    ip_configuration_string_from_cluster AS IP_Config
FROM sys.availability_group_listeners;

-- CDC Status
PRINT '';
PRINT '5. CDC Status:';
SELECT 
    name AS DatabaseName,
    is_cdc_enabled AS CDC_Enabled
FROM sys.databases 
WHERE database_id > 4;  -- Exclude system databases

PRINT '';
PRINT '========================================';
PRINT 'Health Check Complete';
PRINT '========================================';
```

---

## 🔧 Troubleshooting

### Issue 1: Connector Can't Connect After Failover

**Symptoms:**
```
Error: "No readable secondary replica available for the Always On availability group"
```

**Root Cause:**
- Primary failed, became secondary
- No other secondary available
- ApplicationIntent=ReadOnly fails

**Solution:**

**Option A: Wait for Failed Server to Recover**
```bash
# Monitor AG status
sqlcmd -S AG_Listener_YourDB.domain.com -Q \
  "SELECT replica_server_name, role_desc, connected_state_desc 
   FROM sys.dm_hadr_availability_replica_states ars 
   JOIN sys.availability_replicas ar ON ars.replica_id = ar.replica_id"

# Wait for secondary to appear (usually 2-10 minutes)
```

**Option B: Temporarily Read from Primary**
```bash
# Update connector config
kubectl edit connector sqlserver-debezium-connector -n confluent

# Remove or comment out this line:
# database.applicationIntent: "ReadOnly"

# Connector will reconnect to primary
# Revert this change once secondary is available
```

**Option C: Add New Secondary (Permanent Solution)**
```sql
-- Add another replica to AG for redundancy
ALTER AVAILABILITY GROUP AG_YourDatabase
ADD REPLICA ON 'SERVER3'
WITH (
    ENDPOINT_URL = 'TCP://server3.domain.com:5022',
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
    FAILOVER_MODE = AUTOMATIC,
    SECONDARY_ROLE(ALLOW_CONNECTIONS = ALL)
);
```

---

### Issue 2: High Lag During Failover

**Symptoms:**
```
debezium_sql_server_connector_metrics_millisecondsbehindsource > 60000
```

**Possible Causes:**
1. Large transaction volume during failover
2. Slow secondary server
3. Network issues between replicas

**Diagnostic Queries:**
```sql
-- Check replication queue
SELECT 
    ar.replica_server_name,
    drs.log_send_queue_size / 1024 AS log_send_queue_MB,
    drs.log_send_rate / 1024 AS log_send_rate_MB_per_sec,
    drs.redo_queue_size / 1024 AS redo_queue_MB,
    drs.redo_rate / 1024 AS redo_rate_MB_per_sec
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id;

-- Check for blocking on secondary
SELECT * FROM sys.dm_exec_requests WHERE blocking_session_id <> 0;
```

**Solutions:**
1. Increase secondary server resources
2. Optimize CDC capture job frequency
3. Consider async commit for distant replicas
4. Partition large transactions

---

### Issue 3: Listener Name Not Resolving

**Symptoms:**
```
Error: "A network-related or instance-specific error occurred"
```

**Diagnostic:**
```bash
# Test DNS resolution
nslookup AG_Listener_YourDB.domain.com

# Test connectivity
Test-NetConnection -ComputerName AG_Listener_YourDB.domain.com -Port 1433

# Check listener status on SQL Server
sqlcmd -S server1.domain.com -Q \
  "SELECT dns_name, port, ip_configuration_string_from_cluster 
   FROM sys.availability_group_listeners"
```

**Solutions:**
1. Verify DNS is configured correctly
2. Check firewall rules for port 1433
3. Verify listener IP is in correct subnet
4. Flush DNS cache: `ipconfig /flushdns`

---

### Issue 4: CDC Not Replicating to Secondary

**Symptoms:**
- CDC works on primary
- Debezium can't read from secondary

**Diagnostic:**
```sql
-- On SECONDARY replica (read-only connection)
SELECT 
    name,
    is_cdc_enabled
FROM sys.databases
WHERE name = 'YourDatabase';

SELECT 
    name,
    is_tracked_by_cdc
FROM sys.tables
WHERE is_tracked_by_cdc = 1;

-- Check CDC system tables exist
SELECT COUNT(*) FROM cdc.change_tables;
```

**Root Cause:**
- CDC metadata doesn't replicate automatically in some scenarios

**Solution:**
```sql
-- On PRIMARY, ensure CDC is enabled properly
EXEC sys.sp_cdc_enable_db;
EXEC sys.sp_cdc_enable_table 
    @source_schema = N'dbo',
    @source_name = N'TableName',
    @role_name = NULL;

-- Verify replication to secondary
-- CDC system tables should replicate automatically
-- If not, check AG configuration allows data replication
```

---

## 📚 Best Practices Summary

### Configuration Best Practices

1. ✅ **Always use AG Listener** instead of direct server names
2. ✅ **Enable multiSubnetFailover** for faster failover detection
3. ✅ **Use ApplicationIntent=ReadOnly** to route to secondary
4. ✅ **Configure retry timeouts** appropriately (5+ minutes)
5. ✅ **Use synchronous commit** for zero data loss
6. ✅ **Have 2+ replicas** for continuous secondary availability
7. ✅ **Monitor AG health** proactively
8. ✅ **Test failover regularly** (monthly recommended)
9. ✅ **Document failover procedures** for on-call staff
10. ✅ **Configure alerts** for connection issues

### Operational Best Practices

1. ✅ **Regular failover testing** to verify procedures
2. ✅ **Monitor synchronization lag** continuously
3. ✅ **Tune CDC retention** based on lag patterns
4. ✅ **Plan maintenance windows** with failover
5. ✅ **Keep AG and SQL Server versions synchronized**
6. ✅ **Review CDC cleanup job** regularly
7. ✅ **Monitor transaction log growth** on primary
8. ✅ **Verify Debezium lag** stays under 5 seconds
9. ✅ **Document AG topology** and keep updated
10. ✅ **Train DBAs** on AG management

---

## 🎯 Summary

This setup provides:

✅ **Automatic Failover:** 10-30 second failover with zero config changes  
✅ **Zero Data Loss:** Synchronous replication ensures no CDC events lost  
✅ **High Availability:** Multiple replicas with automatic promotion  
✅ **Reduced Primary Load:** Debezium reads from secondary replica  
✅ **Seamless Recovery:** Connector auto-reconnects after failover  
✅ **Production Ready:** Tested procedures and comprehensive monitoring  

### Key Metrics

- **Failover Time:** 10-30 seconds (automatic)
- **Data Loss:** Zero (with synchronous commit)
- **Debezium Downtime:** 0-60 seconds (depends on scenario)
- **Manual Intervention:** None required (in most scenarios)
- **Replication Lag:** <1 second (normal), <10 seconds (during failover)

---

**Document Version:** 1.0  
**Last Updated:** 2026-06-22  
**Tested Scenarios:** Planned failover, automatic failover, replica recovery  
**Production Status:** ✅ Ready for deployment
