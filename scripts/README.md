# Scripts Directory

Utility scripts for managing and testing the Debezium CDC deployment.

---

## 📜 Shell Scripts

### quick-commands.sh

Interactive helper script for common operations.

**Usage:**
```bash
./scripts/quick-commands.sh [command]
```

**Available Commands:**
- `status` - Full status check (Connect + Connector + Topics)
- `connect` - Check Kafka Connect cluster status
- `plugins` - List all connector plugins
- `debezium` - Check Debezium plugin installation
- `deploy` - Deploy the Debezium connector
- `connector` - Check connector status
- `logs` - View connector logs (last 50 lines)
- `follow` - Follow connector logs in real-time
- `topics` - List Debezium-related Kafka topics
- `consume [topic]` - Consume messages from a topic
- `delete` - Delete the connector

**Examples:**
```bash
./scripts/quick-commands.sh status
./scripts/quick-commands.sh consume azure-sqlserver.dbo.Orders
./scripts/quick-commands.sh logs
```

---

## 📊 SQL Scripts

These scripts are for SQL Server CDC setup, verification, and testing.

**Note:** Update database names, server names, and table names according to your environment before running.

### complete-cdc-setup.sql

**Purpose:** Complete CDC setup on Azure SQL Server (Primary)

**What it does:**
- Enables CDC on database
- Enables CDC on specified tables (Customers, Orders, Products)
- Verifies CDC configuration
- Checks CDC capture job status

**Run on:** Primary SQL Server
**Database:** Your primary database

**Before running:** Update these values:
- Database name (replace `primdb`)
- Table names (replace `Customers`, `Orders`, `Products`)

**Usage:**
```sql
-- Update database name and run on primary server
sqlcmd -S primaryserver.database.windows.net -U sqladmin -P password -d YourDatabase -i complete-cdc-setup.sql
```

---

### check-cdc-activity.sql

**Purpose:** Monitor CDC read activity and verify Debezium is reading from the correct server

**What it does:**
- Shows recent queries against CDC tables
- Counts active CDC sessions
- Displays last executed queries
- Identifies JDBC/Debezium connections

**Run on:** Primary AND Secondary SQL Server (to compare)
**Database:** Your database

**Before running:** Update:
- Database name (replace `primdb`)
- Username (replace `sqladmin` if different)

**Usage:**
```sql
-- Run on both primary and secondary to compare activity
sqlcmd -S secondaryserver.database.windows.net -U sqladmin -P password -d YourDatabase -i check-cdc-activity.sql
```

**Expected output:**
- On Secondary: Should see active JDBC connections and CDC queries
- On Primary: Should see fewer or no Debezium connections (if reading from secondary)

---

### check-secondary-connections.sql

**Purpose:** Verify active connections on secondary replica

**What it does:**
- Lists all active sessions on secondary server
- Filters connections from Debezium/Kafka Connect
- Shows current SQL being executed
- Groups connections by application

**Run on:** Secondary SQL Server (read replica)
**Database:** Your database

**Before running:** Update:
- Database name (replace `primdb`)
- Secondary server name

**Usage:**
```sql
sqlcmd -S secondaryserver.database.windows.net -U sqladmin -P password -d YourDatabase -i check-secondary-connections.sql
```

**Look for:**
- Sessions from Java/JDBC programs
- Login name matching your Debezium user
- Active queries against CDC tables

---

### test-e2e-flow.sql

**Purpose:** End-to-end flow test - insert test data and verify CDC pipeline

**What it does:**
- Inserts a unique test record on PRIMARY server
- Verifies record was inserted
- Provides timing guidance for checking Kafka

**Run on:** Primary SQL Server (NOT secondary!)
**Database:** Your primary database

**Before running:** Update:
- Database name
- Table name (if not using Customers)

**Usage:**
```sql
-- Run on PRIMARY server only
sqlcmd -S primaryserver.database.windows.net -U sqladmin -P password -d YourDatabase -i test-e2e-flow.sql
```

**After running:**
1. Wait ~60 seconds (30s geo-replication + 10s CDC capture)
2. Check Kafka topic for the test message:
   ```bash
   ./scripts/quick-commands.sh consume sqlserver.dbo.Customers
   ```
