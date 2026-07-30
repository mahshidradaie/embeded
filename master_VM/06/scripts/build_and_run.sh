#!/bin/bash
cd "$(dirname "$0")" || exit
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}    DISTRIBUTED SENSOR NETWORK (PART 6 - ALERTS)      ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e "Please select the mode you want to run:"
echo -e "${YELLOW}1)${NC} Run Master Node + Daemon (For VM 50)"
echo -e "${YELLOW}2)${NC} Run Slave 1 Node + Daemon (For VM 51)"
echo -e "${YELLOW}3)${NC} Run Slave 2 Node + Daemon (For VM 52)"
echo -e "${YELLOW}4)${NC} Advanced Mode: Run ALL Nodes Locally (Bonus)"
echo -e "${CYAN}======================================================${NC}"
read -p "Enter your choice (1-4): " choice

cd ..
chmod +x master/*.sh slave/*.sh 2>/dev/null

# Fault injection separated by node architecture to match CSV layouts
inject_faulty_data() {
    local db_file=$1
    echo -e "${YELLOW}Injecting simulated fault data for $db_file...${NC}"
    
    if [[ "$db_file" == *"master"* ]]; then
        # Aligning with master_sensors.csv (101: Temp, 102: Humidity, 103: Motion, 104: Temp)
        sqlite3 "$db_file" "INSERT INTO sensor_readings (sensor_id, value, recorded_at) VALUES ('101', '55.5', datetime('now'));"
        sqlite3 "$db_file" "INSERT INTO sensor_readings (sensor_id, value, recorded_at) VALUES ('102', '12.0', datetime('now'));"
        sqlite3 "$db_file" "INSERT INTO sensor_readings (sensor_id, value, recorded_at) VALUES ('103', '1', datetime('now'));"
        sqlite3 "$db_file" "INSERT INTO sensor_readings (sensor_id, value, recorded_at) VALUES ('104', 'ERROR_DATA', datetime('now'));"
    else
        # Aligning with slave_sensors.csv (Assuming ID 204 belongs to CO2 in the slaves)
        sqlite3 "$db_file" "INSERT INTO sensor_readings (sensor_id, value, recorded_at) VALUES ('204', '1200.0', datetime('now'));"
    fi
}

run_api_tests() {
    local port=$1
    echo -e "\n${YELLOW}⏳ Waiting 12 seconds for Daemons to analyze data and generate alerts...${NC}"
    for i in {12..1}; do echo -ne "\rTime remaining: $i seconds... "; sleep 1; done
    
    echo -e "\n\n${CYAN}======================================================${NC}"
    echo -e "${CYAN}          AUTOMATED ALERT API TESTS (PART 6)          ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    echo -e "${YELLOW}[TEST 1] Querying Temperature Alerts...${NC}"
    curl -s "http://127.0.0.1:${port}/api/alerts?sensor_name=temperature"
    echo -e "\n\n${YELLOW}[TEST 2] Querying Humidity Alerts...${NC}"
    curl -s "http://127.0.0.1:${port}/api/alerts?sensor_name=humidity"
    echo -e "\n\n${YELLOW}[TEST 3] Querying CO2 Alerts...${NC}"
    curl -s "http://127.0.0.1:${port}/api/alerts?sensor_name=co2"
    echo -e "\n\n${YELLOW}[TEST 4] Querying Motion Alerts...${NC}"
    curl -s "http://127.0.0.1:${port}/api/alerts?sensor_name=motion"
    
    echo -e "\n\n${GREEN}✔ Tests Completed!${NC}"
}

case $choice in
    1)
        echo -e "\n${GREEN}[1] Compiling Master Node & Alert Daemon...${NC}"
        cd master && make clean > /dev/null 2>&1 && make
        
        echo -e "\n${GREEN}[2] Initializing Master Database & Injecting Faults...${NC}"
        rm -f alerts.db
        ./master_init_db.sh > /dev/null
        inject_faulty_data "master.db"
        
        echo -e "\n${GREEN}[3] Starting Master Daemon...${NC}"
        ./alert_daemon config.example &
        PID_DAEMON=$!
        
        echo -e "${GREEN}[4] Starting Master Node Server...${NC}"
        ./master_node config.example &
        PID_MASTER=$!
        
        MASTER_PORT=$(grep -E '^PORT=' config.example | cut -d'=' -f2 | tr -d '\r')
        run_api_tests "$MASTER_PORT"
        
        echo -e "\n${YELLOW}Shutting down Master processes automatically...${NC}"
        kill $PID_MASTER $PID_DAEMON 2>/dev/null
        echo -e "${GREEN}All services stopped successfully.${NC}"
        ;;
        
    2)
        echo -e "\n${GREEN}[1] Compiling Slave 1 Node & Alert Daemon...${NC}"
        cd slave && make clean > /dev/null 2>&1 && make
        
        echo -e "\n${GREEN}[2] Initializing Slave 1 Database & Injecting Faults...${NC}"
        rm -f alerts.db
        ./slave1_init_db.sh > /dev/null
        inject_faulty_data "slave1.db"
        
        echo -e "\n${GREEN}[3] Starting Slave 1 Daemon...${NC}"
        ./alert_daemon config_s1.example &
        PID_DAEMON=$!
        
        echo -e "${GREEN}[4] Starting Slave 1 Server...${NC}"
        ./slave_node config_s1.example &
        PID_SLAVE=$!
        
        SLAVE1_PORT=$(grep -E '^PORT=' config_s1.example | cut -d'=' -f2 | tr -d '\r')
        run_api_tests "$SLAVE1_PORT"
        
        echo -e "\n${YELLOW}Shutting down Slave 1 processes automatically...${NC}"
        kill $PID_SLAVE $PID_DAEMON 2>/dev/null
        echo -e "${GREEN}All services stopped successfully.${NC}"
        ;;
        
    3)
        echo -e "\n${GREEN}[1] Compiling Slave 2 Node & Alert Daemon...${NC}"
        cd slave && make clean > /dev/null 2>&1 && make
        
        echo -e "\n${GREEN}[2] Initializing Slave 2 Database & Injecting Faults...${NC}"
        rm -f alerts.db
        ./slave2_init_db.sh > /dev/null
        inject_faulty_data "slave2.db"
        
        echo -e "\n${GREEN}[3] Starting Slave 2 Daemon...${NC}"
        ./alert_daemon config_s2.example &
        PID_DAEMON=$!
        
        echo -e "${GREEN}[4] Starting Slave 2 Server...${NC}"
        ./slave_node config_s2.example &
        PID_SLAVE=$!
        
        SLAVE2_PORT=$(grep -E '^PORT=' config_s2.example | cut -d'=' -f2 | tr -d '\r')
        run_api_tests "$SLAVE2_PORT"
        
        echo -e "\n${YELLOW}Shutting down Slave 2 processes automatically...${NC}"
        kill $PID_SLAVE $PID_DAEMON 2>/dev/null
        echo -e "${GREEN}All services stopped successfully.${NC}"
        ;;
        
    4)
        echo -e "\n${GREEN}[1] Compiling all nodes and daemons for Advanced Mode...${NC}"
        cd master && make clean > /dev/null 2>&1 && make > /dev/null
        cd ../slave && make clean > /dev/null 2>&1 && make > /dev/null
        
        echo -e "\n${GREEN}[2] Initializing ALL Databases & Injecting Faults...${NC}"
        cd ../master 
        rm -f alerts.db
        ./master_init_db.sh > /dev/null
        inject_faulty_data "master.db"
        
        cd ../slave
        rm -f alerts.db
        if [ -f "slave1_init_db.sh" ]; then 
            ./slave1_init_db.sh > /dev/null
            inject_faulty_data "slave1.db"
        fi
        if [ -f "slave2_init_db.sh" ]; then 
            ./slave2_init_db.sh > /dev/null
            inject_faulty_data "slave2.db"
        fi
        cd ..
        
        echo -e "\n${CYAN}[3] Launching Distributed System & Daemons Locally...${NC}"
        
        cd slave
        ./alert_daemon config_s1_bonus.example > /dev/null 2>&1 &
        PID_D_S1=$!
        ./slave_node config_s1_bonus.example > /dev/null 2>&1 &
        PID_S1=$!
        
        ./alert_daemon config_s2_bonus.example > /dev/null 2>&1 &
        PID_D_S2=$!
        ./slave_node config_s2_bonus.example > /dev/null 2>&1 &
        PID_S2=$!
        
        cd ../master
        ./alert_daemon config_advanced.example > /dev/null 2>&1 &
        PID_D_M=$!
        ./master_node config_advanced.example > /dev/null 2>&1 &
        PID_M=$!
        
        ADV_PORT=$(grep -E '^PORT=' config_advanced.example | cut -d'=' -f2 | tr -d '\r')
        run_api_tests "$ADV_PORT"
        
        echo -e "\n${YELLOW}Shutting down all processes automatically...${NC}"
        kill $PID_M $PID_S1 $PID_S2 $PID_D_M $PID_D_S1 $PID_D_S2 2>/dev/null
        echo -e "${GREEN}All services stopped successfully.${NC}"
        ;;
esac
