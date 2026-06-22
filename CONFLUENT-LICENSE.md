# Confluent Platform License Information

## ⚠️ Trial Expired

**Issue:** Confluent Platform trial period has expired  
**Message:** "To continue using Confluent, purchase a license or register your existing enterprise license key"  
**Control Center:** http://20.235.11.19:9021/settings/updates

---

## Current Status

The Confluent Platform components are still running, but certain features may be restricted:
- ✅ **Kafka Cluster** - Still operational
- ✅ **Kafka Connect** - Still operational
- ✅ **Debezium Connector** - Still capturing CDC changes
- ⚠️ **Control Center** - May show license warning
- ⚠️ **Schema Registry** - May be restricted
- ⚠️ **Advanced features** - May be disabled

**Good News:** Core functionality (Kafka, Connect, CDC) continues to work!

---

## Solution Options

### Option 1: Apply Enterprise License Key (Recommended for Production)

If you have a Confluent Enterprise license:

**Via Control Center UI:**
1. Go to http://20.235.11.19:9021/settings/updates
2. Click "Add License Key"
3. Paste your enterprise license key
4. Click "Save"

**Via kubectl:**
```bash
# Create license secret
kubectl create secret generic confluent-license \
  --from-file=license.txt=path/to/your/license.txt \
  -n confluent

# Reference in platform components
# Add to controlcenter.yaml, kafka.yaml, etc:
spec:
  license:
    secretRef: confluent-license
```

### Option 2: Request Trial Extension

For continued evaluation:

**Contact Confluent:**
- Email: contact@confluent.io
- Request: 30/60/90 day trial extension
- Mention: Azure SQL CDC POC/Demo

### Option 3: Use Confluent Community License

**What's Included:**
- ✅ Kafka brokers
- ✅ Kafka Connect
- ✅ REST Proxy
- ❌ Control Center (limited)
- ❌ Schema Registry (limited)
- ❌ Tiered Storage
- ❌ Self-Balancing Clusters

**How to Apply:**
```bash
# No action needed - community features continue to work
# Some enterprise features will be disabled
```

### Option 4: Switch to Apache Kafka (Open Source)

For full open-source deployment without Confluent Platform:

**Advantages:**
- ✅ Completely free
- ✅ No license required
- ✅ Kafka Connect works
- ✅ Debezium works

**Disadvantages:**
- ❌ No Control Center UI
- ❌ No enterprise support
- ❌ Manual configuration
- ❌ No operator (need Helm/StatefulSets)

**Migration Required:**
- Redeploy with Apache Kafka images
- Install Debezium separately
- Use CLI tools instead of Control Center

### Option 5: Confluent Cloud (SaaS)

**Advantages:**
- ✅ Fully managed
- ✅ No infrastructure management
- ✅ Pay-as-you-go pricing
- ✅ Enterprise features included

**Considerations:**
- 💰 Usage-based pricing
- 🌐 Azure SQL connection from cloud
- 📊 Different pricing model

---

## Workaround: Continue Using Current Setup

**What Still Works:**

Even with an expired trial, core functionality continues:

```bash
# ✅ Kafka cluster - WORKS
kubectl get kafka -n confluent

# ✅ Connect cluster - WORKS
kubectl get connect -n confluent

# ✅ Connector - WORKS
kubectl get connector -n confluent

# ✅ Topics - WORKS
kubectl exec kafka-0 -n confluent -- \
  kafka-topics --list --bootstrap-server localhost:9071

# ✅ Consuming messages - WORKS
kubectl exec kafka-0 -n confluent -- \
  kafka-console-consumer \
    --bootstrap-server localhost:9071 \
    --topic azure-sqlserver.primdb.dbo.Customers \
    --from-beginning

# ✅ CDC capture - WORKS
# Debezium continues capturing changes
```

**What May Not Work:**
- Control Center UI (shows license warning)
- Advanced monitoring features
- Enterprise-only connectors
- Tiered storage
- Self-balancing

---

## Verification Commands

### Check Current License Status

```bash
# Via Control Center
curl -s http://20.235.11.19:9021/2.0/license | jq

# Via Kafka broker
kubectl exec kafka-0 -n confluent -- \
  kafka-configs --bootstrap-server localhost:9071 \
  --describe --entity-type brokers --entity-default | \
  grep confluent.license
```

### Test Core Functionality

