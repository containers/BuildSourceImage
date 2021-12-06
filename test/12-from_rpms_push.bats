#!/usr/bin/env bats -t

load helpers

# To test skopeo-copy in the provided container image, we are running a local
# registry that we're starting and shutting down on-demand.

setup() {
	run $CTR_ENGINE run -d --name bsi-test-registry --net=host -p 5000:5000 registry:2
}

teardown() {
	run $CTR_ENGINE rm -f bsi-test-registry
}

@test "build from RPMS and push to local registry" {
	skip "deprecating push/pull. Use 'skopeo' instead"

	local d
	d=$(mktemp -d)
	echo "temporary directory: ${d}"

	run_ctr -v $(pwd)/.testprep/srpms/:/src:ro --net=host --mount type=bind,source=${d},destination=/output $CTR_IMAGE -s /src -o /output -p docker://localhost:5000/output:latest-source
	[ "$status" -eq 0 ]

	echo "${d}"
	[ -f "${d}/index.json" ]
	[ -f "${d}/oci-layout" ]
	[ "$(du -b ${d}/index.json | awk '{ print $1 }')" -gt 0 ]
	[ "$(du -b ${d}/oci-layout | awk '{ print $1 }')" -gt 0 ]

	# let's press that the files are predictable
	[ "$(find ${d} -type f | wc -l)" -eq 7 ]
	[ -f "${d}/blobs/sha256/5266b3106c38b4535e314ff52faa3bcf1e9c8256738469381e147c81d700201a" ]
	[ -f "${d}/blobs/sha256/56fb92b015150dd20c581f3a15035a67bc017f41d3115e9ce526a760e27acdfb" ]
	[ -f "${d}/blobs/sha256/6fd6b2113b8afdd00c25585f75330039981ad3d59a63c5f7d45707f1bdc7bafe" ]

	# now let's pull the image with skopeo
	mkdir ${d}/pull
	run skopeo copy --src-tls-verify=false docker://localhost:5000/output:latest-source dir:${d}/pull
}
