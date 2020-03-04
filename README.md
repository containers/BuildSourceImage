[![Build Status](https://api.cirrus-ci.com/github/containers/BuildSourceImage.svg)](https://cirrus-ci.com/github/containers/BuildSourceImage/master)
[![Container Image Repository on Quay](https://quay.io/repository/ctrs/bsi/status "Container Image Repository on Quay")](https://quay.io/repository/ctrs/bsi)

# BuildSourceImage

Tool to build a source image.
The goal is to make retrieving the source code used to make a container image
easier for users to obtain, using the standard OCI protocols and image formats.

## Usage

```bash
$> ./BuildSourceImage.sh -h
BuildSourceImage.sh version 0.1
Usage: BuildSourceImage.sh [-D] [-b <path>] [-c <path>] [-e <path>] [-r <path>] [-o <path>] [-p <image>] [-l] [-d <drivers>]

       -b <path>        base path for source image builds
       -c <path>        build context for the container image. Can be provided via CONTEXT_DIR env variable
       -e <path>        extra src for the container image. Can be provided via EXTRA_SRC_DIR env variable
       -s <path>        directory of SRPMS to add. Can be provided via SRPM_DIR env variable
       -o <path>        output the OCI image to path. Can be provided via OUTPUT_DIR env variable
       -d <drivers>     enumerate specific source drivers to run
       -l               list the source drivers available
       -p <image>       push source image to specified reference after build
       -D               debuging output. Can be set via DEBUG env variable
       -h               this usage information
       -v               version

```

Nicely usable inside a container:

```bash
$> mkdir ./output/
$> podman run -it -v $(pwd)/output/:/output/ -v $(pwd)/SRCRPMS/:/data/ -u $(id -u) quay.io/ctrs/bsi -s /data/ -o /output/
```

## Examples

* Building from a fetched reference [![asciicast](https://asciinema.org/a/266340.svg)](https://asciinema.org/a/266340)
* Building from a directory of src.rpms: [![asciicast](https://asciinema.org/a/266341.svg)](https://asciinema.org/a/266341)
* Building from a directory of src.rpms and pushing it to a simple registry: [![asciicast](https://asciinema.org/a/266343.svg)](https://asciinema.org/a/266343)

## Use Cases

* Build a source image from an existing container image by introspection
* Build a source code image from a collection of known `.src.rpm`'s
* Include additional build context into the source image
* Include extra sources use
