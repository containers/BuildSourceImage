SRC := ./BuildSourceImage.sh

all: validate

.PHONY: validate
validate: $(SRC)
	shellcheck -a $(SRC)
