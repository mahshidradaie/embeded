# System Alert Daemon: Deployment and Operational Engineering Guide

## 1. Daemon Compilation
To deploy the system, the source code must first be compiled by linking the POSIX threads and SQLite3 database libraries. From the workspace directory, execute the compiler to generate the binary:
```bash
g++ alert_daemon.cpp -o alert_daemon -lsqlite3 -lpthread 

2. Service File Installation
Following a successful build, the application must be integrated into the operating system's core as a resilient service. This installation is achieved by copying the service configuration file to the system directory and subsequently refreshing the kernel's process manager: 
sudo cp alert_daemon.service /etc/systemd/system/
sudo systemctl daemon-reload


3. Starting the Daemon
Once installed, the daemon's lifecycle is fully governed by the system manager. The background process can be initialized safely using:
sudo systemctl start alert_daemon.service

4. Stopping the Daemon
To safely halt the daemon during maintenance windows and prevent database transaction corruption or memory leaks, execute:
sudo systemctl stop alert_daemon.service

5. Checking Daemon Status
To ensure high availability and monitor the structural health of the daemon, its real-time operational status can be queried with:


sudo systemctl status alert_daemon.service
6. Viewing System Logs
All standard outputs, errors, and system events are aggregated by the Linux journal. These can be continuously monitored for debugging and observability purposes by executing:

sudo journalctl -u alert_daemon.service -f
7. Auditing Database Alerts
Registered alerts can be audited at any time by running a direct SQL query against the local database to retrieve the anomaly records:


sqlite3 slave1.db "SELECT * FROM alerts;"


8. Alert Generation Conditions
The core analytical engine of the daemon operates by continuously evaluating incoming sensor telemetry against strict engineering thresholds. Specific conditions trigger automatic anomaly detection:

Temperature Out of Range: Ambient temperature falling above or below the standard operational tolerance.

Humidity Out of Range: Relative humidity dropping below or exceeding the acceptable tolerance bounds.

CO2 Above Limit: Carbon dioxide concentrations surpassing maximum safety limits.

Invalid Value: A sensor transmitting corrupted, null, or logically impossible data.

Timeout: Complete loss of signal or lack of received data from a sensor within a predefined timeframe.