all: slave_node

slave_node: main.cpp
	g++ main.cpp -o slave_node -lsqlite3 -lmemcached -lmosquitto

clean:
	rm -f slave_node