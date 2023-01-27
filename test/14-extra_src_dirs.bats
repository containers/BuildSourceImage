#!/usr/bin/env bats -t

load helpers

@test "build with multiple extra source directories" {
	local d
	d=$(mktemp -d)
	echo "temporary directory: ${d}"

	extra_dir1=$(mktemp -d)
	echo 123 > $extra_dir1/123.txt
	extra_dir2=$(mktemp -d)
	echo 456 > $extra_dir1/456.txt

	run_ctr -v $(pwd)/.testprep/srpms/:/src:ro --mount type=bind,source=${d},destination=/output $CTR_IMAGE -e $extra_dir1 -e $extra_dir2 -o /output
	[ "$status" -eq 0 ]
	echo ${lines}
	[[ ${lines[0]} =~ "[SrcImg][INFO] calling source collection drivers" ]]
	[[ ${lines[3]} =~ "[SrcImg][INFO] adding extra source directory $extra_dir1" ]]
	# get the number of the last line
	n=$(expr ${#lines[@]} - 1)
	[[ ${lines[${n}]} =~ "[SrcImg][INFO] copied to oci:/output:latest-source" ]]

	echo "${d}"
	[ -f "${d}/index.json" ]
	[ -f "${d}/oci-layout" ]
	[ "$(du -b ${d}/index.json | awk '{ print $1 }')" -gt 0 ]
	[ "$(du -b ${d}/oci-layout | awk '{ print $1 }')" -gt 0 ]

	# let's press that the files are predictable
	[ "$(find ${d} -type f | wc -l)" -eq 6 ]
	[ -f "${d}/blobs/sha256/124edef61b84f2d3562d33780906711943c04b882468840f80bb0c7b11046a1a" ]
	[ -f "${d}/blobs/sha256/9284ecf9d6e9e677b8deb2fa5d7d9aa363bda15e8fd84352241083b94b639b68" ]
}
