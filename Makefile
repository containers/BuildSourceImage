SRC := ./BuildSourceImage.sh
CTR_IMAGE := localhost/containers/buildsourceimage
CTR_ENGINE ?= podman

all: validate

.PHONY: validate
validate: $(SRC)
	shellcheck $(SRC)

.PHONY: build-container
build-container: Dockerfile
	@echo
	@echo "Building BuildSourceImage Container"
	$(CTR_ENGINE) build --quiet --file Dockerfile --tag $(CTR_IMAGE) .

.PHONY: test-integration
test-integration: build-container
	@echo
	@echo "Running integration tests"
	CTR_IMAGE=$(CTR_IMAGE) CTR_ENGINE=$(CTR_ENGINE) bats test/
