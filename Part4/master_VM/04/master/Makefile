all: master_node

master_node: main.cpp
	g++ main.cpp -o master_node -lsqlite3 -lmemcached -lmosquitto

clean:
	rm -f master_node