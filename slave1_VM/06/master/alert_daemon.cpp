#include <iostream>
#include <fstream>
#include <string>
#include <sqlite3.h>
#include <thread>
#include <chrono>

using namespace std;

string db_file = "";

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
        }
    }
}

void check_sensors_and_alert() {
    sqlite3* db;
    if (sqlite3_open(db_file.c_str(), &db) != SQLITE_OK) return;

    string sql = "SELECT s.sensor_id, s.sensor_type, r.value, "
                 "CAST((julianday('now') - julianday(MAX(r.recorded_at))) * 86400 AS INTEGER) AS time_diff "
                 "FROM sensors s LEFT JOIN sensor_readings r ON s.sensor_id = r.sensor_id "
                 "GROUP BY s.sensor_id;";

    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            string s_id = (const char*)sqlite3_column_text(stmt, 0);
            string s_type = (const char*)sqlite3_column_text(stmt, 1);
            const char* val_text = (const char*)sqlite3_column_text(stmt, 2);
            int time_diff = sqlite3_column_int(stmt, 3);

            string alert_type = "";
            string val = (val_text) ? string(val_text) : "NULL";

            if (val_text == NULL ) {
                
            } 
            else {
                try {
                    float f_val = stof(val);
                    if (s_type == "temperature" && (f_val > 24.00 || f_val < -10.0)) alert_type = "TEMP_OUT_OF_RANGE";
                    else if (s_type == "humidity" && (f_val < 20.0 || f_val > 45.0)) alert_type = "HUMIDITY_OUT_OF_RANGE";
                    else if (s_type == "co2" && f_val > 725.0) {
                        alert_type = "CO2_ABOVE_LIMIT"; 
                    }
                    else if (s_type == "motion" && f_val == 1) {
                        alert_type = "MOTION_DETECTED"; 
                    }
                } catch (...) {
                    alert_type = "INVALID_VALUE_FORMAT";
                }
            }

            if (alert_type != "") {
                sqlite3* alert_db;
                if (sqlite3_open("alerts.db", &alert_db) == SQLITE_OK) {
                    
                    string create_table = "CREATE TABLE IF NOT EXISTS alerts ("
                                          "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                                          "sensor_id TEXT, "
                                          "sensor_name TEXT, "
                                          "alert_type TEXT, "
                                          "sensor_value TEXT, "
                                          "created_at DATETIME DEFAULT CURRENT_TIMESTAMP, "
                                          "status TEXT DEFAULT 'NEW');";
                    sqlite3_exec(alert_db, create_table.c_str(), 0, 0, 0);

                    string insert_sql = "INSERT INTO alerts (sensor_id, sensor_name, alert_type, sensor_value) "
                                        "VALUES ('" + s_id + "', '" + s_type + "', '" + alert_type + "', '" + val + "');";
                    sqlite3_exec(alert_db, insert_sql.c_str(), 0, 0, 0);
                    
                    sqlite3_close(alert_db);
                }
                cout << "[ALERT] " << s_type << " (" << s_id << ") -> " << alert_type << endl;
            }
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
}

int main(int argc, char *argv[]) {
    string config_file = "config.example";
    if (argc > 1) config_file = argv[1];
    
    load_config(config_file);
    if (db_file == "") {
        cout << "Error: DB_FILE not found in config!" << endl;
        return 1;
    }

    cout << "Starting Alert Daemon. Monitoring DB: " << db_file << endl;

    while (true) {
        check_sensors_and_alert();
        this_thread::sleep_for(chrono::seconds(10));
    }
    return 0;
}