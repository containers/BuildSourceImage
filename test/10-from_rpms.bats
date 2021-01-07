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
	[ -f "${d}/blobs/sha256/0a7d6bf1ec0c131b804cc85018b998988b39b66594db73475cf21adb54ab77d5" ]
	[ -f "${d}/blobs/sha256/b890aaedaf242fa7b42a467cffa2ead943171f34c4d81d566c198829f4e16e00" ]
	[ -f "${d}/blobs/sha256/e4d273091c8390bedb25ed76271faf1ef24d4456453b0a4eb305b0d202b9c3c6" ]
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
