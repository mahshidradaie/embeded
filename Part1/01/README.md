Part 1: System Installation and Setup
Before compiling and executing the project, the required tools and C++ libraries must be installed on the Ubuntu 22.04 LTS environment. These dependencies include the GNU C++ compiler (g++), make utility, SQLite3 engine, SQLite3 C/C++ development headers (libsqlite3-dev), HTTP testing utility (curl), and JSON processing tool (jq).
Run the following commands in the terminal to update the package list and install all necessary dependencies:
# Update the package index
sudo apt update

# Install C++ toolchain, SQLite3, development headers, curl, and jq
sudo apt install -y build-essential sqlite3 libsqlite3-dev curl jq

2. Compiling Master and Slave Programs
The project source code is organized into modular directories (master/ and slave/). Each module contains a dedicated Makefile to handle compilation cleanly and efficiently using g++ with SQLite3 and Mongoose library linkages.

Option A: Manual Compilation via Makefile
You can compile each node individually by navigating to its respective directory:

Compiling the Master Node:
cd master
make clean
make
Output: Generates the master_node executable binary.

Compiling the Slave Node:
cd ../slave
make clean
make
Output: Generates the slave_node executable binary.
Option B: Automated Compilation via Script
The project provides an interactive master script (build_and_run.sh) located at script directory. It automatically cleans existing object files and compiles both Master and Slave binaries seamlessly when selecting either execution mode:
# Make sure the script has execution permissions
chmod +x build_and_run.sh

# Run the automated build script
./build_and_run.sh

by running the automated bash script we face two options : 
You will be presented with two operational modes:

Option 1 (Base Mode - VM 50 Master Only):
Automatically compiles master_node.
Executes ./master_init_db.sh to initialize master.db.
Starts the Master server listening on port 8080 (configured to route missing requests to VM 51 and VM 52).

Option 2 (Advanced Mode - All Nodes Local):
Compiles both master_node and slave_node.
Initializes all local databases (master.db, slave1.db, slave2.db).
Launches Slave 1 (Port 8081), Slave 2 (Port 8082), and Master (Port 8080) simultaneously in the background.
Tracks Process IDs (PIDs) and traps CTRL+C signals to cleanly terminate all background node processes.

also we can use manual execution : 
On Master Node (VM 50):
cd master
./master_init_db.sh
./master_node config.example

On Slave 1 Node (VM 51):
cd slave
./db_init_slave_1.sh
./slave_node config.example

On Slave 2 Node (VM 52):
cd slave
./db_init_slave_2.sh
./slave_node config.example

# Requesting using curl commands
Clients and operators interact exclusively with the Master Node endpoint (/api/sensor). The Master Node dynamically resolves whether the requested sensor resides in its local database or requires proxying to one of the Slave nodes.
Open a split terminal on the Master host and issue HTTP GET requests using curl and jq : 
# Querying a sensor stored locally in the Master Node
curl -s "http://127.0.0.1:8080/api/sensor?type=temperature&id=101" | jq .

# Querying a sensor residing on Slave 1
curl -s "http://127.0.0.1:8080/api/sensor?type=co2&id=204" | jq .

# Querying a sensor residing on Slave 2
curl -s "http://127.0.0.1:8080/api/sensor?type=humidity&id=302" | jq .

# Database Structure & Schema Explanation
To avoid data redundancy and maintain high performance during time-series queries, each node's SQLite database is normalized into Third Normal Form (3NF) with three distinct tables:

Schema Overview
node_info Table:
Stores static operational identity metadata for the specific node (e.g., node_name, node_role, description).

sensors Table:
Stores fixed sensor metadata to prevent repeating text attributes across time-series records:

sensor_id (PRIMARY KEY)

sensor_type (e.g., temperature, co2, humidity)

sensor_name, location, unit, node_name, is_active

sensor_readings Table:
Stores time-stamped sensor measurement logs:

id (PRIMARY KEY AUTOINCREMENT)

sensor_id (FOREIGN KEY referencing sensors(sensor_id))

value, recorded_at

Indexing Strategy for Performance Optimization
To minimize search latency during HTTP requests:

Composite Index idx_sensors_type_id: Created on (sensor_type, sensor_id) to speed up WHERE filtering.

Descending Time Index idx_readings_sensor_time: Created on (sensor_id, recorded_at DESC). This enables the SQLite engine to fetch the latest sensor reading (ORDER BY datetime(recorded_at) DESC LIMIT 1) in sub-millisecond execution times.

