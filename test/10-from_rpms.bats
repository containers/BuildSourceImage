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
	[ -f "${d}/blobs/sha256/4ff0b5eb60927dc1aee6a7080790cfcc50765294b5939ea9e4c59ba1d7c83848" ]
	[ -f "${d}/blobs/sha256/81a0ee6e731852c9729cb1beb5d195a08671bd72f00f32be3a63c5243ec95f5c" ]
	[ -f "${d}/blobs/sha256/df4fddb6365e1e652941463dac3054ca58e9302e1bbdc454b611f84fde2e9cdd" ]
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
