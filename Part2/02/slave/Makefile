all: slave_node

slave_node: main.cpp mongoose.c
	g++ main.cpp mongoose.c -o slave_node -lsqlite3 -lmemcached

clean:
	rm -f slave_node