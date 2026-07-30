# 1. installing snmp tools
At the infrastructure level, the deployment of this service s fully automated within the system scripts by installing the necessary network
management agents and client tools using the command : 
# apt-get install -y snmp snmpd snmp-mibs-downloader



## 2. SNMPD configuration
To establish a communication bridge between the isolated Linux snmpd service and the project's dedicated database, the pass directive is utilized
within the daemon's configuration.
rocommunity public localhost .1
pass .1.3.6.1.4.1.9999.101 /bin/bash /usr/local/bin/read_sensor.sh 101
pass .1.3.6.1.4.1.9999.102 /bin/bash /usr/local/bin/read_sensor.sh 102
pass .1.3.6.1.4.1.9999.103 /bin/bash /usr/local/bin/read_sensor.sh 103
pass .1.3.6.1.4.1.9999.104 /bin/bash /usr/local/bin/read_sensor.sh 104
pass .1.3.6.1.4.1.9999.201 /bin/bash /usr/local/bin/read_sensor.sh 201
pass .1.3.6.1.4.1.9999.202 /bin/bash /usr/local/bin/read_sensor.sh 202
pass .1.3.6.1.4.1.9999.203 /bin/bash /usr/local/bin/read_sensor.sh 203
pass .1.3.6.1.4.1.9999.204 /bin/bash /usr/local/bin/read_sensor.sh 204
pass .1.3.6.1.4.1.9999.301 /bin/bash /usr/local/bin/read_sensor.sh 301
pass .1.3.6.1.4.1.9999.302 /bin/bash /usr/local/bin/read_sensor.sh 302
pass .1.3.6.1.4.1.9999.303 /bin/bash /usr/local/bin/read_sensor.sh 303

### 3. defined OID structure
Through this setup, any incoming requests directed at the project's custom OID tree (structured under 1.3.6.1.4.1.9999) are dynamically
routed to the read_sensor.sh proxy script rather than being processed internally. Acting as an intelligent protocol interface, this script
categorizes SNMP requests into three sub-branches: identifier .1 for the sensor name, .2 for the description, and .3 for the dynamic 
latest value. To optimize system resources and separate static data from dynamic data, the sensor names and types are read directly from a 
lightweight text mapping file (sensor_map.txt) without engaging the network, while the SQLite database (master.db) is exclusively queried to fetch the
the dynamic values.

#### 4. how to exexute and run the SNMP service
The service is then reloaded by executing systemctl restart snmpd, making the network ready to respond

##### 5. reading data via snmpwalk
By executing the standard client command snmpwalk -v2c -c public localhost .1.3.6.1.4.1.9999, this script iterates through the entire network tree
systematically proving the proxy script's routing accuracy and the system's real-time response capabilities.

###### 6.The path of data from SQLite database to snmp
To optimize system resources and separate static data from dynamic data, the sensor names and types are read directly from a 
lightweight text mapping file (sensor_map.txt) without engaging the network, while the SQLite database (master.db) is exclusively queried to fetch
the dynamic value.The deployment process of this architecture is completely plug-and-play. The build_and_run.sh script automatically parses the source .csv
files and deploys the database to the standard system path /var/lib/snmp/, setting the appropriate access permissions (chmod 666) and transferring 
ownership to the snmp user. Subsequently, using placeholder replacement techniques, it injects the network addresses and ports into the proxy 
script and writes the routing commands into /etc/snmp/snmpd.conf.
