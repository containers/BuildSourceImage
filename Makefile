SRC := ./BuildSourceImage.sh
CTR_IMAGE := localhost/containers/buildsourceimage
CTR_ENGINE ?= podman
cleanfiles =
# these are packages whose src.rpms are very small
srpm_urls = \
	https://archive.kernel.org/centos-vault/7.0.1406/os/Source/SPackages/basesystem-10.0-7.el7.centos.src.rpm \
	https://archive.kernel.org/centos-vault/7.0.1406/os/Source/SPackages/rootfiles-8.1-11.el7.src.rpm \
	https://archive.kernel.org/centos-vault/7.0.1406/os/Source/SPackages/centos-bookmarks-7-1.el7.src.rpm
srpms = $(addprefix ./.testprep/srpms/,$(notdir $(rpms)))

all: validate

validate: .validate

cleanfiles += .validate
.validate: $(SRC)
	shellcheck $(SRC) && touch $@

build-container: .build-container

cleanfiles += .build-container
.build-container: .validate Dockerfile $(SRC)
	@echo
	@echo "==> Building BuildSourceImage Container"
	$(CTR_ENGINE) build --quiet --file Dockerfile --tag $(CTR_IMAGE) . && touch $@

cleanfiles += .testprep $(srpms)
.testprep:
	@echo "==> Fetching SRPMs for testing against"
	mkdir -p $@/{srpms,tmp}
	wget -P $@/srpms/ $(srpm_urls)

.PHONY: test-integration
test-integration: .build-container .testprep
	@echo
	@echo "==> Running integration tests"
	CTR_IMAGE=$(CTR_IMAGE) CTR_ENGINE=$(CTR_ENGINE) TMPDIR=$(shell realpath .testprep/tmp) bats test/


clean:
	if [ -n "$(cleanfiles)" ] ; then rm -rf $(cleanfiles) ; fi
