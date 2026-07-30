#!/bin/bash
echo "=========================================="
echo "    SNMP SENSOR NETWORK MONITORING        "
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$SCRIPT_DIR/../data" ]; then
    DATA_DIR="$(cd "$SCRIPT_DIR/../data" && pwd)"
elif [ -d "$SCRIPT_DIR/../../data" ]; then
    DATA_DIR="$(cd "$SCRIPT_DIR/../../data" && pwd)"
elif [ -d "$SCRIPT_DIR/data" ]; then
    DATA_DIR="$(cd "$SCRIPT_DIR/data" && pwd)"
else
    echo "Error: Cannot find the 'data' folder!"
    echo "I am running from: $SCRIPT_DIR"
    echo "I looked for the data folder in these 3 places:"
    echo "  1. $SCRIPT_DIR/../data"
    echo "  2. $SCRIPT_DIR/../../data"
    echo "  3. $SCRIPT_DIR/data"
    echo ""
    echo "Fix: Please copy your 'data' folder containing the CSV files into one of those locations!"
    exit 1
fi

echo "Found data folder at: $DATA_DIR"

SENSOR_IDS=$(cat "$DATA_DIR"/*.csv 2>/dev/null | grep -v "sensor_id" | awk -F',' '{print $1}' | sort -n -u)

if [ -z "$SENSOR_IDS" ]; then
    echo " Error: Found the folder, but couldn't find any CSV files inside it, or they are empty."
    exit 1
fi

TOTAL=$(echo "$SENSOR_IDS" | wc -w)
echo " Dynamically detected $TOTAL unique sensors to test."
echo "------------------------------------------"

for sensor in $SENSOR_IDS; do
    echo ">>> Fetching Sensor $sensor via Custom OID..."
    snmpwalk -v2c -c public localhost .1.3.6.1.4.1.9999.$sensor
    echo ""
done

echo "Done! All network sensors retrieved via Gateway."