# CLI Commands - Control Center Alternative

Since Control Center shows license warning, use these CLI commands instead:

## Monitor Connector Status

```bash
# Check connector status
kubectl get connector -n confluent

# Get detailed connector info
kubectl describe connector sqlserver-debezium-connector -n confluent

# View connector configuration
kubectl exec connect-0 -n confluent -- \
  curl -s localhost:8083/connectors/sqlserver-debezium-connector | \
  python3 -m json.tool

# Check connector tasks
kubectl exec connect-0 -n confluent -- \
  curl -s localhost:8083/connectors/sqlserver-debezium-connector/status | \
  python3 -m json.tool
```

## Monitor Topics

```bash
# List all CDC topics
kubectl exec kafka-0 -n confluent -- \
  kafka-topics --list --bootstrap-server localhost:9071 | \
  grep azure-sqlserver

# Describe a topic
kubectl exec kafka-0 -n confluent -- \
  kafka-topics --describe \
  --bootstrap-server localhost:9071 \
  --topic sqlserver.dbo.Customers

# Check topic lag
kubectl exec kafka-0 -n confluent -- \
  kafka-consumer-groups --bootstrap-server localhost:9071 \
  --describe --group connect-sqlserver-debezium-connector
```

## Consume CDC Messages

```bash
# Consume latest messages
kubectl exec kafka-0 -n confluent -- \
  kafka-console-consumer \
    --bootstrap-server localhost:9071 \
    --topic sqlserver.dbo.Customers \
    --from-beginning \
    --max-messages 10

# Consume with pretty JSON formatting
kubectl exec kafka-0 -n confluent -- \
  kafka-console-consumer \
    --bootstrap-server localhost:9071 \
    --topic sqlserver.dbo.Customers \
    --from-beginning \
    --max-messages 1 | \
  python3 -m json.tool

# Tail messages (follow mode)
kubectl exec -it kafka-0 -n confluent -- \
  kafka-console-consumer \
    --bootstrap-server localhost:9071 \
    --topic sqlserver.dbo.Customers
```

## Monitor Connect Cluster

```bash
# Check Connect cluster status
kubectl get connect -n confluent

# View Connect logs
kubectl logs -n confluent connect-0 -f

# Check available plugins
kubectl exec connect-0 -n confluent -- \
  curl -s localhost:8083/connector-plugins | \
  python3 -m json.tool | \
  grep -A 3 SqlServer
```

## Health Checks

```bash
# Full system status
kubectl get kafka,connect,connector -n confluent

# Check Kafka cluster health
kubectl get kafka kafka -n confluent -o yaml | \
  grep -A 5 "phase:"

# Check pod health
kubectl get pods -n confluent

# View pod logs
kubectl logs -n confluent connect-0 --tail=100
```

## Restart Operations

```bash
# Restart connector (if needed)
kubectl delete connector sqlserver-debezium-connector -n confluent
kubectl apply -f sqlserver-connector.yaml

# Restart Connect cluster (if needed)
kubectl delete pod connect-0 -n confluent
# Wait for automatic recreation
kubectl get pods -n confluent -w
```

## Create Quick Aliases

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# Kafka aliases
alias k-topics='kubectl exec kafka-0 -n confluent -- kafka-topics --list --bootstrap-server localhost:9071'
alias k-consume='kubectl exec kafka-0 -n confluent -- kafka-console-consumer --bootstrap-server localhost:9071'

# Connect aliases
alias k-connector='kubectl get connector -n confluent'
alias k-connect-logs='kubectl logs -n confluent connect-0 -f'

# CDC topic consumer
alias k-cdc-customers='kubectl exec kafka-0 -n confluent -- kafka-console-consumer --bootstrap-server localhost:9071 --topic sqlserver.dbo.Customers --from-beginning --max-messages 10'
```

Then use:
```bash
k-topics
k-connector
k-cdc-customers
```

## Monitor Script

Create `monitor.sh`:

```bash
#!/bin/bash
echo "=== Confluent CDC Status ==="
echo ""
echo "Kafka Cluster:"
kubectl get kafka -n confluent
echo ""
echo "Connect Cluster:"
kubectl get connect -n confluent
echo ""
echo "Connector:"
kubectl get connector -n confluent
echo ""
echo "CDC Topics:"
kubectl exec kafka-0 -n confluent -- kafka-topics --list --bootstrap-server localhost:9071 2>/dev/null | grep azure-sqlserver
echo ""
echo "Latest Message:"
kubectl exec kafka-0 -n confluent -- kafka-console-consumer --bootstrap-server localhost:9071 --topic sqlserver.dbo.Customers --from-beginning --max-messages 1 2>/dev/null | python3 -m json.tool
```

Run: `chmod +x monitor.sh && ./monitor.sh`

## No Control Center? No Problem!

You have full visibility and control via CLI. Everything works perfectly!
