#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <sqlite3.h>
#include <libmemcached/memcached.h>
#include <chrono>
#include <mosquitto.h> 
#include <cstring>

using namespace std;

string db_file = "";
string broker_ip = ""; 
int broker_port = 0;
string memcached_ip = "";
int memcached_port = 0;

memcached_st *memc;
struct mosquitto *mosq;

void load_config(string config_filename) {
    ifstream file(config_filename.c_str());
    string line;
    while (getline(file, line)) {
        if (line.empty() || line[0] == '#') continue;
        size_t pos = line.find('=');
        if (pos != string::npos) {
            string key = line.substr(0, pos);
            string val = line.substr(pos + 1);
            if (!val.empty() && val[val.length()-1] == '\r') val.erase(val.length()-1);
            
            if (key == "LISTEN_IP" || key == "BROKER_IP") broker_ip = val;
            else if (key == "BROKER_PORT" || key == "PORT") broker_port = stoi(val);
            else if (key == "MEMCACHED_IP") memcached_ip = val;
            else if (key == "MEMCACHED_PORT") memcached_port = stoi(val);
            else if (key == "DB_FILE") db_file = val;
        }
    }
}

string get_from_cache(const string& key) {
    size_t len;
    uint32_t flags;
    memcached_return_t rc;
    char* val = memcached_get(memc, key.c_str(), key.length(), &len, &flags, &rc);
    if (rc == MEMCACHED_SUCCESS && val) {
        string result(val, len);
        free(val); 
        return result;
    }
    return "";
}

void set_to_cache(const string& key, const string& val) {
    memcached_set(memc, key.c_str(), key.length(), val.c_str(), val.length(), 0, 0);
}

string query_local_db(string sensor_type, string sensor_id) {
    sqlite3* db;
    if (sqlite3_open(db_file.c_str(), &db) != SQLITE_OK) return "";

    string sql = "SELECT r.value, s.unit, r.recorded_at FROM sensors s "
                 "JOIN sensor_readings r ON s.sensor_id = r.sensor_id "
                 "WHERE s.sensor_type = '" + sensor_type + "' AND s.sensor_id = '" + sensor_id + "' "
                 "ORDER BY datetime(r.recorded_at) DESC LIMIT 1;";

    sqlite3_stmt* stmt;
    string result = "";
    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            string val = (const char*)sqlite3_column_text(stmt, 0);
            string unit = (const char*)sqlite3_column_text(stmt, 1);
            string time = (const char*)sqlite3_column_text(stmt, 2);
            result = "{\"status\":\"success\", \"node\":\"master\", \"value\":\"" + val + "\", \"unit\":\"" + unit + "\", \"time\":\"" + time + "\"}";
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return result;
}


vector<string> split_topic(const string& topic) {
    vector<string> tokens;
    stringstream ss(topic);
    string item;
    while (getline(ss, item, '/')) {
        tokens.push_back(item);
    }
    return tokens;
}

