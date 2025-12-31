#!/bin/bash

# Simple script to generate workload on UI pods using basic tools
# This version doesn't require stress-ng

NAMESPACE="automated"
DURATION="${1:-60}"  # Duration in seconds

echo "=== Simple UI Pods Workload Test ==="
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

# Function to generate CPU load using simple math operations
generate_cpu_load() {
    local pod=$1
    local duration=$2
    
    echo "  🔥 Generating CPU load on $pod..."
    kubectl exec -n $NAMESPACE $pod -- sh -c "
        timeout ${duration}s sh -c '
            while true; do
                # Simple CPU-intensive loop
                i=0
                while [ \$i -lt 100000 ]; do
                    i=\$((i+1))
                done
            done
        ' &
    " >/dev/null 2>&1 &
}

# Function to generate memory load
generate_memory_load() {
    local pod=$1
    local duration=$2
    
    echo "  💾 Generating memory load on $pod..."
    kubectl exec -n $NAMESPACE $pod -- sh -c "
        timeout ${duration}s sh -c '
            # Allocate ~400MB of memory (staying under 1Gi limit)
            dd if=/dev/zero of=/tmp/stress_mem bs=1M count=400 2>/dev/null
            sleep \$(($duration - 2))
            rm -f /tmp/stress_mem
        ' &
    " >/dev/null 2>&1 &
}

echo "Starting workload generation..."
echo ""

for pod in $PODS; do
    generate_cpu_load $pod $DURATION
    generate_memory_load $pod $DURATION
    sleep 0.1
done

echo ""
echo "✅ Workload generation started on all pods"
echo "⏱️  Test will run for ${DURATION} seconds"
echo ""
echo "Monitoring resource usage (updates every 5 seconds)..."
echo ""

# Function to display node info (fetches fresh data each time)
display_node_info() {
    # Get fresh node data
    local NODES_DATA=$(kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory --no-headers 2>/dev/null)
    local NODES_TOP=$(kubectl top node --no-headers 2>/dev/null)
    
    echo "=== NODE RESOURCES ==="
    echo ""
    
    # Get node capacity
    echo "Node Capacity:"
    echo "$NODES_DATA" | while read name cpu_raw mem_raw; do
        # Convert memory from Ki to Gi
        mem_gi=$(echo "$mem_raw" | sed 's/Ki//' | awk '{printf "%.2f", $1/1024/1024}')
        printf "  %-25s CPU: %3s cores  Memory: %6sGi\n" "$name" "$cpu_raw" "$mem_gi"
    done
    
    echo ""
    echo "Current Node Usage:"
    echo "$NODES_TOP" | while read name cpu_raw cpu_pct mem_raw mem_pct; do
        cpu_cores=$(echo "$cpu_raw" | sed 's/m//' | awk '{printf "%.2f", $1/1000}')
        mem_gi=$(echo "$mem_raw" | sed 's/Mi//' | awk '{printf "%.2f", $1/1024}')
        printf "  %-25s CPU: %6s cores (%5s%%)  Memory: %6sGi (%5s%%)\n" \
            "$name" "$cpu_cores" "$cpu_pct" "$mem_gi" "$mem_pct"
    done
    
    # Calculate totals
    echo ""
    echo "Cluster Totals:"
    # Get total capacity
    echo "$NODES_DATA" | \
        awk '{
            cpu_total += $2
            mem_ki = $3
            gsub(/Ki/, "", mem_ki)
            mem_total_ki += mem_ki
        } END {
            printf "  Total Capacity: %d CPU cores, %.2fGi memory\n", cpu_total, mem_total_ki/1024/1024
        }'
    
    # Get current usage
    echo "$NODES_TOP" | \
        awk '{
            cpu_m = $2
            mem_mi = $3
            gsub(/m/, "", cpu_m)
            gsub(/Mi/, "", mem_mi)
            cpu_total_m += cpu_m
            mem_total_mi += mem_mi
        } END {
            printf "  Current Usage: %.2f CPU cores, %.2fGi memory\n", cpu_total_m/1000, mem_total_mi/1024
        }'
    echo ""
}

