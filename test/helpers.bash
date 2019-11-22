#!/bin/bash

export CTR_IMAGE="${CTR_IMAGE:-localhost/containers/buildsourceimage}"
export CTR_ENGINE="${CTR_ENGINE:-podman}"

function run_ctr() {
	run $CTR_ENGINE run --security-opt label=disable --rm "$@"
	# Debugging bats tests can be challenging without seeing std{err,out}
	# of the executed processes. The echo below will only be printed when
	# the command fails and ultimately eases debugging.
	echo "${lines}"
}
