#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$(cd "$SCRIPT_DIR/../../data" 2>/dev/null || echo "$SCRIPT_DIR/../data")" 
CONFIG_FILE="$SCRIPT_DIR/../master/config.example" 

if [ -f "$CONFIG_FILE" ]; then
    MASTER_PORT=$(grep "^PORT=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '\r')
    MASTER_IP=$(grep "^LISTEN_IP=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '\r')
 
    if [ -z "$MASTER_IP" ] || [ "$MASTER_IP" == "0.0.0.0" ]; then
        MASTER_IP="127.0.0.1"
    fi
else
    MASTER_PORT="8080"
    MASTER_IP="127.0.0.1"
fi

BASE_URL="http://${MASTER_IP}:${MASTER_PORT}/api/sensor"

echo "================================================================"
echo "    BENCHMARK TEST: SQLite vs Memcached (RAM)"
echo "================================================================"
echo "Target API: $BASE_URL"
echo "Reading Data from: $DATA_DIR"

echo -e "\n Clearing Memcached to guarantee Cache Miss for Round 1..."
sudo systemctl restart memcached
sleep 2

SENSORS=$(cat "$DATA_DIR"/*.csv 2>/dev/null | grep -v "sensor_id" | awk -F',' '{print "type="$2"&id="$1}' | sort -u)

if [ -z "$SENSORS" ]; then
    echo "Error: No sensor data found in $DATA_DIR"
    exit 1
fi

TOTAL=$(echo "$SENSORS" | wc -l)
echo "Found $TOTAL unique sensors across Master and Slaves."
echo "================================================================"

run_round() {
    local round_name="$1"
    echo -e "\n  $round_name"
    echo "------------------------------------------------------------------"
    printf "%-30s | %-16s | %s\n" "Sensor Query" "Data Source" "Response Time"
    echo "------------------------------------------------------------------"
    
    local round_start=$(date +%s%3N)

    for query in $SENSORS; do
        local url="${BASE_URL}?${query}"
        local response=$(curl -s "$url")
  
        local source=$(echo "$response" | grep -o '"source":"[^"]*"' | cut -d'"' -f4)
        local time_ms=$(echo "$response" | grep -o '"[a-z_]*response_time_ms":[0-9.]*' | cut -d':' -f2)
        
        if [ -z "$source" ]; then source="Error/NotFound"; fi
        if [ -z "$time_ms" ]; then time_ms="N/A"; fi
        
        printf "%-30s | %-16s | %s ms\n" "$query" "$source" "$time_ms"
    done

    local round_end=$(date +%s%3N)
    local total_time=$((round_end - round_start))
    
    echo "------------------------------------------------------------------"
    echo "Total Time for $round_name: $total_time ms"
    echo "================================================================"
}

run_round "ROUND 1: Cache Miss (Reads from SQLite & Network)"

echo -e "\n Waiting 2 seconds before Round 2...\n"
sleep 2

run_round "ROUND 2: Cache Hit (Reads from Memcached RAM)"