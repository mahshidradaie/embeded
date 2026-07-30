#include <iostream>
#include <fstream>
#include <string>
#include <sqlite3.h>
#include <libmemcached/memcached.h>
#include <chrono>
#include "mongoose.h"

using namespace std;

string db_file = "";
string port = "";
string listen_ip = "";
string slave1_ip = "", slave2_ip = "";
string slave1_port = "", slave2_port = "";


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
            
            if (key == "PORT") port = val;
            else if (key == "LISTEN_IP") listen_ip = val;
            else if (key == "DB_FILE") db_file = val;
            else if (key == "SLAVE1_IP") slave1_ip = val;
            else if (key == "SLAVE1_PORT") slave1_port = val;
            else if (key == "SLAVE2_IP") slave2_ip = val;
            else if (key == "SLAVE2_PORT") slave2_port = val;
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
                 "ORDER BY r.recorded_at DESC LIMIT 1;";

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

string fetch_from_slave(string ip, string s_port, string sensor_type, string sensor_id) {
    if (ip.empty() || s_port.empty()) return "";
    string url = "http://" + ip + ":" + s_port + "/api/sensor?type=" + sensor_type + "\\&id=" + sensor_id;
    string cmd = "curl -s -m 2 " + url; 
    
    string result = "";
    char buffer[128];
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return "";
    while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
        result += buffer;
    }
    pclose(pipe);
    return result;
}

static void ev_handler(struct mg_connection *c, int ev, void *ev_data) {
    if (ev == MG_EV_HTTP_MSG) {
        struct mg_http_message *hm = (struct mg_http_message *) ev_data;
        string uri(hm->uri.buf, hm->uri.len);

        if (uri == "/api/sensor") {
            char s_type[100] = "", s_id[100] = "";
            mg_http_get_var(&hm->query, "type", s_type, sizeof(s_type));
            mg_http_get_var(&hm->query, "id", s_id, sizeof(s_id));

            
            auto start_time = chrono::high_resolution_clock::now();
            
            string cache_key = string(s_type) + "_" + string(s_id);
            string json_response = get_from_cache(cache_key);
            string data_source = "";

            if (!json_response.empty()) {
                
                data_source = "Memcached_RAM";
            } else {
                
                json_response = query_local_db(s_type, s_id);
                if (!json_response.empty()) {
                    data_source = "Master_SQLite";
                    set_to_cache(cache_key, json_response); 
                } else {
                    string s1_res = fetch_from_slave(slave1_ip, slave1_port, s_type, s_id);
                    if (s1_res.find("success") != string::npos) {
                        json_response = s1_res; 
                        data_source = "Network_Slave1";
                        set_to_cache(cache_key, json_response);
                    } else {
                        string s2_res = fetch_from_slave(slave2_ip, slave2_port, s_type, s_id);
                        if (s2_res.find("success") != string::npos) {
                            json_response = s2_res; 
                            data_source = "Network_Slave2";
                            set_to_cache(cache_key, json_response);
                        }
                    }
                }
            }

            
            auto end_time = chrono::high_resolution_clock::now();
            chrono::duration<double, milli> elapsed = end_time - start_time;

            if (!json_response.empty()) {
               
                if (json_response.back() == '}') {
                    json_response.pop_back();
                    char buffer[256];
                    snprintf(buffer, sizeof(buffer), ", \"source\":\"%s\", \"master_response_time_ms\":%.3f}", data_source.c_str(), elapsed.count());
                    json_response += buffer;
                }
                mg_http_reply(c, 200, "Content-Type: application/json\r\n", "%s", json_response.c_str());
            } else {
                char error_msg[256];
                snprintf(error_msg, sizeof(error_msg), "{\"status\":\"error\", \"message\":\"Sensor not found\", \"master_response_time_ms\":%.3f}", elapsed.count());
                mg_http_reply(c, 404, "Content-Type: application/json\r\n", "%s", error_msg);
            }
        } else {
            mg_http_reply(c, 404, "", "Endpoint Not Found\n");
        }
    }
}

int main(int argc, char *argv[]) {
    string config_file = "config.example";
    if (argc > 1) {
        config_file = argv[1];
    }
    
    load_config(config_file);
    
    if (port == "" || listen_ip == "") {
        cout << "Error: LISTEN_IP or PORT is missing in " << config_file << "!" << endl;
        return 1;
    }

    
    memc = memcached_create(NULL);
    memcached_server_st *servers = memcached_server_list_append(NULL, "127.0.0.1", 11211, NULL);
    memcached_server_push(memc, servers);
    memcached_server_list_free(servers);

    cout << "Using configuration file: " << config_file << endl;
    cout << "Starting Master Node with Caching Enabled..." << endl;
    cout << "Listening on IP: " << listen_ip << " , Port: " << port << endl;

    struct mg_mgr mgr;
    mg_mgr_init(&mgr);
    
    string listen_url = "http://" + listen_ip + ":" + port;
    mg_http_listen(&mgr, listen_url.c_str(), ev_handler, NULL);

    while (true) {
        mg_mgr_poll(&mgr, 1000);
    }
    
    memcached_free(memc);
    mg_mgr_free(&mgr);
    return 0;
}