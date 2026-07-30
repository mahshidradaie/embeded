#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root (sudo bash build_and_run.sh)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MASTER_DIR="$(cd "$SCRIPT_DIR/../master" 2>/dev/null || cd "$SCRIPT_DIR" && pwd)"
DATA_DIR="$(cd "$SCRIPT_DIR/../../data" 2>/dev/null || echo "$SCRIPT_DIR/../data")"

echo "=========================================="
echo "   PART 4: SNMP GATEWAY BUILD & RUN       "
echo "=========================================="

echo ">>> [1/6] Compiling Master Node C++ Code..."
cd "$MASTER_DIR" || exit
make clean >/dev/null 2>&1
make

echo ">>> [2/6] Setting up Configuration..."
if [ ! -f "config" ]; then
    cp config.example config
    echo "    Created config from config.example (No hardcoded IPs)."
fi

BROKER_PORT=$(grep -E "^(BROKER_PORT)=" "$MASTER_DIR/config" | head -n 1 | cut -d'=' -f2 | tr -d '\r')
if [ -z "$BROKER_PORT" ]; then BROKER_PORT=1883; fi

BROKER_IP=$(grep -E "^(BROKER_IP)=" "$MASTER_DIR/config" | head -n 1 | cut -d'=' -f2 | tr -d '\r')
if [ -z "$BROKER_IP" ]; then BROKER_IP="127.0.0.1"; fi

echo ">>> [3/6] Initializing Database..."
chmod +x db_init_master.sh
./db_init_master.sh
echo "    Database built without hardcoded static responses."

echo ">>> [4/6] Installing & Configuring SNMP Dependencies..."
apt-get update -y >/dev/null 2>&1
apt-get install -y snmp snmpd snmp-mibs-downloader sqlite3 mosquitto-clients >/dev/null 2>&1
sed -i 's/^mibs :/#mibs :/g' /etc/snmp/snmp.conf
download-mibs >/dev/null 2>&1

echo ">>> [5/6] Building SNMP Proxy Routing Script Dynamically..."
DB_DEST="/var/lib/snmp/master.db"
if [ -f "$MASTER_DIR/master.db" ]; then
    cp "$MASTER_DIR/master.db" "$DB_DEST"
fi
chown Debian-snmp:Debian-snmp "$DB_DEST" 2>/dev/null || chown snmp:snmp "$DB_DEST"
chmod 666 "$DB_DEST"

MAP_FILE="/var/lib/snmp/sensor_map.txt"
cat /dev/null > "$MAP_FILE"
for csv in "$DATA_DIR"/*.csv; do
    if [ -f "$csv" ]; then
        tail -n +2 "$csv" | awk -F',' '{print $1","$2","$3}' >> "$MAP_FILE"
    fi
done
sort -u "$MAP_FILE" -o "$MAP_FILE"

cat << 'EOF' > /usr/local/bin/read_sensor.sh
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

MAPPING=$(grep "^$SENSOR_ID," "$MAP_FILE" | head -n 1)
TYPE=$(echo "$MAPPING" | cut -d',' -f2)
NAME=$(echo "$MAPPING" | cut -d',' -f3)

VALUE=$(sqlite3 "$DB_PATH" "SELECT value FROM sensor_readings WHERE sensor_id='$SENSOR_ID' ORDER BY recorded_at DESC LIMIT 1;" 2>&1)

if [ -z "$VALUE" ] || [[ "$VALUE" == *"Error"* ]]; then
    
    mosquitto_sub -h "BROKER_IP_PLACEHOLDER" -p "BROKER_PORT_PLACEHOLDER" -t "gateway/response/$TYPE/$SENSOR_ID" -C 1 -W 2 > "/tmp/mqtt_resp_${SENSOR_ID}.json" &
    SUB_PID=$!
    sleep 0.1
    mosquitto_pub -h "BROKER_IP_PLACEHOLDER" -p "BROKER_PORT_PLACEHOLDER" -t "gateway/request/$TYPE/$SENSOR_ID" -m ""
    wait $SUB_PID 2>/dev/null
    
    RAW_RESP=$(cat "/tmp/mqtt_resp_${SENSOR_ID}.json" 2>/dev/null)
    rm -f "/tmp/mqtt_resp_${SENSOR_ID}.json"
    
    if [[ "$RAW_RESP" == *"error"* ]] || [ -z "$RAW_RESP" ]; then
        VALUE="Error: Sensor Offline or Missing"
    else
        VALUE=$(echo "$RAW_RESP" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)
    fi
fi

[ -z "$TYPE" ] && TYPE="N/A"
[ -z "$NAME" ] && NAME="N/A"
[ -z "$VALUE" ] && VALUE="Timeout/Offline"

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
EOF

sed -i "s/BROKER_PORT_PLACEHOLDER/$BROKER_PORT/g" /usr/local/bin/read_sensor.sh
sed -i "s/BROKER_IP_PLACEHOLDER/$BROKER_IP/g" /usr/local/bin/read_sensor.sh

chmod +x /usr/local/bin/read_sensor.sh

echo "rocommunity public localhost .1" > /etc/snmp/snmpd.conf
awk -F',' '{print "pass .1.3.6.1.4.1.9999." $1 " /bin/bash /usr/local/bin/read_sensor.sh " $1}' "$MAP_FILE" >> /etc/snmp/snmpd.conf

systemctl restart snmpd

echo ">>> [6/6] Executing Background Node & Running Tests..."
cd "$MASTER_DIR" || exit
./master_node config > /dev/null 2>&1 &
MASTER_PID=$!

if [ -f "$SCRIPT_DIR/test_all_snmp.sh" ]; then
    bash "$SCRIPT_DIR/test_all_snmp.sh"
fi

echo "=========================================="
echo "SUCCESS! Build, Configuration, and Tests complete."
echo "Master Node is running in background (PID: $MASTER_PID)."