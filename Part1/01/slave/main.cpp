#include <iostream>
#include <fstream>
#include <string>
#include <sqlite3.h>
#include "mongoose.h"

using namespace std;

string db_file = "";
string port = "";
string listen_ip = "";

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
            
            result = "{\"status\":\"success\", \"source\":\"Network_Slave\", \"value\":\"" + val + "\", \"unit\":\"" + unit + "\", \"time\":\"" + time + "\"}";
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
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

            string json_response = query_local_db(s_type, s_id);

            if (json_response != "") {
                mg_http_reply(c, 200, "Content-Type: application/json\r\n", "%s", json_response.c_str());
            } else {
                string error_msg = "{\"status\":\"error\", \"message\":\"Sensor not found in this Slave node!\"}";
                mg_http_reply(c, 404, "Content-Type: application/json\r\n", "%s", error_msg.c_str());
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
    
    if (port == "") {
    cout << "Error: PORT is missing in " << config_file << "!" << endl;
    cout << "System Halted." << endl;
    return 1;
}

    cout << "Using configuration file: " << config_file << endl;
    cout << "Starting Slave Node..." << endl;
    cout << "Listening on IP: " << listen_ip << " , Port: " << port << endl;
    cout << "Using Database: " << db_file << endl;

    struct mg_mgr mgr;
    mg_mgr_init(&mgr);
    
    string listen_url = "http://" + listen_ip + ":" + port;
    mg_http_listen(&mgr, listen_url.c_str(), ev_handler, NULL);

    while (true) {
        mg_mgr_poll(&mgr, 1000);
    }
    
    mg_mgr_free(&mgr);
    return 0;
}