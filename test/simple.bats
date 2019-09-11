#!/usr/bin/env bats -t

@test "Help" {
	run $CTR_ENGINE run --rm $CTR_IMAGE -h
	[ "$status" -eq 1 ]
	#TODO: we should exit 0
	[[ ${lines[0]} =~ "BuildSourceImage.sh version " ]]
	[[ ${lines[1]} =~ "Usage: BuildSourceImage.sh " ]]
}

@test "Version" {
	run $CTR_ENGINE run --rm $CTR_IMAGE -v
	[ "$status" -eq 0 ]
	[[ ${lines[0]} =~ "BuildSourceImage.sh version " ]]
}

@test "List Drivers" {
	run $CTR_ENGINE run --rm $CTR_IMAGE -l
	[ "$status" -eq 0 ]
	[[ ${lines[0]} =~ "sourcedriver_context_dir" ]]
	[[ ${lines[1]} =~ "sourcedriver_extra_src_dir" ]]
	[[ ${lines[2]} =~ "sourcedriver_rpm_dir" ]]
	[[ ${lines[3]} =~ "sourcedriver_rpm_fetch" ]]
}
