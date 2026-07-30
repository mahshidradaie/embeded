#!/bin/bash

echo "=========================================="
echo "    PART 4: SLAVE NODE INITIALIZATION     "
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SLAVE_DIR="$(cd "$SCRIPT_DIR/../slave" 2>/dev/null || cd "$SCRIPT_DIR" && pwd)"

echo ">>> [1/3] Compiling Slave Node C++ Code..."
cd "$SLAVE_DIR" || { echo "Error: Could not find slave directory!"; exit 1; }
make clean > /dev/null 2>&1
make

if [ $? -ne 0 ]; then
    echo " Error: Compilation failed!"
    exit 1
fi

echo ">>> [2/3] Detecting Configuration..."

MY_IP=$(hostname -I | awk '{print $1}')

if [[ "$MY_IP" == *"51"* ]]; then
    CONFIG_FILE="config_s1.example"
    echo "    Detected VM 51 (Slave 1). Using $CONFIG_FILE."
elif [[ "$MY_IP" == *"52"* ]]; then
    CONFIG_FILE="config_s2.example"
    echo "    Detected VM 52 (Slave 2). Using $CONFIG_FILE."
else
    CONFIG_FILE="config.example"
    echo "    WARNING: Unknown IP. Using default $CONFIG_FILE."
fi

echo ">>> [3/3] Connecting to MQTT Broker..."

pkill -f slave_node 2>/dev/null

./slave_node "$CONFIG_FILE" > /dev/null 2>&1 &
SLAVE_PID=$!

echo "=========================================="
echo "SUCCESS! Slave Node is Connected to MQTT Broker."
echo "Background PID: $SLAVE_PID"