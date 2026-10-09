PY ?= python3

.PHONY: test run install

test:
	$(PY) -m unittest discover -s tests -v

run:
	qs -p "$(CURDIR)"

install:
	./install.sh
