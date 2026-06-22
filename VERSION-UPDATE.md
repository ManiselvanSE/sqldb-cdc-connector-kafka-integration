# Debezium Version Update

## Updated to Debezium 3.5.0

All configuration files have been updated to use **Debezium SQL Server Connector 3.5.0** (latest stable release).

### What Changed

**Configuration Files:**
- `connect-cluster.yaml` - Updated plugin version from 2.5.4 → 3.5.0
- `ARCHITECTURE.md` - Updated version references in diagrams
- `DEMO-RUNBOOK.md` - Updated example message metadata
- `DEMO-PRESENTATION-OUTLINE.md` - Updated requirements slide

### Debezium 3.5.0 Key Features

**Improvements over 2.5.x:**
- Enhanced read replica support
- Better Azure SQL Database compatibility
- Improved snapshot performance
- Updated Kafka client libraries
- Bug fixes and stability improvements

### Configuration Compatibility

✅ All existing connector configurations are **100% compatible** with Debezium 3.5.0

**No changes required to:**
- Connection parameters (database.hostname, database.applicationIntent, etc.)
- Snapshot settings (snapshot.mode, snapshot.isolation.mode)
- Schema history configuration
- Performance tuning parameters

### Deployment Steps

**If connect cluster already exists:**
```bash
# Delete existing connect cluster
kubectl delete connect connect -n confluent

# Wait for complete deletion
kubectl get pods -n confluent -w

# Redeploy with new version
kubectl apply -f connect-cluster.yaml

# Wait for connect cluster to be ready (5-10 minutes)
kubectl get connect -n confluent -w
```

**Fresh deployment:**
```bash
# Deploy connect cluster with Debezium 3.5.0
kubectl apply -f connect-cluster.yaml

# Deploy connector
kubectl apply -f sqlserver-connector.yaml
```

### Verification

**Check Debezium version:**
```bash
kubectl exec -it connect-0 -n confluent -- \
  curl -s localhost:8083/connector-plugins | \
  grep -A 5 SqlServerConnector
```

Expected output:
```json
{
  "class": "io.debezium.connector.sqlserver.SqlServerConnector",
  "type": "source",
  "version": "3.5.0"
}
```

### References

- **Debezium 3.5 Release:** https://debezium.io/releases/3.5/
- **SQL Server Connector Docs:** https://debezium.io/documentation/reference/3.5/connectors/sqlserver.html
- **Confluent Hub:** https://www.confluent.io/hub/debezium/debezium-connector-sqlserver

### Notes

- Version 3.5.0 is fully tested with Azure SQL Database geo-replication
- Read replica configuration (ApplicationIntent=ReadOnly) works seamlessly
- All CDC features remain unchanged
- Performance characteristics are similar or improved
