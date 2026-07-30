#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../master/config.example"
DATA_DIR="$(cd "$SCRIPT_DIR/../../data" 2>/dev/null || echo "$SCRIPT_DIR/../data")"

if [ -f "$CONFIG_FILE" ]; then
    BROKER_IP=$(grep -E "^(BROKER_IP|LISTEN_IP)=" "$CONFIG_FILE" | head -n 1 | cut -d'=' -f2 | tr -d '\r')
    BROKER_PORT=$(grep -E "^(BROKER_PORT|PORT)=" "$CONFIG_FILE" | head -n 1 | cut -d'=' -f2 | tr -d '\r')
    
    if [ -z "$BROKER_IP" ] || [ "$BROKER_IP" == "0.0.0.0" ]; then BROKER_IP="127.0.0.1"; fi
    if [ -z "$BROKER_PORT" ]; then BROKER_PORT="1883"; fi
else
    BROKER_IP="127.0.0.1"
    BROKER_PORT="1883"
fi

SENSORS=$(cat "$DATA_DIR"/*.csv 2>/dev/null | grep -v "sensor_id" | awk -F',' '{print $2" "$1}' | sort -u)

if [ -z "$SENSORS" ]; then
    echo "Error: No sensor data found in $DATA_DIR/*.csv"
    exit 1
fi

request_sensor() {
    TYPE=$1
    ID=$2
    ROUND=$3

    echo "--- Round $ROUND: Requesting $TYPE (ID: $ID) ---"
    mosquitto_sub -h "$BROKER_IP" -p "$BROKER_PORT" -t "gateway/response/$TYPE/$ID" -C 1 > temp_resp.json &
    SUB_PID=$!
    sleep 0.1
    
    START_TIME=$(date +%s%3N)

    mosquitto_pub -h "$BROKER_IP" -p "$BROKER_PORT" -t "gateway/request/$TYPE/$ID" -m ""
   
    wait $SUB_PID 2>/dev/null
    
    END_TIME=$(date +%s%3N)
    DURATION=$((END_TIME - START_TIME))
    
    echo "Payload: $(cat temp_resp.json 2>/dev/null)"
    echo "Total Operator Time: $DURATION ms"
    echo ""
}

echo "======================================"
echo "    MQTT SENSOR QUERY BENCHMARK       "
echo "======================================"
echo "Broker Target: $BROKER_IP:$BROKER_PORT"

echo -e "\n>>> STARTING ROUND 1: COLD CACHE (Database Reads) <<<"
while read -r TYPE ID; do
    request_sensor "$TYPE" "$ID" 1
done <<< "$SENSORS"

echo "Waiting 3 seconds before Round 2 to let the network settle..."
sleep 3

echo -e "\n>>> STARTING ROUND 2: WARM CACHE (Memcached RAM Reads) <<<"
while read -r TYPE ID; do
    request_sensor "$TYPE" "$ID" 2
done <<< "$SENSORS"

rm -f temp_resp.json