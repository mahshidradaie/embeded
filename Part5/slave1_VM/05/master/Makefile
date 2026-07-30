all: master_node

master_node: main.cpp mongoose.c
	g++ main.cpp mongoose.c -o master_node -lsqlite3

clean:
	rm -f master_node