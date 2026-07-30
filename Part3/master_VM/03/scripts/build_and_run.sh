#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MASTER_DIR="$(cd "$SCRIPT_DIR/../master" 2>/dev/null || cd "$SCRIPT_DIR" && pwd)" 

echo "=========================================="
echo " Starting MQTT Master Node Build & Run    "
echo "=========================================="

CONFIG_FILE="$MASTER_DIR/config.example"
BROKER_PORT=$(grep -E "^(BROKER_PORT|PORT)=" "$CONFIG_FILE" | head -n 1 | cut -d'=' -f2 | tr -d '\r')


if [ -z "$BROKER_PORT" ]; then 
    BROKER_PORT=1883 
fi

echo "--> Step 0: Configuring Mosquitto Broker (Port: $BROKER_PORT) "
sudo bash -c "echo -e \"listener $BROKER_PORT 0.0.0.0\nallow_anonymous true\" > /etc/mosquitto/conf.d/default.conf"
sudo systemctl restart mosquitto
echo "Broker configuration applied successfully!"

cd "$MASTER_DIR" || { echo "Error: Could not find master directory!"; exit 1; }

echo "--> Step 1: Initializing Memcached..."
chmod +x memcached_init_master.sh
./memcached_init_master.sh

echo "--> Step 2: Compiling the C++ Source Code..."
make clean > /dev/null 2>&1
make

if [ $? -eq 0 ]; then
    echo "--> Step 3: Compilation successful. Starting the Master Node..."
    echo "-----------------------------------------------------"
    ./master_node config.example
else
    echo "--> Error: Compilation failed! Please check your code."
    exit 1
fi