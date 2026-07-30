#!/bin/bash
echo "Checking Memcached service for Slave..."
sudo systemctl start memcached
if systemctl is-active --quiet memcached; then
    echo "Memcached is successfully running on default port 11211."
else
    echo "Error: Memcached failed to start. Please check installation."
    exit 1
fi