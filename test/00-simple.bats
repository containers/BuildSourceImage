#!/usr/bin/env bats -t

load helpers

@test "Help" {
	run_ctr $CTR_IMAGE -h
	[ "$status" -eq 0 ]
	[[ ${lines[0]} =~ "BuildSourceImage.sh version " ]]
	[[ ${lines[1]} =~ "Usage: BuildSourceImage.sh " ]]
}

@test "Version" {
	run_ctr $CTR_IMAGE -v
	[ "$status" -eq 0 ]
	[[ ${lines[0]} =~ "BuildSourceImage.sh version " ]]
}

@test "List Drivers" {
	run_ctr $CTR_IMAGE -l
	[ "$status" -eq 0 ]
	[[ ${lines[0]} =~ "sourcedriver_context_dir" ]]
	[[ ${lines[1]} =~ "sourcedriver_extra_src_dir" ]]
	[[ ${lines[2]} =~ "sourcedriver_rpm_dir" ]]
	[[ ${lines[3]} =~ "sourcedriver_rpm_fetch" ]]
}

@test "No input" {
	run_ctr $CTR_IMAGE
	[ "$status" -eq 1 ]
	[[ ${lines[0]} =~ "[SrcImg][ERROR] provide an input (example: BuildSourceImage.sh -e ./my-sources/ )" ]]
}
