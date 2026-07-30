#include <iostream>
#include <fstream>
#include <string>
#include <sqlite3.h>
#include "mongoose.h"

using namespace std;

string db_file = "";
string port = "";
string listen_ip = "";
string slave1_ip = "", slave2_ip = "";
string slave1_port = "", slave2_port = "";

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

string query_local_db_history(string sensor_name, string sensor_id, string req_date) {
    sqlite3* db;
    if (sqlite3_open(db_file.c_str(), &db) != SQLITE_OK) return "";

    string sql = "SELECT r.value, strftime('%H:%M:%S', r.recorded_at) FROM sensors s "
                 "JOIN sensor_readings r ON s.sensor_id = r.sensor_id "
                 "WHERE s.sensor_type = '" + sensor_name + "' AND s.sensor_id = '" + sensor_id + "' "
                 "AND date(r.recorded_at) = '" + req_date + "' "
                 "ORDER BY r.recorded_at ASC;";

    sqlite3_stmt* stmt;
    string json = "";
    bool has_data = false;

    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, NULL) == SQLITE_OK) {
        bool first = true;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            if (!has_data) {
                has_data = true;
                json = "{\n";
                json += "  \"sensor_name\": \"" + sensor_name + "\",\n";
                json += "  \"sensor_id\": \"" + sensor_id + "\",\n";
                json += "  \"date\": \"" + req_date + "\",\n";
                json += "  \"values\": [\n";
            }
            if (!first) json += ",\n";
            first = false;

            string val = (const char*)sqlite3_column_text(stmt, 0);
            string time_val = (const char*)sqlite3_column_text(stmt, 1);

            json += "    {\n";
            json += "      \"time\": \"" + time_val + "\",\n";
            json += "      \"value\": \"" + val + "\"\n";
            json += "    }";
        }
        if (has_data) json += "\n  ]\n}"; 
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return json;
}

string fetch_from_slave(string ip, string s_port, string sensor_name, string sensor_id, string req_date) {
    if (ip.empty() || s_port.empty()) return "";

    string cmd = "curl -s -m 2 \"http://" + ip + ":" + s_port + "/api/history?sensor_name=" + sensor_name + "&sensor_id=" + sensor_id + "&date=" + req_date + "\""; 
    
    string result = "";
    char buffer[256];
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return "";
    while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
        result += buffer;
    }
    pclose(pipe);
    return result;
}
string query_local_alerts_db(string sensor_name) {
    sqlite3* db;
    if (sqlite3_open("alerts.db", &db) != SQLITE_OK) return "";

    string sql = "SELECT sensor_id, alert_type, sensor_value, created_at, status FROM alerts "
                 "WHERE sensor_name = '" + sensor_name + "' ORDER BY created_at DESC;";

    sqlite3_stmt* stmt;
    string json = "";
    bool has_data = false;

    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, NULL) == SQLITE_OK) {
        bool first = true;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            if (!has_data) {
                has_data = true;
                json = "{\n  \"sensor_name\": \"" + sensor_name + "\",\n  \"alerts\": [\n";
            }
            if (!first) json += ",\n";
            first = false;

            string s_id = (const char*)sqlite3_column_text(stmt, 0);
            string a_type = (const char*)sqlite3_column_text(stmt, 1);
            string s_val = (const char*)sqlite3_column_text(stmt, 2);
            string c_time = (const char*)sqlite3_column_text(stmt, 3);
            string status = (const char*)sqlite3_column_text(stmt, 4);

            json += "    {\n      \"sensor_id\": \"" + s_id + "\",\n      \"alert_type\": \"" + a_type + "\",\n";
            json += "      \"value\": \"" + s_val + "\",\n      \"time\": \"" + c_time + "\",\n      \"status\": \"" + status + "\"\n    }";
        }
        if (has_data) json += "\n  ]\n}";
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return json;
}

