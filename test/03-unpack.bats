#!/usr/bin/env bats -t

load helpers

@test "unpack - no args" {
	run_ctr $CTR_IMAGE unpack
	[ "$status" -eq 1 ]
	[[ ${lines[0]} =~ "[SrcImg][ERROR] [unpack_img] blank arguments provided" ]]
}

@test "unpack - Help" {
	run_ctr $CTR_IMAGE unpack -h
	[ "$status" -eq 1 ]
	[[ ${lines[0]} =~ "BuildSourceImage.sh unpack <oci layout path> <unpack path>" ]]
}

@test "unpack - from a SRPM build" {
	local d
	local r

	d=$(mktemp -d)
	echo "temporary directories: output - ${d}"
	run_ctr -v $(pwd)/.testprep/srpms/:/src:ro --mount type=bind,source=${d},destination=/output $CTR_IMAGE -s /src -o /output
	[ "$status" -eq 0 ]
	[ -f "${d}/index.json" ]

	r=$(mktemp -d)
	echo "temporary directories: unpacked - ${r}"
	run_ctr --mount type=bind,source=${d},destination=/output -v ${r}:/unpacked/ $CTR_IMAGE unpack /output/ /unpacked/
	[ "$(find ${r} -type f | wc -l)" -eq 3 ] # regular files
	[ "$(find ${r} -type l | wc -l)" -eq 3 ] # and symlinks
}
