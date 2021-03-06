SHELL := /bin/bash

# NOTE: this requires a kernel with tools/lib/bpf bulit (for libbpf.so)
LINUX_SOURCE=../linux
# ^^ is there a better way to do this??
# Perhaps just copy the relevant files in?
IFLAGS:=-I$(LINUX_SOURCE)/tools/lib -I$(LINUX_SOURCE)/tools/perf -I$(LINUX_SOURCE)/tools/include
LDFLAGS:=-lelf

OBJECTS:=$(LINUX_SOURCE)/tools/lib/bpf/libbpf.so bpf_load.o cjson/cJSON.o

CFLAGS:=-g -O2 -Wall -Wextra
.PHONY: all load unload clean setup py-c-hash

all: xdp-flowradar.o xdp-flowradar dump_maps py-c-hash

cjson/cJSON.o:
	make -C cjson

$(LINUX_SOURCE)/tools/lib/bpf/libbpf.so:
	make -C $(LINUX_SOURCE)/tools/lib/bpf/

xdp-flowradar.o: xdp-flowradar_kern.c bpf_helpers.h common.h data.h
	clang $(CFLAGS) -target bpf -c xdp-flowradar_kern.c -o xdp-flowradar.o

xdp-flowradar: xdp-flowradar_user.c $(OBJECTS) common.h data.h
	clang $(CFLAGS) $(IFLAGS) $(LDFLAGS) $(OBJECTS) xdp-flowradar_user.c -o xdp-flowradar

dump_maps: dump_maps.c common.h $(OBJECTS) data.h
	clang $(CFLAGS) $(IFLAGS) $(LDFLAGS) $(OBJECTS) dump_maps.c -o dump_maps

bpf_load.o: bpf_load.c bpf_load.h
	clang $(CFLAGS) $(IFLAGS) -c bpf_load.c -o bpf_load.o

test-hash: test-hash.c xdp-flowradar_kern.c
	clang $(CFLAGS) test-hash.c -o test-hash

unload:
	sudo ip netns exec h1 ip l set dev h1-eth0 xdp off || true

clean:
	rm -f test-hash
	rm -f xdp-flowradar
	rm -f dump_maps
	rm -f *.o
	rm -f *.so

setup: clean
	sudo ln -s /proc/$(shell pgrep -f "mininet:h1$$")/ns/net /var/run/netns/h1

dump: xdp-flowradar.o
	llvm-objdump -S xdp-flowradar.o

activate:
	python3 -m venv venv
	( \
		source venv/bin/activate; \
		pip install -r requirements.txt; \
	)

aggregate: activate
	./aggregate.py dumped.json parsed.json

py-c-hash: cHash.cpython-36m-x86_64-linux-gnu.so

cHash.cpython-36m-x86_64-linux-gnu.so: venv/ chash.c setup.py
	source venv/bin/activate && python setup.py build_ext --inplace
