#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SLAVE_DIR="$(cd "$SCRIPT_DIR/../slave" 2>/dev/null || cd "$SCRIPT_DIR" && pwd)"

echo "=========================================="
echo " Starting MQTT Slave Node Build & Run     "
echo "=========================================="

cd "$SLAVE_DIR" || { echo "Error: Could not find slave directory!"; exit 1; }

echo "--> Step 1: Initializing Memcached..."
chmod +x memcached_init_slave.sh
./memcached_init_slave.sh

echo "--> Step 2: Compiling the C++ Source Code..."
make clean > /dev/null 2>&1
make

if [ $? -eq 0 ]; then
    echo "--> Step 3: Compilation successful. Starting the Slave Node..."
    echo "-----------------------------------------------------"
    ./slave_node config.example
else
    echo "--> Error: Compilation failed! Please check your code."
    exit 1
fi