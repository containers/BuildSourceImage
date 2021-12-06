#!/usr/bin/env bats -t

load helpers

@test "build from RPMS" {
	local d
	d=$(mktemp -d)
	echo "temporary directory: ${d}"

	run_ctr -v $(pwd)/.testprep/srpms/:/src:ro --mount type=bind,source=${d},destination=/output $CTR_IMAGE -s /src -o /output
	[ "$status" -eq 0 ]
	echo ${lines}
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
	[ -f "${d}/blobs/sha256/5266b3106c38b4535e314ff52faa3bcf1e9c8256738469381e147c81d700201a" ]
	[ -f "${d}/blobs/sha256/56fb92b015150dd20c581f3a15035a67bc017f41d3115e9ce526a760e27acdfb" ]
	[ -f "${d}/blobs/sha256/6fd6b2113b8afdd00c25585f75330039981ad3d59a63c5f7d45707f1bdc7bafe" ]
}

@test "build from RPMS and push" {
	skip "deprecating push/pull. Use 'skopeo' instead."
	local d
	d=$(mktemp -d)
	echo "temporary directory: ${d}"

	run_ctr -v $(pwd)/.testprep/srpms/:/src:ro --mount type=bind,source=${d},destination=/output $CTR_IMAGE -s /src -p oci:/output/pushed-image:latest-source
	[ "$status" -eq 0 ]

	run ls ${d}/pushed-image
	[ "$status" -eq 0 ]
}