# Network Topology Diagram
===================================================================================================
                       Distributed Network Topology (Isolated L2 Subnet)
===================================================================================================

                            +-----------------------------------+
                            |         Operator / Client         |
                            +-----------------+-----------------+
                                              |
                                              | HTTP GET /api/sensor
                                              v
+-------------------------------------------------------------------------------------------------+
| Host Machine (VMware Workstation Pro)                                                           |
|                                                                                                 |
|  Virtual Subnet: 192.168.118.0/24 (VMnet1 / Host-Only Mode)                                     |
|  +-------------------------------------------------------------------------------------------+  |
|  |                                Virtual Switch (vSwitch)                                   |  |
|  +--------+-----------------------------------+-----------------------------------+----------+  |
|           |                                   |                                   |             |
|           | eth0/ens33                        | eth0/ens33                        | eth0/ens33  |
|           v                                   v                                   v             |
|  +------------------------+          +------------------------+          +-------------------+  |
|  | VM 50: Master Node     |          | VM 51: Slave 1 Node    |          | VM 52: Slave 2 Node|  |
|  | ---------------------- |          | ---------------------- |          | ----------------- |  |
|  | OS: Ubuntu 22.04 LTS   |          | OS: Ubuntu 22.04 LTS   |          | OS: Ubuntu 22.04  |  |
|  | IP: 192.168.118.50     |          | IP: 192.168.118.51     |          | IP: 192.168.118.52|  |
|  | Port: 8080             |          | Port: 8080             |          | Port: 8080        |  |
|  | DB: master.db          |          | DB: slave1.db          |          | DB: slave2.db     |  |
|  +-----------+------------+          +------------------------+          +-------------------+  |
|              |                                    ^                                 ^           |
|              | HTTP Routing (Proxy)               |                                 |           |
|              +------------------------------------+---------------------------------+           |
|                                1. Fallback Query                     2. Fallback Query          |
+-------------------------------------------------------------------------------------------------+

# ===================================================================================================
                       Distributed Network Topology (Isolated L2 Subnet)
===================================================================================================

                            +-----------------------------------+
                            |         Operator / Client         |
                            +-----------------+-----------------+
                                              |
                                              | HTTP GET /api/sensor
                                              v
+-------------------------------------------------------------------------------------------------+
| Host Machine (VMware Workstation Pro)                                                           |
|                                                                                                 |
|  Virtual Subnet: 192.168.118.0/24 (VMnet1 / Host-Only Mode)                                     |
|  +-------------------------------------------------------------------------------------------+  |
|  |                                Virtual Switch (vSwitch)                                   |  |
|  +--------+-----------------------------------+-----------------------------------+----------+  |
|           |                                   |                                   |             |
|           | eth0/ens33                        | eth0/ens33                        | eth0/ens33  |
|           v                                   v                                   v             |
|  +------------------------+          +------------------------+          +-------------------+  |
|  | VM 50: Master Node     |          | VM 51: Slave 1 Node    |          | VM 52: Slave 2 Node|  |
|  | ---------------------- |          | ---------------------- |          | ----------------- |  |
|  | OS: Ubuntu 22.04 LTS   |          | OS: Ubuntu 22.04 LTS   |          | OS: Ubuntu 22.04  |  |
|  | IP: 192.168.118.50     |          | IP: 192.168.118.51     |          | IP: 192.168.118.52|  |
|  | Port: 8080             |          | Port: 8080             |          | Port: 8080        |  |
|  | DB: master.db          |          | DB: slave1.db          |          | DB: slave2.db     |  |
|  +-----------+------------+          +------------------------+          +-------------------+  |
|              |                                    ^                                 ^           |
|              | HTTP Routing (Proxy)               |                                 |           |
|              +------------------------------------+---------------------------------+           |
|                                1. Fallback Query                     2. Fallback Query          |
+-------------------------------------------------------------------------------------------------+


# ===================================================================================================
                       Distributed Network Topology (Isolated L2 Subnet)
===================================================================================================

                            +-----------------------------------+
                            |         Operator / Client         |
                            +-----------------+-----------------+
                                              |
                                              | HTTP GET /api/sensor
                                              v