# Monitor for the duration
for i in $(seq 1 $DURATION); do
    if [ $((i % 5)) -eq 0 ] || [ $i -eq 1 ]; then
        # Get fresh data each time (this ensures we see updates)
        PODS_JSON=$(kubectl get pods -n $NAMESPACE -o json 2>/dev/null)
        PODS_METRICS=$(kubectl top pods -n $NAMESPACE --no-headers 2>/dev/null | grep "\-ui-")
        
        clear
        echo "=== UI Pods Workload Test (${i}/${DURATION}s) ==="
        echo ""
        
        # Display node information (also gets fresh data)
        display_node_info
        
        echo "=== UI PODS RESOURCE USAGE ==="
        echo ""
        printf "%-50s %-40s %-40s\n" "Pod Name" "CPU (Request/Limit/Used)" "Memory (Request/Limit/Used)"
        echo "────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
        
        # Get pod resource info and current usage
        echo "$PODS_JSON" | jq -r '.items[] | select(.metadata.name | contains("-ui-")) | select(.status.phase == "Running") | .metadata.name' | head -15 | while read pod; do
            # Get resource requests and limits from cached JSON
            cpu_req=$(echo "$PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.requests.cpu // "0"')
            cpu_limit=$(echo "$PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.limits.cpu // "0"')
            mem_req=$(echo "$PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.requests.memory // "0"')
            mem_limit=$(echo "$PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.limits.memory // "0"')
            
            # Get current usage from cached metrics
            cpu_used=$(echo "$PODS_METRICS" | grep "^$pod " | awk '{print $2}' || echo "0m")
            mem_used=$(echo "$PODS_METRICS" | grep "^$pod " | awk '{print $3}' || echo "0Mi")
            
            # Convert CPU to millicores for percentage calculation
            if [[ "$cpu_req" =~ m$ ]]; then
                cpu_req_m=$(echo "$cpu_req" | sed 's/m//')
            elif [[ "$cpu_req" =~ ^[0-9.]+$ ]]; then
                cpu_req_m=$(echo "$cpu_req" | awk '{printf "%.0f", $1*1000}')
            else
                cpu_req_m=0
                cpu_req="0"
            fi
            
            if [[ "$cpu_limit" =~ m$ ]]; then
                cpu_limit_m=$(echo "$cpu_limit" | sed 's/m//')
            elif [[ "$cpu_limit" =~ ^[0-9.]+$ ]]; then
                cpu_limit_m=$(echo "$cpu_limit" | awk '{printf "%.0f", $1*1000}')
            else
                cpu_limit_m=0
                cpu_limit="0"
            fi
            
            cpu_used_m=$(echo "$cpu_used" | sed 's/m//' || echo "0")
            
            # Convert Memory to Mi for display
            if [[ "$mem_req" =~ Mi$ ]]; then
                mem_req_mi=$(echo "$mem_req" | sed 's/Mi//')
            elif [[ "$mem_req" =~ Gi$ ]]; then
                mem_req_mi=$(echo "$mem_req" | sed 's/Gi//' | awk '{printf "%.0f", $1*1024}')
            else
                mem_req_mi=0
                mem_req="0"
            fi
            
            if [[ "$mem_limit" =~ Mi$ ]]; then
                mem_limit_mi=$(echo "$mem_limit" | sed 's/Mi//')
            elif [[ "$mem_limit" =~ Gi$ ]]; then
                mem_limit_mi=$(echo "$mem_limit" | sed 's/Gi//' | awk '{printf "%.0f", $1*1024}')
            else
                mem_limit_mi=0
                mem_limit="0"
            fi
            
            mem_used_mi=$(echo "$mem_used" | sed 's/Mi//' || echo "0")
            
            # Format display - show "Used/Limit"
            if [ "$cpu_used" = "N/A" ] || [ -z "$cpu_used" ]; then
                cpu_used="0m"
                cpu_used_m=0
            fi
            
            if [ "$mem_used" = "N/A" ] || [ -z "$mem_used" ]; then
                mem_used="0Mi"
                mem_used_mi=0
            fi
            
            # Format CPU: "Req:100m Lim:1 Used:1m/1000m"
            cpu_display="Req:${cpu_req} Lim:${cpu_limit} Used:${cpu_used_m}m/${cpu_limit_m}m"
            
            # Format Memory: "Req:256Mi Lim:1Gi Used:43Mi/1024Mi"
            mem_display="Req:${mem_req} Lim:${mem_limit} Used:${mem_used_mi}Mi/${mem_limit_mi}Mi"
            
            printf "%-50s %-40s %-40s\n" "$pod" "$cpu_display" "$mem_display"
        done
        
        echo ""
        # Calculate totals - use cached data, calculate in one pass
        total_cpu_req=0
        total_cpu_limit=0
        total_cpu_used=0
        total_mem_req=0
        total_mem_limit=0
        total_mem_used=0
        pod_count=0
        
        # Process all pods using cached data - use grep for metrics lookup (faster than associative arrays in subshell)
        while IFS= read -r pod; do
            cpu_req=$(echo "$PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.requests.cpu // "0"')
            cpu_limit=$(echo "$PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.limits.cpu // "0"')
            mem_req=$(echo "$PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.requests.memory // "0"')
            mem_limit=$(echo "$PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.limits.memory // "0"')
            cpu_used=$(echo "$PODS_METRICS" | grep "^$pod " | awk '{print $2}' || echo "0m")
            mem_used=$(echo "$PODS_METRICS" | grep "^$pod " | awk '{print $3}' || echo "0Mi")
            
            # Convert CPU request to millicores
            if [[ "$cpu_req" =~ m$ ]]; then
                cpu_req_m=$(echo "$cpu_req" | sed 's/m//')
            elif [[ "$cpu_req" =~ ^[0-9]+$ ]]; then
                cpu_req_m=$((cpu_req * 1000))
            else
                cpu_req_m=0
            fi
            
            # Convert CPU limit to millicores
            if [[ "$cpu_limit" =~ m$ ]]; then
                cpu_limit_m=$(echo "$cpu_limit" | sed 's/m//')
            elif [[ "$cpu_limit" =~ ^[0-9]+$ ]]; then
                cpu_limit_m=$((cpu_limit * 1000))
            else
                cpu_limit_m=0
            fi
            
            # Convert CPU used to millicores
            cpu_used_m=$(echo "$cpu_used" | sed 's/m//' || echo "0")
            
            # Convert Memory request to Mi
            if [[ "$mem_req" =~ Mi$ ]]; then
                mem_req_mi=$(echo "$mem_req" | sed 's/Mi//')
            elif [[ "$mem_req" =~ Gi$ ]]; then
                mem_req_mi=$(echo "$mem_req" | sed 's/Gi//' | awk '{print int($1*1024)}')
            else
                mem_req_mi=0
            fi
            
            # Convert Memory limit to Mi
            if [[ "$mem_limit" =~ Mi$ ]]; then
                mem_limit_mi=$(echo "$mem_limit" | sed 's/Mi//')
            elif [[ "$mem_limit" =~ Gi$ ]]; then
                mem_limit_mi=$(echo "$mem_limit" | sed 's/Gi//' | awk '{print int($1*1024)}')
            else
                mem_limit_mi=0
            fi
            
            # Convert Memory used to Mi
            mem_used_mi=$(echo "$mem_used" | sed 's/Mi//' || echo "0")
            
            # Use temp file to accumulate totals (avoid subshell variable issues)
            echo "$cpu_req_m|$cpu_limit_m|$cpu_used_m|$mem_req_mi|$mem_limit_mi|$mem_used_mi" >> /tmp/pod_totals_$$
        done
        
        # Calculate totals from temp file
        if [ -f /tmp/pod_totals_$$ ]; then
            while IFS='|' read -r cpu_req_m cpu_limit_m cpu_used_m mem_req_mi mem_limit_mi mem_used_mi; do
                total_cpu_req=$((total_cpu_req + cpu_req_m))
                total_cpu_limit=$((total_cpu_limit + cpu_limit_m))
                total_cpu_used=$((total_cpu_used + cpu_used_m))
                total_mem_req=$((total_mem_req + mem_req_mi))
                total_mem_limit=$((total_mem_limit + mem_limit_mi))
                total_mem_used=$((total_mem_used + mem_used_mi))
                pod_count=$((pod_count + 1))
            done < /tmp/pod_totals_$$
            rm -f /tmp/pod_totals_$$
        fi
        
        if [ $pod_count -gt 0 ]; then
            printf "────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────\n"
            printf "Total UI Pods: %d\n" $pod_count
            printf "  CPU - Requested: %dm (%.2f cores) | Limit: %dm (%.2f cores) | Used: %dm/%dm\n" \
                $total_cpu_req $(echo "$total_cpu_req" | awk '{printf "%.2f", $1/1000}') \
                $total_cpu_limit $(echo "$total_cpu_limit" | awk '{printf "%.2f", $1/1000}') \
                $total_cpu_used $total_cpu_limit
            printf "  Memory - Requested: %dMi (%.2fGi) | Limit: %dMi (%.2fGi) | Used: %dMi/%dMi\n" \
                $total_mem_req $(echo "$total_mem_req" | awk '{printf "%.2f", $1/1024}') \
                $total_mem_limit $(echo "$total_mem_limit" | awk '{printf "%.2f", $1/1024}') \
                $total_mem_used $total_mem_limit
        fi
    fi
    sleep 1
done

echo ""
echo "=== Test Complete ==="
echo ""

# Final node status
echo "=== FINAL NODE STATUS ==="
echo ""
display_node_info

# Final UI pods summary
echo "=== FINAL UI PODS SUMMARY ==="
echo ""

# Calculate totals for all UI pods
total_cpu_req=0
total_cpu_limit=0
total_cpu_used=0
total_mem_req=0
total_mem_limit=0
total_mem_used=0
pod_count=0

for pod in $(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep "\-ui-" | grep Running | awk '{print $1}'); do
    cpu_req=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "0")
    cpu_limit=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "0")
    mem_req=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "0")
    mem_limit=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "0")
    cpu_used=$(kubectl top pod $pod -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $2}' || echo "0m")
    mem_used=$(kubectl top pod $pod -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $3}' || echo "0Mi")
    
    # Convert CPU request to millicores
    if [[ "$cpu_req" =~ m$ ]]; then
        cpu_req_m=$(echo "$cpu_req" | sed 's/m//')
    elif [[ "$cpu_req" =~ ^[0-9.]+$ ]]; then
        cpu_req_m=$(echo "$cpu_req" | awk '{printf "%.0f", $1*1000}')
    else
        cpu_req_m=0
    fi
    
    # Convert CPU limit to millicores
    if [[ "$cpu_limit" =~ m$ ]]; then
        cpu_limit_m=$(echo "$cpu_limit" | sed 's/m//')
    elif [[ "$cpu_limit" =~ ^[0-9.]+$ ]]; then
        cpu_limit_m=$(echo "$cpu_limit" | awk '{printf "%.0f", $1*1000}')
    else
        cpu_limit_m=0
    fi
    
    # Convert CPU used to millicores
    cpu_used_m=$(echo "$cpu_used" | sed 's/m//' || echo "0")
    
    # Convert Memory request to Mi
    if [[ "$mem_req" =~ Mi$ ]]; then
        mem_req_mi=$(echo "$mem_req" | sed 's/Mi//')
    elif [[ "$mem_req" =~ Gi$ ]]; then
        mem_req_mi=$(echo "$mem_req" | sed 's/Gi//' | awk '{printf "%.0f", $1*1024}')
    else
        mem_req_mi=0
    fi
    
    # Convert Memory limit to Mi
    if [[ "$mem_limit" =~ Mi$ ]]; then
        mem_limit_mi=$(echo "$mem_limit" | sed 's/Mi//')
    elif [[ "$mem_limit" =~ Gi$ ]]; then
        mem_limit_mi=$(echo "$mem_limit" | sed 's/Gi//' | awk '{printf "%.0f", $1*1024}')
    else
        mem_limit_mi=0
    fi
    
    # Convert Memory used to Mi
    mem_used_mi=$(echo "$mem_used" | sed 's/Mi//' || echo "0")
    
    # Write to temp file to accumulate totals
    echo "$cpu_req_m|$cpu_limit_m|$cpu_used_m|$mem_req_mi|$mem_limit_mi|$mem_used_mi" >> "$TEMP_FILE"
done

# Calculate totals from temp file
total_cpu_req=0
total_cpu_limit=0
total_cpu_used=0
total_mem_req=0
total_mem_limit=0
total_mem_used=0
pod_count=0

if [ -f "$TEMP_FILE" ]; then
    while IFS='|' read -r cpu_req_m cpu_limit_m cpu_used_m mem_req_mi mem_limit_mi mem_used_mi; do
        total_cpu_req=$((total_cpu_req + cpu_req_m))
        total_cpu_limit=$((total_cpu_limit + cpu_limit_m))
        total_cpu_used=$((total_cpu_used + cpu_used_m))
        total_mem_req=$((total_mem_req + mem_req_mi))
        total_mem_limit=$((total_mem_limit + mem_limit_mi))
        total_mem_used=$((total_mem_used + mem_used_mi))
        pod_count=$((pod_count + 1))
    done < "$TEMP_FILE"
    rm -f "$TEMP_FILE"
fi

if [ $pod_count -gt 0 ]; then
    printf "Summary Statistics:\n"
    printf "  Total UI Pods: %d\n" $pod_count
    printf "\n"
    printf "  CPU Resources:\n"
    printf "    Requested: %dm (%.2f cores)\n" $total_cpu_req $(echo "$total_cpu_req" | awk '{printf "%.2f", $1/1000}')
    printf "    Limit: %dm (%.2f cores)\n" $total_cpu_limit $(echo "$total_cpu_limit" | awk '{printf "%.2f", $1/1000}')
    printf "    Used: %dm/%dm\n" $total_cpu_used $total_cpu_limit
    printf "\n"
    printf "  Memory Resources:\n"
    printf "    Requested: %dMi (%.2fGi)\n" $total_mem_req $(echo "$total_mem_req" | awk '{printf "%.2f", $1/1024}')
    printf "    Limit: %dMi (%.2fGi)\n" $total_mem_limit $(echo "$total_mem_limit" | awk '{printf "%.2f", $1/1024}')
    printf "    Used: %dMi/%dMi\n" $total_mem_used $total_mem_limit
fi

echo ""
echo "Top 10 UI Pods by Memory Usage:"
printf "%-50s %-40s %-40s\n" "Pod Name" "CPU (Request/Limit/Used)" "Memory (Request/Limit/Used)"
echo "────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
# Use cached data for top pods
for pod in $(echo "$FINAL_PODS_METRICS" | sort -k3 -rn | head -10 | awk '{print $1}'); do
    cpu_req=$(echo "$FINAL_PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.requests.cpu // "0"')
    cpu_limit=$(echo "$FINAL_PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.limits.cpu // "0"')
    mem_req=$(echo "$FINAL_PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.requests.memory // "0"')
    mem_limit=$(echo "$FINAL_PODS_JSON" | jq -r --arg pod "$pod" '.items[] | select(.metadata.name == $pod) | .spec.containers[0].resources.limits.memory // "0"')
    cpu_used=$(echo "$FINAL_PODS_METRICS" | grep "^$pod " | awk '{print $2}' || echo "0m")
    mem_used=$(echo "$FINAL_PODS_METRICS" | grep "^$pod " | awk '{print $3}' || echo "0Mi")
    
    # Convert for percentage calculation
    if [[ "$cpu_req" =~ m$ ]]; then
        cpu_req_m=$(echo "$cpu_req" | sed 's/m//')
    elif [[ "$cpu_req" =~ ^[0-9.]+$ ]]; then
        cpu_req_m=$(echo "$cpu_req" | awk '{printf "%.0f", $1*1000}')
    else
        cpu_req_m=0
        cpu_req="0"
    fi
    
    if [[ "$cpu_limit" =~ m$ ]]; then
        cpu_limit_m=$(echo "$cpu_limit" | sed 's/m//')
    elif [[ "$cpu_limit" =~ ^[0-9.]+$ ]]; then
        cpu_limit_m=$(echo "$cpu_limit" | awk '{printf "%.0f", $1*1000}')
    else
        cpu_limit_m=0
        cpu_limit="0"
    fi
    
    cpu_used_m=$(echo "$cpu_used" | sed 's/m//' || echo "0")
    
    if [[ "$mem_req" =~ Mi$ ]]; then
        mem_req_mi=$(echo "$mem_req" | sed 's/Mi//')
    elif [[ "$mem_req" =~ Gi$ ]]; then
        mem_req_mi=$(echo "$mem_req" | sed 's/Gi//' | awk '{printf "%.0f", $1*1024}')
    else
        mem_req_mi=0
        mem_req="0"
    fi
    
    if [[ "$mem_limit" =~ Mi$ ]]; then
        mem_limit_mi=$(echo "$mem_limit" | sed 's/Mi//')
    elif [[ "$mem_limit" =~ Gi$ ]]; then
        mem_limit_mi=$(echo "$mem_limit" | sed 's/Gi//' | awk '{printf "%.0f", $1*1024}')
    else
        mem_limit_mi=0
        mem_limit="0"
    fi
    
    mem_used_mi=$(echo "$mem_used" | sed 's/Mi//' || echo "0")
    
    if [ -z "$cpu_used" ] || [ "$cpu_used" = "N/A" ]; then 
        cpu_used="0m"
        cpu_used_m=0
    fi
    if [ -z "$mem_used" ] || [ "$mem_used" = "N/A" ]; then 
        mem_used="0Mi"
        mem_used_mi=0
    fi
    
    # Format CPU: "Req:100m Lim:1 Used:1m/1000m"
    cpu_display="Req:${cpu_req} Lim:${cpu_limit} Used:${cpu_used_m}m/${cpu_limit_m}m"
    
    # Format Memory: "Req:256Mi Lim:1Gi Used:43Mi/1024Mi"
    mem_display="Req:${mem_req} Lim:${mem_limit} Used:${mem_used_mi}Mi/${mem_limit_mi}Mi"
    
    printf "%-50s %-40s %-40s\n" "$pod" "$cpu_display" "$mem_display"
done

