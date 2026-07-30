#include <iostream>
#include <fstream>
#include <string>
#include <sqlite3.h>
#include "mongoose.h"

using namespace std;

string db_file = "";
string port = "";
string listen_ip = "0.0.0.0";

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

// UPDATED FOR PART 5: Fetch history and build JSON array
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
        if (has_data) {
            json += "\n  ]\n}"; 
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return json;
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

            string json_response = query_local_db_history(s_name, s_id, s_date);

            if (json_response != "") {
                mg_http_reply(c, 200, "Content-Type: application/json\r\n", "%s", json_response.c_str());
            } else {
                string error_msg = "{\"status\":\"error\", \"message\":\"No data found for this date on the Slave Node!\"}";
                mg_http_reply(c, 404, "Content-Type: application/json\r\n", "%s", error_msg.c_str());
            }
        } else {
            mg_http_reply(c, 404, "", "Endpoint Not Found\n");
        }
    }
}

int main(int argc, char *argv[]) {
    string config_file = "config.example";
    if (argc > 1) config_file = argv[1];
    
    load_config(config_file);
    if (port == "") {
        cout << "Error: PORT missing!" << endl;
        return 1;
    }

    cout << "Starting Slave Node (History API)..." << endl;
    cout << "Listening on Port: " << port << endl;

    struct mg_mgr mgr;
    mg_mgr_init(&mgr);
    string listen_url = "http://" + listen_ip + ":" + port;
    mg_http_listen(&mgr, listen_url.c_str(), ev_handler, NULL);

    while (true) mg_mgr_poll(&mgr, 1000);
    mg_mgr_free(&mgr);
    return 0;
}