```bash
# 1. Verify Kafka cluster
kubectl get kafka -n confluent

# 2. Verify Connect
kubectl get connect -n confluent

# 3. Verify connector status
kubectl get connector -n confluent

# 4. List topics
kubectl exec kafka-0 -n confluent -- \
  kafka-topics --list --bootstrap-server localhost:9071

# 5. Consume CDC messages
kubectl exec kafka-0 -n confluent -- \
  kafka-console-consumer \
    --bootstrap-server localhost:9071 \
    --topic azure-sqlserver.primdb.dbo.Customers \
    --from-beginning \
    --max-messages 5
```

All of these should still work even with expired trial!

---

## Recommended Action Plan

### For Demo/POC (Next 1-2 weeks):

**Continue as-is:**
- ✅ Core CDC functionality works
- ✅ Debezium connector operational
- ✅ Can demonstrate to customers
- ⚠️ Control Center shows license warning (ignore for demo)

**Action:** Request trial extension from Confluent

### For Production (Next 1-3 months):

**Option A: Purchase Confluent Enterprise License**
- Best for: Enterprise deployments
- Cost: Contact Confluent sales
- Benefits: Full support, all features

**Option B: Use Confluent Cloud**
- Best for: Cloud-first organizations
- Cost: Pay-as-you-go
- Benefits: Fully managed, no ops overhead

**Option C: Open Source Apache Kafka**
- Best for: Cost-sensitive deployments
- Cost: Free (infrastructure costs only)
- Trade-off: No UI, manual management

---

## License FAQ

### Q: Will my connector stop working?
**A:** No! Kafka Connect and Debezium continue to work even with expired trial.

### Q: Will CDC capture stop?
**A:** No! CDC capture continues normally.

### Q: Can I still consume messages?
**A:** Yes! Message consumption works fine.

### Q: What happens to my data?
**A:** All data remains intact. Topics, messages, offsets are preserved.

### Q: Can I still deploy new connectors?
**A:** Yes! Connector deployment continues to work.

### Q: Is Control Center completely unusable?
**A:** No, it shows a warning banner but most features still work for monitoring.

---

## Cost Comparison

| Option | Setup Cost | Monthly Cost | Support | Management |
|--------|------------|--------------|---------|------------|
| **Trial** | $0 | $0 (limited time) | Community | Self |
| **Community** | $0 | $0 | Community | Self |
| **Enterprise** | $0 | ~$5K-50K+ | Enterprise | Self |
| **Confluent Cloud** | $0 | ~$500-5K+ | Enterprise | Managed |
| **Apache Kafka OSS** | $0 | Infrastructure | Community | Self |

*Prices are estimates and vary based on usage/scale*

---

## Immediate Next Steps

### Step 1: Verify Current Functionality (5 minutes)

```bash
# Run all verification commands above
# Ensure CDC is still working
```

### Step 2: Choose Path Forward (1 day)

- [ ] Request trial extension for demo
- [ ] Contact Confluent sales for enterprise license quote
- [ ] Evaluate Confluent Cloud
- [ ] Plan migration to open-source if needed

### Step 3: Document Decision

Update this file with chosen path and timeline.

---

## Contact Information

**Confluent Sales:**
- Email: contact@confluent.io
- Web: https://www.confluent.io/contact/
- Phone: Check Confluent website for regional numbers

**Trial Extension Request Template:**

```
Subject: Trial Extension Request - Azure SQL CDC POC

Hello Confluent Team,

We are currently evaluating Confluent Platform for a production Azure SQL 
Server CDC use case with Debezium. Our trial has expired and we would like 
to request a 60-day extension to complete our POC and business case.

Current Setup:
- Confluent Platform 7.8.0
- Debezium SQL Server Connector 2.5.4
- Azure SQL geo-replicated CDC
- Use case: Real-time data replication for analytics

We plan to evaluate for production deployment within the next 60 days.

Thank you,
[Your Name]
[Company]
```

---

## Summary

**Current Status:** Trial expired, but CDC pipeline fully operational ✅

**Impact:** Minimal - core functionality continues working

**Recommendation:** 
1. Continue using for demos/POC
2. Request trial extension
3. Evaluate license options for production

**No Immediate Action Required:** System continues to function normally!

---

**Last Updated:** 2026-06-22  
**Next Review:** Request trial extension within 7 days
