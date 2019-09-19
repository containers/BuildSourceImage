#!/usr/bin/env bats -t

load helpers

@test "Build from image reference" {
	d=$(mktemp -d)
    ref="registry.fedoraproject.org/fedora-minimal"
	run_ctr -v ${d}:/output/ $CTR_IMAGE -i "${ref}"
	[ "$status" -eq 0 ]
	#echo ${lines[@]}
	[[ ${lines[0]} =~ "Getting image source signatures" ]]
	[[ ${lines[1]} =~ "Copying blob " ]]
	[[ ${lines[5]} =~ "[SrcImg][INFO] [unpacking] layer sha256:" ]]
    [[ ${lines[6]} =~ "[SrcImg][INFO] inspecting image reference ${ref}:" ]]
	[[ ${lines[7]} =~ "[SrcImg][INFO] calling source collection drivers" ]]
	# get the number of the last line
	n=$(expr ${#lines[@]} - 1)
	[[ ${lines[${n}]} =~ "[SrcImg][INFO] copied to oci:/output:latest-source" ]]
	
	echo "${d}"
	[ -f "${d}/index.json" ]
	[ -f "${d}/oci-layout" ]
	[ "$(du -b ${d}/index.json | awk '{ print $1 }')" -gt 0 ]
	[ "$(du -b ${d}/oci-layout | awk '{ print $1 }')" -gt 0 ]
	[ "$(find ${d} -type f | wc -l)" -gt 5 ]
}
