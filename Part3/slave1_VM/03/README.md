## 1. Broker Installation Guide
To establish the asynchronous Publish/Subscribe messaging layer, the Eclipse Mosquitto MQTT broker and its C/C++ development libraries must be installed on the host machine (VM 50 - Master Node).

```bash
# Update package repositories
sudo apt update

# Install Mosquitto daemon and client utilities
sudo apt install -y mosquitto mosquitto-clients libmosquitto-dev

# Verify service state and enable it to start on boot
sudo systemctl enable mosquitto
sudo systemctl start mosquitto
sudo systemctl status mosquitto 

## 2. MQTT Configuration Guide
The system avoids hardcoding by parsing MQTT configurations dynamically at runtime from a config.example file.

BROKER_IP=127.0.0.1: Specifies the target IP address of the central Mosquitto Broker daemon.

BROKER_PORT=1883: Binds connections to the standard unencrypted MQTT TCP port.

NODE_ID: Defines the unique identity for worker delegation (e.g., slave1, slave2).

Protocol Version: MQTT v3.1.1 is utilized due to its lightweight header footprint (minimum 2 bytes) and high stability in Linux embedded environments.

Quality of Service (QoS): QoS 1 (At least once delivery) is configured to guarantee packet arrival using PUBACK acknowledgments without incurring the multi-step handshake latency of QoS 2.

3. Topic Structure
To isolate public client-facing requests from internal inter-node coordination, a dual-layer hierarchical topic tree is implemented:

Client to Master (External Request):
gateway/request/<sensor_type>/<sensor_id>

Master to Client (External Response):
gateway/response/<sensor_type>/<sensor_id>

Master to Slave (Internal Delegation):
internal/<node_id>/request/<sensor_type>/<sensor_id>

Slave to Master (Internal Response):
internal/<node_id>/response/<sensor_type>/<sensor_id>

4. How to Run the Programs
you can use the automaution script build_and_run.sh ti run all 3 VMs and for speed testing , use benchmark_read.sh in the VM50 files.

5. How to Send Requests using mosquitto_pub
Clients or test scripts dispatch sensor queries by publishing empty payloads with QoS 1 to the public request channel.

# Querying Temperature Sensor (ID: 101)
mosquitto_pub -h 127.0.0.1 -p 1883 -q 1 -t "gateway/request/temperature/101" -m ""

# Querying Remote CO2 Sensor (ID: 204)
mosquitto_pub -h 127.0.0.1 -p 1883 -q 1 -t "gateway/request/co2/204" -m ""

6. How to Receive Responses using mosquitto_sub
Clients listen asynchronously on response channels to capture the formatted JSON payloads returned by the Master node.
# Subscribe to all gateway responses (Exits after receiving 1 message via -C 1)
mosquitto_sub -h 127.0.0.1 -p 1883 -q 1 -t "gateway/response/#" -C 1
Example JSON Response:

JSON
{
  "status": "success",
  "node": "master",
  "value": "24.8",
  "unit": "C",
  "time": "2026-06-01 10:15:00",
  "source": "Memcached_RAM",
  "master_response_time_ms": 0.642
}

7. How to Run the Test Script
An automated bash script (benchmark_read.sh) is provided to query all unique sensors across two consecutive rounds (Cold Start vs. Warm Cache) to evaluate system performance.
cd scripts
chmod +x benchmark_mqtt.sh

./benchmark_mqtt.sh


8. Response Time Comparison
The automated benchmark evaluates the distributed caching architecture over two rounds. The logic utilizes a Look-Aside caching pattern: whenever data is read from a local database or received from a Slave node, the Master writes a copy of it into its own L1 Memcached RAM. you can see the reults in the image i uploade in my report pdf.
Empirical Benchmark Findings

Sensor Query          | Round 1 Source (Cold Cache) | Round 1 Total RTT | Round 2 Source (Warm Cache) | Round 2 Total RTT
-------------------------------------------------------------------------------------------------------------------------
co2 (ID: 204)         | Slave_SQLite                | 176 ms            | Memcached_RAM               | 27 ms
humidity (ID: 102)    | Master_SQLite               | 274 ms            | Memcached_RAM               | 20 ms
humidity (ID: 202)    | Slave_SQLite                | 134 ms            | Memcached_RAM               | 22 ms
temperature (301)     | Slave_SQLite                | 211 ms            | Memcached_RAM               | 72 ms