3. Look for the test record: `email = 'e2e-test@verify.com'`

---

## 🔄 Typical Workflow

### Initial Setup
```bash
# 1. Run CDC setup on primary SQL Server
sqlcmd -S primaryserver.database.windows.net -i scripts/complete-cdc-setup.sql

# 2. Deploy Debezium connector
./scripts/quick-commands.sh deploy

# 3. Verify connector status
./scripts/quick-commands.sh status
```

### Verification
```bash
# 1. Check connections on secondary (should see Debezium)
sqlcmd -S secondaryserver.database.windows.net -i scripts/check-secondary-connections.sql

# 2. Check CDC activity on both servers
sqlcmd -S primaryserver.database.windows.net -i scripts/check-cdc-activity.sql
sqlcmd -S secondaryserver.database.windows.net -i scripts/check-cdc-activity.sql

# 3. Run end-to-end test
sqlcmd -S primaryserver.database.windows.net -i scripts/test-e2e-flow.sql

# 4. Verify message in Kafka
./scripts/quick-commands.sh consume
```

### Daily Operations
```bash
# Check overall status
./scripts/quick-commands.sh status

# View recent logs
./scripts/quick-commands.sh logs

# Consume latest messages
./scripts/quick-commands.sh consume
```

---

## ⚠️ Important Notes

### Before Running SQL Scripts

1. **Update Variables:** All SQL scripts contain example values that must be updated:
   - Database name: `primdb` → `YourDatabase`
   - Server names: `primaryserver`, `secondaryserver` → Your actual servers
   - Table names: `Customers`, `Orders`, `Products` → Your actual tables
   - Username: `sqladmin` → Your actual username

2. **Test on Development:** Always test scripts on a development database first

3. **Backup:** Ensure you have backups before making CDC changes

4. **Permissions:** Ensure you have sufficient permissions to enable CDC

### SQL Server Requirements

- SQL Server 2016+ or Azure SQL Database
- SQL Server Agent must be running
- User must have db_owner or appropriate CDC permissions
- For geo-replicated databases: CDC must be enabled on PRIMARY only

---

## 📝 Customization Examples

### Example: Customize complete-cdc-setup.sql

```sql
-- Change database name
USE YourActualDatabase;  -- Instead of 'primdb'

-- Enable CDC on your tables
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'YourTableName',  -- Instead of 'Customers'
    @role_name = NULL,
    @supports_net_changes = 1;
```

### Example: Customize check-cdc-activity.sql

```sql
-- Update database ID check
WHERE s.database_id = DB_ID('YourDatabase')  -- Instead of 'primdb'
    AND s.login_name = 'your_debezium_user';  -- Instead of 'sqladmin'
```

---

## 🔍 Troubleshooting

### SQL Scripts Not Working?

**Error: Database not found**
- Update database name in script
- Ensure you're connected to the correct server

**Error: Permission denied**
- User needs db_owner or CDC permissions
- Check: `SELECT IS_SRVROLEMEMBER('sysadmin')`

**Error: SQL Agent not running**
- Required for CDC capture job
- Check: `SELECT status FROM sys.dm_exec_sessions WHERE program_name LIKE '%Agent%'`

### Shell Script Issues

**Error: kubectl not found**
- Install kubectl: `brew install kubectl` (macOS)
- Or: `sudo apt-get install kubectl` (Linux)

**Error: connect-0 pod not found**
- Verify namespace: `kubectl get pods -n confluent`
- Check pod name: `kubectl get pods -n confluent | grep connect`

**Error: Permission denied when running script**
- Make executable: `chmod +x scripts/quick-commands.sh`

---

## 📞 Support

For issues with these scripts:
- **SQL Scripts:** Check [PRODUCTION-SETUP-QUICK-REFERENCE.md](../PRODUCTION-SETUP-QUICK-REFERENCE.md)
- **Shell Scripts:** Check [CLI-COMMANDS.md](../CLI-COMMANDS.md)
- **General:** See [README.md](../README.md)

---

**Last Updated:** 2026-06-22
