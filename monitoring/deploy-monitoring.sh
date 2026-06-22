#!/bin/bash

# Monitoring Stack Deployment Script
# Deploys Prometheus, Grafana, and configures monitoring for Debezium CDC

set -e

echo "=== Debezium CDC Monitoring Stack Deployment ==="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install kubectl first."
    exit 1
fi

print_status "kubectl found"

# Create monitoring namespace
echo ""
echo "Step 1: Creating monitoring namespace..."
kubectl create namespace monitoring 2>/dev/null || print_warning "Namespace 'monitoring' already exists"
print_status "Monitoring namespace ready"

# Install Prometheus Operator CRDs
echo ""
echo "Step 2: Installing Prometheus Operator CRDs..."
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
print_status "CRDs installed"

# Deploy Prometheus Operator
echo ""
echo "Step 3: Deploying Prometheus Operator..."
kubectl apply -f prometheus-operator.yaml
sleep 5
print_status "Prometheus Operator deployed"

# Deploy Prometheus Instance
echo ""
echo "Step 4: Deploying Prometheus instance..."
kubectl apply -f prometheus-instance.yaml
echo "Waiting for Prometheus to be ready (this may take 1-2 minutes)..."
kubectl wait --for=condition=Ready prometheus/confluent-monitoring -n monitoring --timeout=300s 2>/dev/null || print_warning "Prometheus may still be starting"
print_status "Prometheus deployed"

# Deploy Grafana
echo ""
echo "Step 5: Deploying Grafana..."
kubectl apply -f grafana.yaml
echo "Waiting for Grafana to be ready..."
kubectl wait --for=condition=Available deployment/grafana -n monitoring --timeout=180s 2>/dev/null || print_warning "Grafana may still be starting"
print_status "Grafana deployed"

# Deploy ServiceMonitors
echo ""
echo "Step 6: Configuring ServiceMonitors..."
kubectl apply -f servicemonitors.yaml
print_status "ServiceMonitors configured"

# Deploy Alert Rules
echo ""
echo "Step 7: Deploying alert rules..."
kubectl apply -f prometheus-rules.yaml
print_status "Alert rules deployed"

# Wait for all pods to be ready
echo ""
echo "Step 8: Waiting for all monitoring pods to be ready..."
sleep 10
kubectl get pods -n monitoring

# Get access URLs
echo ""
echo "=========================================="
echo "🎉 Monitoring Stack Deployed Successfully!"
echo "=========================================="
echo ""

# Get Prometheus URL
PROM_SVC=$(kubectl get svc prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
if [ -z "$PROM_SVC" ]; then
    PROM_SVC=$(kubectl get svc prometheus -n monitoring -o jsonpath='{.spec.clusterIP}')
    print_warning "Prometheus using ClusterIP (LoadBalancer pending)"
    echo "Prometheus: http://$PROM_SVC:9090 (cluster-internal)"
else
    echo "✅ Prometheus: http://$PROM_SVC:9090"
fi

# Get Grafana URL
GRAFANA_SVC=$(kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
if [ -z "$GRAFANA_SVC" ]; then
    GRAFANA_SVC=$(kubectl get svc grafana -n monitoring -o jsonpath='{.spec.clusterIP}')
    print_warning "Grafana using ClusterIP (LoadBalancer pending)"
    echo "Grafana: http://$GRAFANA_SVC:3000 (cluster-internal)"
else
    echo "✅ Grafana: http://$GRAFANA_SVC:3000"
fi

echo ""
echo "📊 Grafana Login:"
echo "   Username: admin"
echo "   Password: admin"
echo ""

echo "Next Steps:"
echo "1. Access Grafana and change the default password"
echo "2. Import dashboard: dashboard-debezium-overview.json"
echo "3. Check Prometheus targets: http://$PROM_SVC:9090/targets"
echo "4. Verify alerts: http://$PROM_SVC:9090/alerts"
echo ""

# Check if metrics endpoints are accessible
echo "Verifying metrics endpoints..."
echo ""

# Check Kafka metrics
if kubectl exec kafka-0 -n confluent -- curl -s localhost:7778/metrics &>/dev/null; then
    print_status "Kafka metrics endpoint accessible"
else
    print_warning "Kafka metrics not accessible - may need to enable JMX exporter"
    echo "   Run: kubectl edit kafka kafka -n confluent"
    echo "   Add metrics configuration (see MONITORING-SETUP.md)"
fi

# Check Connect metrics
if kubectl exec connect-0 -n confluent -- curl -s localhost:7778/metrics &>/dev/null; then
    print_status "Connect metrics endpoint accessible"
else
    print_warning "Connect metrics not accessible - may need to enable JMX exporter"
    echo "   Run: kubectl edit connect connect -n confluent"
    echo "   Add metrics configuration (see MONITORING-SETUP.md)"
fi

echo ""
echo "=========================================="
echo "For detailed configuration, see:"
echo "  monitoring/MONITORING-SETUP.md"
echo "=========================================="
