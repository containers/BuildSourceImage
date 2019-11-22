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
	[ -f "${d}/blobs/sha256/549ac1e4eb73e55781f39f4b8ee08c1158f1b1c1a523cf278d602386613e2f12" ]
	[ -f "${d}/blobs/sha256/b5d5efc6c334cc52223eaea4ac046f21f089c3088b6abb4de027339e5e6dce4b" ]
	[ -f "${d}/blobs/sha256/ce0608ce0a601a4cac453b0a0e181cac444027d800a26d5b44b80a74c6dc94e8" ]

	# now let's pull the image with skopeo
	mkdir ${d}/pull
	run skopeo copy --src-tls-verify=false docker://localhost:5000/output:latest-source dir:${d}/pull
}
