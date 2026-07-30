#!/bin/bash

SENSOR_ID=$1
CMD=$2
REQ_OID=$(echo "$3" | sed 's/^\.//')
BASE_OID="1.3.6.1.4.1.9999.$SENSOR_ID"


DB_PATH="/var/lib/snmp/master.db"
MAP_FILE="/var/lib/snmp/sensor_map.txt"

reply() {
    echo ".$1"
    echo "string"
    echo "$2"
    exit 0
}

CONFIG_FILE=$(find /home -maxdepth 5 -type f -name "config" -path "*/master/config" 2>/dev/null | head -n 1)

if [ -z "$CONFIG_FILE" ]; then
    reply "$BASE_OID.3" "Error: Config file not found in system"
fi


BROKER_PORT=$(grep -E "^(BROKER_PORT)=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '\r')
BROKER_IP=$(grep -E "^(BROKER_IP)=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '\r')

if [ -z "$BROKER_IP" ] || [ -z "$BROKER_PORT" ]; then
    reply "$BASE_OID.3" "Error: IP or Port missing in config"
fi


MAPPING=$(grep "^$SENSOR_ID," "$MAP_FILE" 2>/dev/null | head -n 1)
TYPE=$(echo "$MAPPING" | cut -d',' -f2)
NAME=$(echo "$MAPPING" | cut -d',' -f3)

[ -z "$TYPE" ] && TYPE="N/A"
[ -z "$NAME" ] && NAME="N/A"


FETCH_VALUE=false
if [ "$CMD" = "-g" ] && [ "$REQ_OID" = "$BASE_OID.3" ]; then FETCH_VALUE=true; fi
if [ "$CMD" = "-n" ] && [ "$REQ_OID" = "$BASE_OID.2" ]; then FETCH_VALUE=true; fi

VALUE="Timeout/Offline"

if [ "$FETCH_VALUE" = true ]; then
    VALUE=$(sqlite3 "$DB_PATH" "SELECT value FROM sensor_readings WHERE sensor_id='$SENSOR_ID' ORDER BY recorded_at DESC LIMIT 1;" 2>&1)


    if [ -z "$VALUE" ] || [[ "$VALUE" == *"Error"* ]]; then
        
        mosquitto_sub -h "$BROKER_IP" -p "$BROKER_PORT" -t "gateway/response/$TYPE/$SENSOR_ID" -C 1 -W 2 > "/tmp/mqtt_resp_${SENSOR_ID}.json" &
        SUB_PID=$!
        sleep 0.1
        mosquitto_pub -h "$BROKER_IP" -p "$BROKER_PORT" -t "gateway/request/$TYPE/$SENSOR_ID" -m ""
        wait $SUB_PID 2>/dev/null
        
        RAW_RESP=$(cat "/tmp/mqtt_resp_${SENSOR_ID}.json" 2>/dev/null)
        rm -f "/tmp/mqtt_resp_${SENSOR_ID}.json"
        
        if [[ "$RAW_RESP" == *"error"* ]] || [ -z "$RAW_RESP" ]; then
            VALUE="Error: Sensor Offline or Missing"
        else
            VALUE=$(echo "$RAW_RESP" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)
        fi
    fi
fi

if [ "$CMD" = "-g" ]; then
    case "$REQ_OID" in
        "$BASE_OID.1") reply "$BASE_OID.1" "Type: $TYPE" ;;
        "$BASE_OID.2") reply "$BASE_OID.2" "Desc: $NAME" ;;
        "$BASE_OID.3") reply "$BASE_OID.3" "Last Value: $VALUE" ;;
        *) exit 0 ;;
    esac
elif [ "$CMD" = "-n" ]; then
    case "$REQ_OID" in
        "$BASE_OID")   reply "$BASE_OID.1" "Type: $TYPE" ;;
        "$BASE_OID.1") reply "$BASE_OID.2" "Desc: $NAME" ;;
        "$BASE_OID.2") reply "$BASE_OID.3" "Last Value: $VALUE" ;;
        *) exit 0 ;;
    esac
fi
exit 0