#!/bin/bash

export CTR_IMAGE="${CTR_IMAGE:-localhost/containers/buildsourceimage}"
export CTR_ENGINE="${CTR_ENGINE:-podman}"

function run_ctr() {
	run $CTR_ENGINE run --security-opt label=disable --rm "$@"
}
