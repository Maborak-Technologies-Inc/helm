#!/bin/bash

# Script to generate workload on all UI pods for testing
# Usage: ./test-ui-pods.sh [cpu|memory|both] [duration_seconds]

NAMESPACE="automated"
TEST_TYPE="${1:-both}"  # cpu, memory, or both
DURATION="${2:-60}"     # Duration in seconds

echo "=== UI Pods Workload Test ==="
echo "Test Type: $TEST_TYPE"
echo "Duration: ${DURATION}s"
echo ""

# Get all running UI pods
PODS=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep "\-ui-" | grep Running | awk '{print $1}')

if [ -z "$PODS" ]; then
    echo "❌ No running UI pods found!"
    exit 1
fi

POD_COUNT=$(echo "$PODS" | wc -l)
echo "Found $POD_COUNT UI pods to test"
echo ""

# Function to check if stress-ng is available
check_stress_tool() {
    local pod=$1
    kubectl exec -n $NAMESPACE $pod -- which stress-ng >/dev/null 2>&1
    return $?
}

# Function to install stress-ng (if possible)
install_stress_tool() {
    local pod=$1
    echo "Attempting to install stress-ng in $pod..."
    kubectl exec -n $NAMESPACE $pod -- sh -c "apt-get update && apt-get install -y stress-ng" 2>/dev/null || \
    kubectl exec -n $NAMESPACE $pod -- sh -c "apk add --no-cache stress-ng" 2>/dev/null || \
    kubectl exec -n $NAMESPACE $pod -- sh -c "yum install -y stress-ng" 2>/dev/null
}

# Function to generate CPU load
generate_cpu_load() {
    local pod=$1
    local duration=$2
    
    echo "  🔥 Generating CPU load on $pod..."
    
    # Try stress-ng first
    if check_stress_tool $pod; then
        kubectl exec -n $NAMESPACE $pod -- stress-ng --cpu 1 --timeout ${duration}s --metrics-brief >/dev/null 2>&1 &
    else
        # Fallback: use dd to generate CPU load
        kubectl exec -n $NAMESPACE $pod -- sh -c "timeout ${duration}s sh -c 'while true; do dd if=/dev/zero of=/dev/null bs=1M count=100 2>/dev/null; done'" >/dev/null 2>&1 &
    fi
}

# Function to generate memory load
generate_memory_load() {
    local pod=$1
    local duration=$2
    local mem_size="500M"  # Use 500MB to stay under 1Gi limit
    
    echo "  💾 Generating memory load on $pod..."
    
    # Try stress-ng first
    if check_stress_tool $pod; then
        kubectl exec -n $NAMESPACE $pod -- stress-ng --vm 1 --vm-bytes $mem_size --timeout ${duration}s --metrics-brief >/dev/null 2>&1 &
    else
        # Fallback: use dd to allocate memory
        kubectl exec -n $NAMESPACE $pod -- sh -c "timeout ${duration}s sh -c 'while true; do dd if=/dev/zero of=/tmp/stress bs=1M count=500 2>/dev/null; sleep 1; rm -f /tmp/stress; done'" >/dev/null 2>&1 &
    fi
}

# Start monitoring in background
monitor_pods() {
    echo ""
    echo "=== Monitoring Resource Usage ==="
    while true; do
        clear
        echo "=== UI Pods Resource Usage (Press Ctrl+C to stop monitoring) ==="
        echo ""
        kubectl top pods -n $NAMESPACE --no-headers 2>/dev/null | grep "\-ui-" | \
            awk '{printf "%-50s %8s %10s\n", $1, $2, $3}' | \
            head -20
        echo ""
        echo "Total cluster usage:"
        kubectl top node --no-headers 2>/dev/null | \
            awk '{cpu+=$2; mem+=$3} END {printf "  CPU: %dm (%.2f cores)\n  Memory: %dMi (%.2fGi)\n", cpu, cpu/1000, mem, mem/1024}'
        sleep 2
    done
}

# Start monitoring in background
monitor_pids=()
(monitor_pods) &
MONITOR_PID=$!

# Generate workload on all pods
echo "Starting workload generation..."
echo ""

PIDS=()
for pod in $PODS; do
    case $TEST_TYPE in
        cpu)
            generate_cpu_load $pod $DURATION
            ;;
        memory)
            generate_memory_load $pod $DURATION
            ;;
        both)
            generate_cpu_load $pod $DURATION
            generate_memory_load $pod $DURATION
            ;;
    esac
    sleep 0.1  # Small delay to avoid overwhelming
done

echo ""
echo "✅ Workload generation started on all pods"
echo "⏱️  Test will run for ${DURATION} seconds"
echo "📊 Monitoring is running (PID: $MONITOR_PID)"
echo ""
echo "Press Ctrl+C to stop monitoring early (workload will continue for ${DURATION}s)"
echo ""

# Wait for duration
sleep $DURATION

# Stop monitoring
kill $MONITOR_PID 2>/dev/null

echo ""
echo "=== Test Complete ==="
echo ""
echo "Final resource usage:"
kubectl top pods -n $NAMESPACE --no-headers 2>/dev/null | grep "\-ui-" | \
    awk '{cpu+=$2; mem+=$3; count++} END {
        if(count>0) {
            printf "  Total UI Pods: %d\n", count
            printf "  Total CPU: %dm (%.2f cores)\n", cpu, cpu/1000
            printf "  Total Memory: %dMi (%.2fGi)\n", mem, mem/1024
        }
    }'

echo ""
echo "Top 10 UI pods by resource usage:"
kubectl top pods -n $NAMESPACE --no-headers 2>/dev/null | grep "\-ui-" | \
    sort -k3 -rn | head -10 | \
    awk '{printf "  %-50s %8s %10s\n", $1, $2, $3}'

