SRC := ./BuildSourceImage.sh
CTR_IMAGE := localhost/containers/buildsourceimage

all: validate

.PHONY: validate
validate: $(SRC)
	shellcheck -a $(SRC)

.PHONY: build-container
build-container: Dockerfile
	podman build -f Dockerfile -t $(CTR_IMAGE) .
