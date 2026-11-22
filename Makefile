# PAVÉ - check dependencies, build, download maps, run and test.
#   make            check what is needed, then build
#   make deps       install missing packages (apt, uses sudo)
#   make maps       download all worlds (or: make map-small / map-large / map-copenhagen)
#   make run        start the game (it can also download a map itself on first start)
#   make test       run the self-tests on every installed world
PYTHON   ?= python3
GPRBUILD ?= gprbuild

.PHONY: all check build deps maps map-small map-large map-copenhagen run test media clean

all: check build

check:
	@sh tools/check_deps.sh

build:
	$(GPRBUILD) -p -q -P pave.gpr

deps:
	@sh tools/check_deps.sh --install

maps: map-small map-large map-copenhagen

map-small:
	$(PYTHON) tools/get_map.py small

map-large:
	$(PYTHON) tools/get_map.py large

map-copenhagen:
	$(PYTHON) tools/get_map.py copenhagen

run: build
	./pave

test: build
	@sh tools/run_tests.sh

media: build
	sh tools/make_media.sh

clean:
	rm -rf obj
	rm -f pave
