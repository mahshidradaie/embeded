#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <sqlite3.h>
#include <libmemcached/memcached.h>
#include <chrono>
#include <mosquitto.h> 

using namespace std;

string db_file = "";
string broker_ip = ""; 
int broker_port = 0;
string memcached_ip = "";
int memcached_port = 0;
string node_id = "";

memcached_st *memc;

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
            
            if (key == "DB_FILE") db_file = val;
            else if (key == "BROKER_IP") broker_ip = val;
            else if (key == "BROKER_PORT") broker_port = stoi(val);
            else if (key == "MEMCACHED_IP") memcached_ip = val;
            else if (key == "MEMCACHED_PORT") memcached_port = stoi(val);
            else if (key == "NODE_ID") node_id = val;
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
            result = "{\"status\":\"success\", \"node\":\"slave\", \"value\":\"" + val + "\", \"unit\":\"" + unit + "\", \"time\":\"" + time + "\"}";
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return result;
}

// Helper to split the MQTT Topic
vector<string> split_topic(const string& topic) {
    vector<string> tokens;
    stringstream ss(topic);
    string item;
    while (getline(ss, item, '/')) {
        tokens.push_back(item);
    }
    return tokens;
}

// The MQTT Callback (Replaces ev_handler)
void on_message(struct mosquitto *mosq, void *userdata, const struct mosquitto_message *message) {
    if (!message->topic) return;
    string topic(message->topic);
    vector<string> parts = split_topic(topic);
    
    // Ensure the request is meant for this specific slave: internal/slaveX/request/<type>/<id>
    if (parts.size() == 5 && parts[0] == "internal" && parts[1] == node_id && parts[2] == "request") {
        string s_type = parts[3];
        string s_id = parts[4];
        
        auto start_time = chrono::high_resolution_clock::now();

        string cache_key = s_type + "_" + s_id;
        string json_response = get_from_cache(cache_key);
        string data_source = "";

        if (!json_response.empty()) {
            data_source = "Memcached_RAM";
        } else {
            json_response = query_local_db(s_type, s_id);
            if (!json_response.empty()) {
                data_source = "Slave_SQLite";
                set_to_cache(cache_key, json_response); 
            }
        }

        auto end_time = chrono::high_resolution_clock::now();
        chrono::duration<double, milli> elapsed = end_time - start_time;
        string response_topic = "internal/" + node_id + "/response/" + s_type + "/" + s_id;

        if (!json_response.empty()) {
            if (json_response.back() == '}') {
                json_response.pop_back();
                char buffer[256];
                snprintf(buffer, sizeof(buffer), ", \"source\":\"%s\", \"slave_response_time_ms\":%.3f}", data_source.c_str(), elapsed.count());
                json_response += buffer;
            }
            // Publish success data back to Master via MQTT
            mosquitto_publish(mosq, NULL, response_topic.c_str(), json_response.length(), json_response.c_str(), 1, false);
        } else {
            char error_msg[256];
            snprintf(error_msg, sizeof(error_msg), "{\"status\":\"error\", \"message\":\"Sensor not found in this Slave node!\", \"slave_response_time_ms\":%.3f}", elapsed.count());
            // Publish error back to Master via MQTT
            mosquitto_publish(mosq, NULL, response_topic.c_str(), string(error_msg).length(), error_msg, 1, false);
        }
    }
}

int main(int argc, char *argv[]) {
    string config_file = "config.example";
    if (argc > 1) { config_file = argv[1]; }
    
    load_config(config_file);
    
    // Safety check to ensure the config file loaded properly
    if (broker_ip == "" || broker_port == 0 || node_id == "" || memcached_ip == "" || memcached_port == 0) {
        cout << "Error: Missing critical configurations (IPs, Ports, or NODE_ID) in " << config_file << "!" << endl;
        return 1;
    }
    
    memc = memcached_create(NULL);
    memcached_server_st *servers = memcached_server_list_append(NULL, memcached_ip.c_str(), memcached_port, NULL);
    memcached_server_push(memc, servers);
    memcached_server_list_free(servers);

    cout << "Using configuration file: " << config_file << endl;
    cout << "Starting " << node_id << " Node with MQTT & Caching..." << endl;
    cout << "Using Database: " << db_file << endl;

    // Initialize MQTT
    mosquitto_lib_init();
    struct mosquitto *mosq = mosquitto_new(node_id.c_str(), true, NULL);
    mosquitto_message_callback_set(mosq, on_message);
    
    if(mosquitto_connect(mosq, broker_ip.c_str(), broker_port, 60) != MOSQ_ERR_SUCCESS) {
        cout << "Error connecting to MQTT Broker at " << broker_ip << ":" << broker_port << "!" << endl;
        return 1;
    }
    
    // Subscribe to internal requests meant for this node
    string sub_topic = "internal/" + node_id + "/request/#";
    mosquitto_subscribe(mosq, NULL, sub_topic.c_str(), 1);

    cout << "Connected to MQTT Broker at " << broker_ip << ":" << broker_port << endl;
    cout << "Connected to Memcached at " << memcached_ip << ":" << memcached_port << endl;
    cout << "Listening on Topic: " << sub_topic << endl;

    // Keep program running, listening for MQTT messages
    mosquitto_loop_forever(mosq, -1, 1);
    
    mosquitto_destroy(mosq);
    mosquitto_lib_cleanup();
    memcached_free(memc);
    return 0;
}