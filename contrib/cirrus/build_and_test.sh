#!/usr/bin/env bash

set -e

source $(dirname $0)/lib.sh

cd $CIRRUS_WORKING_DIR

showrun echo "Validating..."
showrun make validate

showrun echo "Building container image..."
showrun make validate

showrun echo "Running integration tests..."
showrun make test-integration
