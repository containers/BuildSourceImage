[![Build Status](https://travis-ci.org/containers/BuildSourceImage.svg?branch=master)](https://travis-ci.org/containers/BuildSourceImage)

# BuildSourceImage

Tool to build a source image.
The goal is to make retrieving the source code used to make a container image
easier for users to obtain, using the standard OCI protocols and image formats.

## Usage

```bash
$> ./BuildSourceImage.sh -h
BuildSourceImage.sh version 0.1
Usage: BuildSourceImage.sh [-D] [-b <path>] [-c <path>] [-e <path>] [-r <path>] [-o <path>] [-i <image>] [-p <image>] [-l] [-d <drivers>]

       -b <path>        base path for source image builds
       -c <path>        build context for the container image. Can be provided via CONTEXT_DIR env variable
       -e <path>        extra src for the container image. Can be provided via EXTRA_SRC_DIR env variable
       -s <path>        directory of SRPMS to add. Can be provided via SRPM_DIR env variable
       -o <path>        output the OCI image to path. Can be provided via OUTPUT_DIR env variable
       -d <drivers>     enumerate specific source drivers to run
       -l               list the source drivers available
       -i <image>       image reference to fetch and inspect its rootfs to derive sources
       -p <image>       push source image to specified reference after build
       -D               debuging output. Can be set via DEBUG env variable
       -h               this usage information
       -v               version

```

It also nicely usable inside a container
```bash
$> buildah build-using-dockerfile -t containers/buildsourceimage .
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

