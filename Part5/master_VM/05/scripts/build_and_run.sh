#!/bin/bash
cd "$(dirname "$0")" || exit
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}     DISTRIBUTED SENSOR NETWORK (PART 1 - VM 50)      ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e "Please select the mode you want to run:"
echo -e "${YELLOW}1)${NC} Base Mode: Run Master Node ONLY (Connects to VMs 51 & 52)"
echo -e "${YELLOW}2)${NC} Advanced Mode (Bonus): Run ALL Nodes Locally on this VM"
echo -e "${CYAN}======================================================${NC}"
read -p "Enter your choice (1-2): " choice

cd ..
chmod +x master/*.sh slave/*.sh 2>/dev/null

case $choice in
    1)
        echo -e "\n${GREEN}[1] Compiling Master Node...${NC}"
        cd master && make clean > /dev/null 2>&1 && make
        if [ $? -ne 0 ]; then echo -e "${RED}Compilation Failed!${NC}"; exit 1; fi
        
        echo -e "\n${GREEN}[2] Initializing Master Database...${NC}"
        ./master_init_db.sh
        
        echo -e "\n${GREEN}[3] Starting Master Node Server...${NC}"
        echo -e "------------------------------------------------------"
        ./master_node config.example
        ;;
        
    2)
        echo -e "\n${GREEN}[1] Compiling all nodes for Advanced Mode...${NC}"
        cd master && make clean > /dev/null 2>&1 && make > /dev/null
        cd ../slave && make clean > /dev/null 2>&1 && make > /dev/null
        
        echo -e "\n${GREEN}[2] Initializing ALL Databases...${NC}"
        cd ../master && ./master_init_db.sh > /dev/null
        cd ../slave
        if [ -f "slave1_init_db.sh" ]; then ./slave1_init_db.sh > /dev/null; fi
        if [ -f "slave2_init_db.sh" ]; then ./slave2_init_db.sh > /dev/null; fi
        cd ..
        
        echo -e "\n${CYAN}[3] Launching Distributed System Architecture Locally...${NC}"
        
        cd slave
        ./slave_node config_s1.example &
        PID_S1=$!
        ./slave_node config_s2.example &
        PID_S2=$!
        cd ../master
        ./master_node config.example &
        PID_M=$!
        cd ..

        echo -e "\n${GREEN} System is ALIVE! (Master:8080, Slave1:8081, Slave2:8082)${NC}"
        echo -e "${RED} Press [CTRL+C] to stop all servers.${NC}"
        
        trap "echo -e '\n${YELLOW}Stopping all nodes...${NC}'; kill $PID_M $PID_S1 $PID_S2 2>/dev/null; exit" SIGINT SIGTERM
        wait
        ;;
        
    *)
        echo -e "${RED}Invalid option selected. Exiting.${NC}"
        exit 1
        ;;
esac