#!/bin/bash

cd "$(dirname "$0")" || exit
CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}     DISTRIBUTED SENSOR NETWORK (PART 1 - VM 51)      ${NC}"
echo -e "${CYAN}======================================================${NC}"

cd ../slave || exit
chmod +x *.sh 2>/dev/null

echo -e "\n${GREEN}[1] Compiling Slave Node 1...${NC}"
make clean > /dev/null 2>&1 && make
if [ $? -ne 0 ]; then
    echo -e "${RED} Compilation Failed!${NC}"
    exit 1
fi
echo " Compilation successful!"

echo -e "\n${GREEN}[2] Initializing Slave 1 Database...${NC}"
./slave1_init_db.sh

echo -e "\n${GREEN}[3] Starting Slave Node 1 Server...${NC}"
echo -e "------------------------------------------------------"
./slave_node config_s1.example &