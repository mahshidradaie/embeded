#!/bin/bash


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit

CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m'


CONFIG_FILE="$SCRIPT_DIR/../master/config.example"
if [ -f "$CONFIG_FILE" ]; then
    MASTER_PORT=$(grep "^PORT=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '\r')
else
    MASTER_PORT="8080" 
fi

MASTER_URL="http://127.0.0.1:${MASTER_PORT}/api/sensor"

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}      VERIFICATION TEST: PART 1 (HTTP API & Routing)${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e "Target API: ${MASTER_URL}"

echo -e "\n${YELLOW}[1] Testing Master Node (Local SQLite) -> Sensor 101${NC}"
echo "Request: GET /api/sensor?type=temperature&id=101"
echo "------------------------------------------------------"
curl -s "${MASTER_URL}?type=temperature&id=101" | jq . || curl -s "${MASTER_URL}?type=temperature&id=101"
echo -e "\n"

echo -e "${YELLOW}[2] Testing Slave Node 1 (Network Route) -> Sensor 204${NC}"
echo "Request: GET /api/sensor?type=co2&id=204"
echo "------------------------------------------------------"
curl -s "${MASTER_URL}?type=co2&id=204" | jq . || curl -s "${MASTER_URL}?type=co2&id=204"
echo -e "\n"

echo -e "${YELLOW}[3] Testing Slave Node 2 (Network Route) -> Sensor 302${NC}"
echo "Request: GET /api/sensor?type=humidity&id=302"
echo "------------------------------------------------------"
curl -s "${MASTER_URL}?type=humidity&id=302" | jq . || curl -s "${MASTER_URL}?type=humidity&id=302"
echo -e "\n"

echo -e "${GREEN} Test Completed! Check the API responses above.${NC}"
echo -e "${CYAN}======================================================${NC}"