string fetch_alerts_from_slave(string ip, string s_port, string sensor_name) {
    if (ip.empty() || s_port.empty()) return "";
    string cmd = "curl -s -m 2 \"http://" + ip + ":" + s_port + "/api/alerts?sensor_name=" + sensor_name + "\""; 
    string result = "";
    char buffer[256];
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return "";
    while (fgets(buffer, sizeof(buffer), pipe) != NULL) result += buffer;
    pclose(pipe);
    return result;
}
static void ev_handler(struct mg_connection *c, int ev, void *ev_data) {
    if (ev == MG_EV_HTTP_MSG) {
        struct mg_http_message *hm = (struct mg_http_message *) ev_data;
        string uri(hm->uri.buf, hm->uri.len);

        if (uri == "/api/history") {
            char s_name[100] = "", s_id[100] = "", s_date[100] = "";
            mg_http_get_var(&hm->query, "sensor_name", s_name, sizeof(s_name));
            mg_http_get_var(&hm->query, "sensor_id", s_id, sizeof(s_id));
            mg_http_get_var(&hm->query, "date", s_date, sizeof(s_date));

            // 1. Try local Master DB
            string json_response = query_local_db_history(s_name, s_id, s_date);

            // 2. Proxy to Slave 1
            if (json_response == "") {
                string s1_res = fetch_from_slave(slave1_ip, slave1_port, s_name, s_id, s_date);
                if (s1_res.find("\"values\":") != string::npos) json_response = s1_res; 
            }

            // 3. Proxy to Slave 2
            if (json_response == "") {
                string s2_res = fetch_from_slave(slave2_ip, slave2_port, s_name, s_id, s_date);
                if (s2_res.find("\"values\":") != string::npos) json_response = s2_res; 
            }
            
            if (json_response != "") {
                mg_http_reply(c, 200, "Content-Type: application/json\r\n", "%s", json_response.c_str());
            } else {
                string error_msg = "{\"status\":\"error\", \"message\":\"No history found across Master or Slaves for this date!\"}";
                mg_http_reply(c, 404, "Content-Type: application/json\r\n", "%s", error_msg.c_str());
            }
        }
        else if (uri == "/api/alerts") {
            char s_name[100] = "";
            mg_http_get_var(&hm->query, "sensor_name", s_name, sizeof(s_name));
            string s_name_str(s_name);

            
            string json_response = query_local_alerts_db(s_name_str);

            
            if (json_response == "") {
                string s1_res = fetch_alerts_from_slave(slave1_ip, slave1_port, s_name_str);
                if (s1_res.find("\"alerts\":") != string::npos) json_response = s1_res; 
            }

          
            if (json_response == "") {
                string s2_res = fetch_alerts_from_slave(slave2_ip, slave2_port, s_name_str);
                if (s2_res.find("\"alerts\":") != string::npos) json_response = s2_res; 
            }
            
            if (json_response != "") {
                mg_http_reply(c, 200, "Content-Type: application/json\r\n", "%s", json_response.c_str());
            } else {
                string error_msg = "{\"status\":\"error\", \"message\":\"No alerts found across Master or Slaves!\"}";
                mg_http_reply(c, 404, "Content-Type: application/json\r\n", "%s", error_msg.c_str());
            }
        } 
        else {
            mg_http_reply(c, 404, "", "Endpoint Not Found\n");
        } 
    }
}

int main(int argc, char *argv[]) {
    string config_file = "config.example";
    if (argc > 1) config_file = argv[1];
    
    load_config(config_file);
    if (port == "" || listen_ip == "") return 1;

    cout << "Starting Master Gateway (History API)..." << endl;
    cout << "Listening on Port: " << port << endl;

    struct mg_mgr mgr;
    mg_mgr_init(&mgr);
    string listen_url = "http://" + listen_ip + ":" + port;
    mg_http_listen(&mgr, listen_url.c_str(), ev_handler, NULL);

    while (true) mg_mgr_poll(&mgr, 1000);
    mg_mgr_free(&mgr);
    return 0;
}