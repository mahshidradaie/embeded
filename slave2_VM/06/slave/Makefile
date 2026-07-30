all: slave_node alert_daemon

slave_node: main.cpp mongoose.c
	g++ main.cpp mongoose.c -o slave_node -lsqlite3

alert_daemon: alert_daemon.cpp
	g++ alert_daemon.cpp -o alert_daemon -lsqlite3 -lpthread

clean:
	rm -f slave_node alert_daemon