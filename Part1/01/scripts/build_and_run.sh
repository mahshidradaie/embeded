#!/bin/bash
cd "$(dirname "$0")" || exit
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}     DISTRIBUTED SENSOR NETWORK (UNIVERSAL LAUNCHER)  ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e "Please select the mode you want to run:"
echo -e "${YELLOW}1)${NC} Base Mode: Run Master Node ONLY (VM 50)"
echo -e "${YELLOW}2)${NC} Base Mode: Run Slave Node 1 (VM 51)"
echo -e "${YELLOW}3)${NC} Base Mode: Run Slave Node 2 (VM 52)"
echo -e "${YELLOW}4)${NC} Advanced Mode (Bonus): Run ALL Nodes Locally on this VM"
echo -e "${CYAN}======================================================${NC}"
read -p "Enter your choice (1-4): " choice

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
        echo -e "\n${CYAN}======================================================${NC}"
        echo -e "${CYAN}     DISTRIBUTED SENSOR NETWORK (PART 1 - VM 51)      ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        
        cd slave || exit
        
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
        ./slave_node config_s1.example
        ;;
        
    3)
        echo -e "\n${CYAN}======================================================${NC}"
        echo -e "${CYAN}     DISTRIBUTED SENSOR NETWORK (PART 1 - VM 52)      ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        
        cd slave || exit
        
        echo -e "\n${GREEN}[1] Compiling Slave Node 2...${NC}"
        make clean > /dev/null 2>&1 && make
        if [ $? -ne 0 ]; then
            echo -e "${RED} Compilation Failed!${NC}"
            exit 1
        fi
        echo "Compilation successful!"

        echo -e "\n${GREEN}[2] Initializing Slave 2 Database...${NC}"
        ./slave2_init_db.sh

        echo -e "\n${GREEN}[3] Starting Slave Node 2 Server...${NC}"
        echo -e "------------------------------------------------------"
        ./slave_node config_s2.example
        ;;
        
    4)
        echo -e "\n${GREEN}[1] Compiling all nodes for Advanced Mode...${NC}"
        cd master && make clean > /dev/null 2>&1 && make > /dev/null
        cd ../slave && make clean > /dev/null 2>&1 && make > /dev/null
        
        echo -e "\n${GREEN}[2] Initializing ALL Databases...${NC}"
        cd ../master && ./master_init_db.sh > /dev/null
        cd ../slave
        if [ -f "db_init_slave_1.sh" ]; then ./slave1_init_db.sh > /dev/null; fi
        if [ -f "db_init_slave_2.sh" ]; then ./slave2_init_db.sh > /dev/null; fi
        cd ..
        
        echo -e "\n${CYAN}[3] Launching Distributed System Architecture Locally...${NC}"
        
        cd slave
        ./slave_node config_s1_bonus.example &
        PID_S1=$!
        ./slave_node config_s2_bonus.example &
        PID_S2=$!
        cd ../master
        ./master_node config_advanced.example &
        PID_M=$!
        cd ..

        echo -e "\n${GREEN}✔ System is ALIVE! (Master:8080, Slave1:8081, Slave2:8082)${NC}"
        echo -e "${RED}👉 Press [CTRL+C] to stop all servers.${NC}"
        
        trap "echo -e '\n${YELLOW}Stopping all nodes...${NC}'; kill $PID_M $PID_S1 $PID_S2 2>/dev/null; exit" SIGINT SIGTERM
        wait
        ;;
        
    *)
        echo -e "${RED}Invalid option selected. Exiting.${NC}"
        exit 1
        ;;
esac