+-------------------------------------------------------------------------------------------------+
| Host Machine (VMware Workstation Pro)                                                           |
|                                                                                                 |
|  Virtual Subnet: 192.168.118.0/24 (VMnet1 / Host-Only Mode)                                     |
|  +-------------------------------------------------------------------------------------------+  |
|  |                                Virtual Switch (vSwitch)                                   |  |
|  +--------+-----------------------------------+-----------------------------------+----------+  |
|           |                                   |                                   |             |
|           | eth0/ens33                        | eth0/ens33                        | eth0/ens33  |
|           v                                   v                                   v             |
|  +------------------------+          +------------------------+          +-------------------+  |
|  | VM 50: Master Node     |          | VM 51: Slave 1 Node    |          | VM 52: Slave 2 Node|  |
|  | ---------------------- |          | ---------------------- |          | ----------------- |  |
|  | OS: Ubuntu 22.04 LTS   |          | OS: Ubuntu 22.04 LTS   |          | OS: Ubuntu 22.04  |  |
|  | IP: 192.168.118.50     |          | IP: 192.168.118.51     |          | IP: 192.168.118.52|  |
|  | Port: 8080             |          | Port: 8080             |          | Port: 8080        |  |
|  | DB: master.db          |          | DB: slave1.db          |          | DB: slave2.db     |  |
|  +-----------+------------+          +------------------------+          +-------------------+  |
|              |                                    ^                                 ^           |
|              | HTTP Routing (Proxy)               |                                 |           |
|              +------------------------------------+---------------------------------+           |
|                                1. Fallback Query                     2. Fallback Query          |
+-------------------------------------------------------------------------------------------------+


# Request and Response Path (Cascading Logic)
Slaves do not communicate with each other directly. When VM 2 (Slave 1) does not contain the requested sensor, it returns an explicit HTTP 404 error back to the Master, signaling the Master to fallback and query VM 3 (Slave 2).

[Client / Operator]      [Master Node / VM 50]     [Slave 1 Node / VM 51]    [Slave 2 Node / VM 52]
           |                         |                         |                         |
  (1)      |--- Send HTTP Request -->|                         |                         |
           |    (GET /api/sensor)    |                         |                         |
           |                         |-- (2) Query Local DB -┐ |                         |
           |                         |       (master.db)     | |                         |
           |                         |<-- Data Not Found ----┘ |                         |
           |                         |                         |                         |
  (3)      |                         |--- Send HTTP Request -->|                         |
           |                         |    (GET /api/sensor)    |                         |
           |                         |                         |-- Query Local DB -┐     |
           |                         |                         |   (slave1.db)     |     |
  (4)      |                         |<-- Return HTTP 404 -----|<-- Data Not Found ┘     |
           |                         |    (Signal to Master)   |                         |
           |                         |                         |                         |
  (5)      |                         |--- Send HTTP Request (Route to VM 52) ------------>|
           |                         |    (GET /api/sensor)    |                         |
           |                         |                         |                         |-- Query Local DB -┐
           |                         |                         |                         |   (slave2.db)     |
  (6)      |                         |<-- Return HTTP 200 (JSON Data) -------------------|<-- Data Found ----┘
           |                         |                         |                         |
  (7)      |<-- Forward Final JSON --|                         |                         |
           |    (Status: Success)    |                         |                         |



8. HTTP Protocol Security Analysis & Improvements
Current Security Flaws
Cleartext Transmission: Data is transmitted unencrypted over standard HTTP, making it vulnerable to Eavesdropping / Packet Sniffing on the local virtual network.

Lack of Authentication: Slave nodes accept incoming HTTP queries from any client without validating the identity of the requester.

Man-In-The-Middle (MITM) Vulnerability: An attacker on VMnet1 can intercept or alter sensor payloads sent between Slaves and the Master.

Proposed Improvement Methods
Protocol Encryption (HTTPS / TLS): Upgrade the Mongoose web server library to support SSL/TLS certificates, ensuring end-to-end encryption across all node communications.

Token-Based Authentication: Implement Bearer Tokens or API Keys in the HTTP headers (e.g., Authorization: Bearer <TOKEN>). Slave nodes will reject queries that do not present a valid Master token.

Network Firewall Rules (UFW Whitelisting): Configure ufw on Slave VMs so that port 8080 strictly accepts traffic from the Master's IP (192.168.118.50) and drops all other requests:

sudo ufw allow from 192.168.118.50 to any port 8080 proto tcp

Prepared Statements: Secure C++ SQLite query execution using Parameter Binding instead of string formatting to completely neutralize SQL Injection risks.