//The MQTT Callback Function (Replaces Mongoose's ev_handler & fetch_from_slave)
void on_message(struct mosquitto *mosq, void *userdata, const struct mosquitto_message *message) {
    if (!message->topic) return;
    string topic(message->topic);
    string payload = message->payload ? string((char*)message->payload) : "";
    
    vector<string> parts = split_topic(topic);
    
    // SCENARIO A: The Test Script asks the Master for data
    // Topic format: gateway/request/<sensor_type>/<sensor_id>
    if (parts.size() == 4 && parts[0] == "gateway" && parts[1] == "request") {
        string s_type = parts[2];
        string s_id = parts[3];
        string cache_key = s_type + "_" + s_id;
        
        auto start_time = chrono::high_resolution_clock::now();
        string json_response = get_from_cache(cache_key);
        string data_source = "";

        //Check Memcached RAM
        if (!json_response.empty()) {
            data_source = "Memcached_RAM";
        } 
        //Check Local SQLite
        else {
            json_response = query_local_db(s_type, s_id);
            if (!json_response.empty()) {
                data_source = "Master_SQLite";
                set_to_cache(cache_key, json_response);
            }
        }

        // If found locally (RAM or SQLite), Publish the answer back to the script immediately
        if (!json_response.empty()) {
            auto end_time = chrono::high_resolution_clock::now();
            chrono::duration<double, milli> elapsed = end_time - start_time;
            
            if (json_response.back() == '}') {
                json_response.pop_back();
                char buffer[256];
                snprintf(buffer, sizeof(buffer), ", \"source\":\"%s\", \"master_response_time_ms\":%.3f}", data_source.c_str(), elapsed.count());
                json_response += buffer;
            }
            string response_topic = "gateway/response/" + s_type + "/" + s_id;
            mosquitto_publish(mosq, NULL, response_topic.c_str(), json_response.length(), json_response.c_str(), 1, false);
        } 
        // Not found locally! Ask Slave 1 by publishing to its Topic
        else {
            string slave1_req_topic = "internal/slave1/request/" + s_type + "/" + s_id;
            mosquitto_publish(mosq, NULL, slave1_req_topic.c_str(), 0, "", 1, false);
        }
    }
    
    //SCENARIO B: Slave 1 responds to the Master
    //Topic format: internal/slave1/response/<sensor_type>/<sensor_id>
    else if (parts.size() == 5 && parts[0] == "internal" && parts[1] == "slave1" && parts[2] == "response") {
        string s_type = parts[3];
        string s_id = parts[4];
        string final_response_topic = "gateway/response/" + s_type + "/" + s_id;
        
        if (payload.find("\"status\":\"success\"") != string::npos) {
            set_to_cache(s_type + "_" + s_id, payload); // Cache the network data
            mosquitto_publish(mosq, NULL, final_response_topic.c_str(), payload.length(), payload.c_str(), 1, false);
        } else {
            // Slave 1 didn't have it either. Ask Slave 2!
            string slave2_req_topic = "internal/slave2/request/" + s_type + "/" + s_id;
            mosquitto_publish(mosq, NULL, slave2_req_topic.c_str(), 0, "", 1, false);
        }
    }
    
    //SCENARIO C: Slave 2 responds to the Master
    //Topic format: internal/slave2/response/<sensor_type>/<sensor_id>
    else if (parts.size() == 5 && parts[0] == "internal" && parts[1] == "slave2" && parts[2] == "response") {
        string s_type = parts[3];
        string s_id = parts[4];
        string final_response_topic = "gateway/response/" + s_type + "/" + s_id;
        
        if (payload.find("\"status\":\"success\"") != string::npos) {
            set_to_cache(s_type + "_" + s_id, payload); // Cache the network data
            mosquitto_publish(mosq, NULL, final_response_topic.c_str(), payload.length(), payload.c_str(), 1, false);
        } else {
            // Nobody has the data! Return a 404-style error via MQTT
            string error_msg = "{\"status\":\"error\", \"message\":\"Sensor not found in any node!\"}";
            mosquitto_publish(mosq, NULL, final_response_topic.c_str(), error_msg.length(), error_msg.c_str(), 1, false);
        }
    }
}

int main(int argc, char *argv[]) {
    string config_file = "config.example";
    if (argc > 1) { config_file = argv[1]; }
    
    load_config(config_file);
    
    if (broker_ip == "" || broker_port == 0 || memcached_ip == "" || memcached_port == 0) {
        cout << "Error: Missing IP or Port configurations in " << config_file << "!" << endl;
        return 1;
    }
    
    memc = memcached_create(NULL);
    memcached_server_st *servers = memcached_server_list_append(NULL, memcached_ip.c_str(), memcached_port, NULL);
    memcached_server_push(memc, servers);
    memcached_server_list_free(servers);

    //Initializing the Mosquitto Broker Connection
    mosquitto_lib_init();
    mosq = mosquitto_new("MasterNode", true, NULL);
    mosquitto_message_callback_set(mosq, on_message); // Tell MQTT to run on_message() when data arrives
    
    if(mosquitto_connect(mosq, broker_ip.c_str(), broker_port, 60) != MOSQ_ERR_SUCCESS) {
        cout << "Error connecting to MQTT Broker at " << broker_ip << ":" << broker_port << "!" << endl;
        return 1;
    }
    
    // Subscribe to listen to the test script, and listen to the slaves
    mosquitto_subscribe(mosq, NULL, "gateway/request/#", 1);
    mosquitto_subscribe(mosq, NULL, "internal/+/response/#", 1);

    cout << "Starting Master Node with Caching & MQTT Routing..." << endl;
    cout << "Connected to MQTT Broker at " << broker_ip << ":" << broker_port << endl;
    cout << "Connected to Memcached at " << memcached_ip << ":" << memcached_port << endl;

    // This loop keeps the program running forever, listening for MQTT messages
    mosquitto_loop_forever(mosq, -1, 1);
    
    mosquitto_destroy(mosq);
    mosquitto_lib_cleanup();
    memcached_free(memc);
    return 0;
}