## Section 1: Architectural Design & Zero Hardcoding

### 1.1 Master Node Configuration Analysis (`config.example`)
The system architecture strictly adheres to **Engineering Design Principles**, specifically the **Zero Hardcoding** design pattern. All network parameters, ports, and database routes are decoupled from the C++ binaries and managed dynamically at runtime via configuration files. 

* **`LISTEN_IP=0.0.0.0`**: Binds the HTTP web server socket to all available network interfaces, allowing incoming connections from external host browsers and internal virtual networks.
* **`PORT=8080`**: Specifies the primary TCP port for handling incoming `/api/sensor` HTTP requests.
* **`DB_FILE=master.db`**: Defines the target local SQLite3 database file containing primary time-series records.
* **`MEMCACHED_IP=127.0.0.1` & `MEMCACHED_PORT=11211`**: Dynamically routes the C++ `libmemcached` client to the local caching daemon.
* **`SLAVE1_IP` & `SLAVE1_PORT` (`192.168.118.51:8080`)**: Configures the primary network route for forwarding queries to Slave 1 upon local cache/database misses.
* **`SLAVE2_IP` & `SLAVE2_PORT` (`192.168.118.52:8080`)**: Configures the secondary network route for forwarding queries to Slave 2.

---

## Section 2: Memcached Integration & System Benchmarking

### 2.1 Memcached Installation & Execution

**Installation**
To enable Layer-1 in-memory caching, Memcached and its corresponding C++ client development library (`libmemcached`) must be installed across the virtual machines:
```bash
sudo apt update
sudo apt install -y memcached libmemcached-dev

# Service Execution & Health Checking
Memcached operates as a background daemon listening on TCP port 11211. To ensure system stability, an initialization script (memcached_init.sh) acts as a fail-safe gate before binary execution:

# Compilation and Build Automation
The C++ binaries use g++ and are built using modular Makefiles. Both libsqlite3 and libmemcached are dynamically linked during compilation.

#Master & Slave Execution (Universal Launcher)
To enforce proper resource isolation and avoid data collisions, the system utilizes a unified Bash script (build_and_run.sh) that dynamically resolves paths and applies specific isolated configuration files (config_s1.example, config_s2.example) based on the execution environment.

#Usage, Testing & Benchmarking
Manual Request Routing
Sensor readings can be queried over HTTP GET requests:
curl "[http://127.0.0.1:8080/api/sensor?type=co2&id=204](http://127.0.0.1:8080/api/sensor?type=co2&id=204)"

#Automated Benchmark Execution
The benchmarking tool (benchmark_read.sh) dynamically extracts network targets from the configuration files and measures read latencies across two sequential rounds (Cache Miss vs. Cache Hit).

chmod +x scripts/benchmark_read.sh
./scripts/benchmark_read.sh


# Performance Analysis & Results
1. Cache Population Mechanism (Lazy Population)
The caching architecture utilizes a Look-Aside / Lazy Population pattern. When a query misses the cache, the Master node fetches it from the SQLite database or remote Slave network. Immediately upon retrieving the JSON string, the C++ code invokes memcached_set to store the result in RAM.

2. Cache Hit Conditions (When is cache read?)
Data is read from the cache (Round 2) when the exact query key (sensorType_sensorID) already exists in the Memcached RAM. The system immediately returns the cached JSON string, completely bypassing Disk I/O and network requests.

3. Cache Miss Conditions (When is SQLite read?)
Data is read from SQLite (Round 1) when the key is absent from the RAM. The Master reads from its local master.db for internal sensors or proxies requests to Slaves, which read from slave1.db or slave2.db.

# Cache Eviction & Miss Factors
If data fails to load from the cache during a secondary read, potential causes include:Service Restart: The Memcached service flushed the RAM.LRU Eviction: Memory limits were reached, triggering the Least Recently Used (LRU) algorithm to drop older keys.TTL Expiry: The Time-To-Live for the cached key expired.

#Benchmark Timings 
you can see the results in the report pdf.

System Impact & Analysis

Elimination of Network Bottlenecks: In Round 1, remote queries targeting Slave VMs took up to 48.6 ms due to TCP socket creation and inter-VM round-trip time. In Round 2, serving these queries from local RAM reduced latency to ~0.11 ms (>400x speedup).

Reduction in Disk I/O: Local SQLite queries dropped from 1.22 ms to 0.08 ms.

Conclusion: The integration of Layer-1 RAM caching successfully resolves the bottleneck of inter-VM propagation delay, transforming an I/O-bound architecture into a deterministic, high-throughput engineering system.