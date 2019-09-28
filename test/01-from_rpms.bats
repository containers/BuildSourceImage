#!/usr/bin/env bats -t

load helpers

@test "build from RPMS" {
	local d
	d=$(mktemp -d)
	echo "temporary directory: ${d}"

	run_ctr -v $(pwd)/.testprep/srpms/:/src:ro --mount type=bind,source=${d},destination=/output $CTR_IMAGE -s /src -o /output
	[ "$status" -eq 0 ]
	[[ ${lines[0]} =~ "[SrcImg][INFO] calling source collection drivers" ]]
	# get the number of the last line
	n=$(expr ${#lines[@]} - 1)
	[[ ${lines[${n}]} =~ "[SrcImg][INFO] copied to oci:/output:latest-source" ]]

	echo "${d}"
	[ -f "${d}/index.json" ]
	[ -f "${d}/oci-layout" ]
	[ "$(du -b ${d}/index.json | awk '{ print $1 }')" -gt 0 ]
	[ "$(du -b ${d}/oci-layout | awk '{ print $1 }')" -gt 0 ]

	# let's press that the files are predictable
	[ "$(find ${d} -type f | wc -l)" -eq 7 ]
	[ -f "${d}/blobs/sha256/3afb43699ea82a69b16efb215363604d9e4ffe16c9ace7e53df66663847309cf" ]
	[ -f "${d}/blobs/sha256/7f4a50f05b7bd38017be8396b6320e1d2e6a05af097672e3ed23ef3df2ddeadb" ]
	[ -f "${d}/blobs/sha256/8f4e610748f8b58a3297ecf78ecc8ff7b6420c3e559e3e20cad8ac178c6fe4e8" ]
}

@test "build from RPMS and push" {
	local d
	d=$(mktemp -d)
	echo "temporary directory: ${d}"

	run_ctr -v $(pwd)/.testprep/srpms/:/src:ro --mount type=bind,source=${d},destination=/output $CTR_IMAGE -s /src -p oci:/output/pushed-image:latest-source
	[ "$status" -eq 0 ]

	run ls ${d}/pushed-image
	[ "$status" -eq 0 ]
}
