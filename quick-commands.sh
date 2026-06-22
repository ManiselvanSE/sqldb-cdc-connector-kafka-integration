#!/bin/bash
# Quick Reference Commands for Debezium SQL Server Connector

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

NAMESPACE="confluent"

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check Prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found"
        exit 1
    fi
    print_success "kubectl found"

    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        print_error "Namespace $NAMESPACE not found"
        exit 1
    fi
    print_success "Namespace $NAMESPACE exists"
}

# Check Connect Cluster Status
check_connect() {
    print_header "Kafka Connect Cluster Status"
    kubectl get connect -n $NAMESPACE

    POD_STATUS=$(kubectl get pod connect-0 -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$POD_STATUS" == "Running" ]; then
        print_success "Connect cluster is running"
    else
        print_error "Connect cluster status: $POD_STATUS"
    fi
}

# List Connector Plugins
list_plugins() {
    print_header "Available Connector Plugins"
    kubectl exec -n $NAMESPACE connect-0 -- curl -s localhost:8083/connector-plugins | python3 -m json.tool | grep -E '"class"|"version"' | head -20
}

# Check Debezium Plugin
check_debezium_plugin() {
    print_header "Debezium SQL Server Plugin"
    if kubectl exec -n $NAMESPACE connect-0 -- curl -s localhost:8083/connector-plugins | grep -q "SqlServerConnector"; then
        print_success "Debezium SQL Server connector plugin is installed"
        kubectl exec -n $NAMESPACE connect-0 -- curl -s localhost:8083/connector-plugins | python3 -m json.tool | grep -A 3 -i sqlserver
    else
        print_error "Debezium SQL Server connector plugin not found"
    fi
}

# Deploy Connector
deploy_connector() {
    print_header "Deploying Debezium Connector"

    if [ -f "sqlserver-connector.yaml" ]; then
        kubectl apply -f sqlserver-connector.yaml
        print_success "Connector deployment initiated"

        print_warning "Waiting 10 seconds for connector to initialize..."
        sleep 10
        check_connector
    else
        print_error "sqlserver-connector.yaml not found"
        exit 1
    fi
}

# Check Connector Status
check_connector() {
    print_header "Connector Status"
    kubectl get connector -n $NAMESPACE

    echo ""
    print_header "Connector Details"
    kubectl describe connector sqlserver-debezium-connector -n $NAMESPACE 2>/dev/null || print_warning "Connector not found"
}

# View Connector Logs
view_logs() {
    print_header "Connector Logs (last 50 lines)"
    kubectl logs -n $NAMESPACE connect-0 --tail=50 | grep -i debezium || print_warning "No Debezium logs found yet"
}

# Follow Logs
follow_logs() {
    print_header "Following Connect Logs (Ctrl+C to stop)"
    kubectl logs -n $NAMESPACE connect-0 -f
}

# List Kafka Topics
list_topics() {
    print_header "Kafka Topics (Debezium)"
    kubectl exec -it kafka-0 -n $NAMESPACE -- kafka-topics --list --bootstrap-server localhost:9071 2>/dev/null | grep -E "azure-sqlserver|schema-changes" || print_warning "No Debezium topics found yet"
}

# Consume Messages
consume_topic() {
    TOPIC=${1:-"azure-sqlserver.dbo.Customers"}
    MAX_MSG=${2:-10}

    print_header "Consuming from Topic: $TOPIC (max $MAX_MSG messages)"
    kubectl exec -it kafka-0 -n $NAMESPACE -- kafka-console-consumer \
        --bootstrap-server localhost:9071 \
        --topic "$TOPIC" \
        --from-beginning \
        --max-messages $MAX_MSG 2>/dev/null || print_error "Failed to consume from topic"
}

# Delete Connector
delete_connector() {
    print_header "Deleting Connector"
    read -p "Are you sure you want to delete the connector? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete connector sqlserver-debezium-connector -n $NAMESPACE
        print_success "Connector deleted"
    else
        print_warning "Deletion cancelled"
    fi
}

# Full Status Check
full_status() {
    check_prerequisites
    check_connect
    check_debezium_plugin
    check_connector
    list_topics
}

# Show Help
show_help() {
    cat << EOF
Debezium SQL Server Connector - Quick Commands

Usage: ./quick-commands.sh [command]

Commands:
    status          - Full status check (Connect + Connector + Topics)
    connect         - Check Kafka Connect cluster status
    plugins         - List all connector plugins
    debezium        - Check Debezium plugin installation
    deploy          - Deploy the Debezium connector
    connector       - Check connector status
    logs            - View connector logs (last 50 lines)
    follow          - Follow connector logs in real-time
    topics          - List Debezium-related Kafka topics
    consume [topic] - Consume messages from a topic (default: Customers)
    delete          - Delete the connector
    help            - Show this help message

Examples:
    ./quick-commands.sh status
    ./quick-commands.sh deploy
    ./quick-commands.sh consume azure-sqlserver.dbo.Orders
    ./quick-commands.sh logs

EOF
}

# Main Script
case "${1:-help}" in
    status)
        full_status
        ;;
    connect)
        check_connect
        ;;
    plugins)
        list_plugins
        ;;
    debezium)
        check_debezium_plugin
        ;;
    deploy)
        deploy_connector
        ;;
    connector)
        check_connector
        ;;
    logs)
        view_logs
        ;;
    follow)
        follow_logs
        ;;
    topics)
        list_topics
        ;;
    consume)
        consume_topic "$2" "$3"
        ;;
    delete)
        delete_connector
        ;;
    help|*)
        show_help
        ;;
esac
