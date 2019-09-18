SRC := ./BuildSourceImage.sh
CTR_IMAGE := localhost/containers/buildsourceimage
CTR_ENGINE ?= podman
cleanfiles =

all: validate

validate: .validate

cleanfiles += .validate
.validate: $(SRC)
	shellcheck $(SRC) && touch $@

build-container: .build-container

cleanfiles += .build-container
.build-container: .validate Dockerfile $(SRC)
	@echo
	@echo "Building BuildSourceImage Container"
	$(CTR_ENGINE) build --quiet --file Dockerfile --tag $(CTR_IMAGE) . && touch $@

.PHONY: test-integration
test-integration: .build-container
	@echo
	@echo "Running integration tests"
	CTR_IMAGE=$(CTR_IMAGE) CTR_ENGINE=$(CTR_ENGINE) bats test/


clean:
	if [ -n "$(cleanfiles)" ] ; then rm -rf $(cleanfiles) ; fi
