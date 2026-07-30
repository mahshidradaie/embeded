#!/bin/bash


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MASTER_DIR="$(cd "$SCRIPT_DIR/../master" && pwd)"
SLAVE_DIR="$(cd "$SCRIPT_DIR/../slave" && pwd)"

# Color variables for UI
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

clear
echo -e "${CYAN}=====================================================${NC}"
echo -e "${CYAN}  Build and Run Automation - Universal Launcher      ${NC}"
echo -e "${CYAN}=====================================================${NC}"
echo -e "Please select the node you want to run on this VM:"
echo -e "${YELLOW}1)${NC} Master Node (For VM 50)"
echo -e "${YELLOW}2)${NC} Slave Node 1 (For VM 51)"
echo -e "${YELLOW}3)${NC} Slave Node 2 (For VM 52)"
echo -e "${YELLOW}4)${NC} Advanced Mode: Run ALL Nodes Locally"
echo -e "${CYAN}=====================================================${NC}"
read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        echo -e "\n${CYAN}=====================================================${NC}"
        echo -e "${CYAN}       Building and Running Master Node              ${NC}"
        echo -e "${CYAN}=====================================================${NC}"
        cd "$MASTER_DIR" || { echo -e "${RED}Error: Could not find master directory!${NC}"; exit 1; }

        echo -e "\n${GREEN}[1] Compiling the C++ code...${NC}"
        make clean > /dev/null 2>&1 
        make
        if [ $? -ne 0 ]; then echo -e "${RED}Error: Compilation failed!${NC}"; exit 1; fi
        echo "Compilation successful!"

        echo -e "\n${GREEN}[2] Initializing SQLite Database...${NC}"
        chmod +x db_init_master.sh 2>/dev/null
        ./db_init_master.sh

        echo -e "\n${GREEN}[3] Checking Memcached Service...${NC}"
        chmod +x memcached_init_master.sh 2>/dev/null
        ./memcached_init_master.sh

        echo -e "\n${GREEN}[4] Starting the Master Node Server...${NC}"
        echo -e "-----------------------------------------------------"
        ./master_node config.example
        ;;
        
    2)
        echo -e "\n${CYAN}=====================================================${NC}"
        echo -e "${CYAN}       Building and Running Slave Node 1             ${NC}"
        echo -e "${CYAN}=====================================================${NC}"
        cd "$SLAVE_DIR" || { echo -e "${RED}Error: Could not find slave directory!${NC}"; exit 1; }

        echo -e "\n${GREEN}[1] Compiling the C++ code...${NC}"
        make clean > /dev/null 2>&1
        make
        if [ $? -ne 0 ]; then echo -e "${RED}Error: Compilation failed!${NC}"; exit 1; fi
        echo "Compilation successful!"

        echo -e "\n${GREEN}[2] Initializing SQLite Database...${NC}"
        chmod +x db_init_slave_1.sh 2>/dev/null
        ./db_init_slave_1.sh

        echo -e "\n${GREEN}[3] Checking Memcached Service...${NC}"
        chmod +x memcached_init_slave.sh 2>/dev/null
        ./memcached_init_slave.sh

        echo -e "\n${GREEN}[4] Starting the Slave Node 1 Server...${NC}"
        echo -e "-----------------------------------------------------"
        ./slave_node config_s1.example
        ;;
        
    3)
        echo -e "\n${CYAN}=====================================================${NC}"
        echo -e "${CYAN}       Building and Running Slave Node 2             ${NC}"
        echo -e "${CYAN}=====================================================${NC}"
        cd "$SLAVE_DIR" || { echo -e "${RED}Error: Could not find slave directory!${NC}"; exit 1; }

        echo -e "\n${GREEN}[1] Compiling the C++ code...${NC}"
        make clean > /dev/null 2>&1
        make
        if [ $? -ne 0 ]; then echo -e "${RED}Error: Compilation failed!${NC}"; exit 1; fi
        echo "Compilation successful!"

        echo -e "\n${GREEN}[2] Initializing SQLite Database...${NC}"
        chmod +x db_init_slave_2.sh 2>/dev/null
        ./db_init_slave_2.sh

        echo -e "\n${GREEN}[3] Checking Memcached Service...${NC}"
        chmod +x memcached_init_slave.sh 2>/dev/null
        ./memcached_init_slave.sh

        echo -e "\n${GREEN}[4] Starting the Slave Node 2 Server...${NC}"
        echo -e "-----------------------------------------------------"
        ./slave_node config_s2.example
        ;;
        
    4)
        echo -e "\n${CYAN}=====================================================${NC}"
        echo -e "${CYAN}       Advanced Mode: Running ALL Nodes Locally      ${NC}"
        echo -e "${CYAN}=====================================================${NC}"
        
        echo -e "\n${GREEN}[1] Compiling all nodes...${NC}"
        cd "$MASTER_DIR" && make clean > /dev/null 2>&1 && make > /dev/null
        cd "$SLAVE_DIR" && make clean > /dev/null 2>&1 && make > /dev/null
        
        echo -e "\n${GREEN}[2] Initializing Databases & Memcached...${NC}"
        cd "$MASTER_DIR"
        chmod +x db_init_master.sh memcached_init_master.sh 2>/dev/null
        ./db_init_master.sh > /dev/null
        ./memcached_init_master.sh > /dev/null
        
        cd "$SLAVE_DIR"
        chmod +x db_init_slave_1.sh db_init_slave_2.sh memcached_init_slave.sh 2>/dev/null
        if [ -f "db_init_slave_1.sh" ]; then ./db_init_slave_1.sh > /dev/null; fi
        if [ -f "db_init_slave_2.sh" ]; then ./db_init_slave_2.sh > /dev/null; fi
        ./memcached_init_slave.sh > /dev/null
        
        echo -e "\n${GREEN}[3] Launching Distributed System Architecture Locally...${NC}"
        cd "$SLAVE_DIR"
        ./slave_node config_s1.example &
        PID_S1=$!
        ./slave_node config_s2.example &
        PID_S2=$!
        
        cd "$MASTER_DIR"
        ./master_node config.example &
        PID_M=$!
        
        echo -e "\n${GREEN}✔ System is ALIVE!${NC}"
        echo -e "${RED}👉 Press [CTRL+C] to gracefully stop all servers and free ports.${NC}"
        
        trap "echo -e '\n${YELLOW}Stopping all nodes...${NC}'; kill $PID_M $PID_S1 $PID_S2 2>/dev/null; exit" SIGINT SIGTERM
        wait
        ;;
        
    *)
        echo -e "${RED}Invalid option selected. Exiting.${NC}"
        exit 1
        ;;
esac