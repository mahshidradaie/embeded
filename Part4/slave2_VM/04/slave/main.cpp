#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <sqlite3.h>
#include <mosquitto.h>
#include <cstring>

using namespace std;

string db_file = "";
string broker_ip = "";
int broker_port = 0;
string node_id = ""; 


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
            
            if (key == "BROKER_IP") broker_ip = val;
            else if (key == "BROKER_PORT") broker_port = stoi(val);
            else if (key == "DB_FILE") db_file = val;
            else if (key == "NODE_ID") node_id = val;
        }
    }
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
            
            result = "{\"status\":\"success\", \"source\":\"Slave_SQLite\", \"value\":\"" + val + "\", \"unit\":\"" + unit + "\", \"time\":\"" + time + "\"}";
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


void on_message(struct mosquitto *mosq, void *userdata, const struct mosquitto_message *message) {
    if (!message->topic) return;
    string topic(message->topic);
    vector<string> parts = split_topic(topic);

   
    if (parts.size() == 5 && parts[0] == "internal" && parts[1] == node_id && parts[2] == "request") {
        string s_type = parts[3];
        string s_id = parts[4];
        
        string json_response = query_local_db(s_type, s_id);
        string response_topic = "internal/" + node_id + + "/response/" + s_type + "/" + s_id;

        if (json_response != "") {
         
            mosquitto_publish(mosq, NULL, response_topic.c_str(), json_response.length(), json_response.c_str(), 1, false);
        } else {
         
            string error_msg = "{\"status\":\"error\", \"message\":\"Sensor not found in this Slave node!\"}";
            mosquitto_publish(mosq, NULL, response_topic.c_str(), error_msg.length(), error_msg.c_str(), 1, false);
        }
    }
}

int main(int argc, char *argv[]) {
    string config_file = "config.example";
    if (argc > 1) { config_file = argv[1]; }
    
    load_config(config_file);
    
    if (broker_ip == "" || broker_port == 0 || db_file == "" || node_id == "") {
        cout << "Error: Missing BROKER_IP, BROKER_PORT, DB_FILE or NODE_ID in " << config_file << "!" << endl;
        return 1;
    }

    cout << "Starting Slave Node (" << node_id << ") with MQTT Protocol..." << endl;
    cout << "Using Database: " << db_file << endl;

   
    mosquitto_lib_init();
    struct mosquitto *mosq = mosquitto_new(node_id.c_str(), true, NULL);
    mosquitto_message_callback_set(mosq, on_message);

    if(mosquitto_connect(mosq, broker_ip.c_str(), broker_port, 60) != MOSQ_ERR_SUCCESS) {
        cout << "Error connecting to MQTT Broker at " << broker_ip << ":" << broker_port << "!" << endl;
        return 1;
    }

   
    string subscribe_topic = "internal/" + node_id + "/request/#";
    mosquitto_subscribe(mosq, NULL, subscribe_topic.c_str(), 1);
    
    cout << "Connected to MQTT Broker. Listening on: " << subscribe_topic << endl;

  
    mosquitto_loop_forever(mosq, -1, 1);
    
    mosquitto_destroy(mosq);
    mosquitto_lib_cleanup();
    return 0;
}