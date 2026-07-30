#!/bin/bash

cd "$(dirname "$0")" || exit

CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MASTER_URL="http://127.0.0.1:8080/api/history"

TEST_DATE="2026-06-01"

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}     VERIFICATION TEST: PART 5 (Historical API)       ${NC}"
echo -e "${CYAN}======================================================${NC}"

echo -e "\n${YELLOW}[1] Testing Master Node (Local SQLite) -> Sensor 101${NC}"
echo "Request: GET /api/history?sensor_name=temperature&sensor_id=101&date=$TEST_DATE"
echo "------------------------------------------------------"
curl -s "${MASTER_URL}?sensor_name=temperature&sensor_id=101&date=$TEST_DATE" | jq . || curl -s "${MASTER_URL}?sensor_name=temperature&sensor_id=101&date=$TEST_DATE"
echo -e "\n"

echo -e "${YELLOW}[2] Testing Slave Node 1 (Network Route) -> Sensor 204${NC}"
echo "Request: GET /api/history?sensor_name=co2&sensor_id=204&date=$TEST_DATE"
echo "------------------------------------------------------"
curl -s "${MASTER_URL}?sensor_name=co2&sensor_id=204&date=$TEST_DATE" | jq . || curl -s "${MASTER_URL}?sensor_name=co2&sensor_id=204&date=$TEST_DATE"
echo -e "\n"

echo -e "${YELLOW}[3] Testing Slave Node 2 (Network Route) -> Sensor 302${NC}"
echo "Request: GET /api/history?sensor_name=humidity&sensor_id=302&date=$TEST_DATE"
echo "------------------------------------------------------"
curl -s "${MASTER_URL}?sensor_name=humidity&sensor_id=302&date=$TEST_DATE" | jq . || curl -s "${MASTER_URL}?sensor_name=humidity&sensor_id=302&date=$TEST_DATE"
echo -e "\n"

echo -e "${GREEN} Test Completed! Check the API responses above.${NC}"
echo -e "${CYAN}======================================================${NC}"