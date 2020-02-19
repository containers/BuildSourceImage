# Layout of Source Image

## Overview

This tool builds an [OCI Image](https://github.com/opencontainers/image-spec/blob/master/config.md) comprised of the sources that correspond to another "works" image.
This source image can be pushed to a container registry that satisfies the [OCI Distribution API](https://github.com/opencontainers/distribution-spec).
In this way the source code is available in equivalent access as the works (binaries).

## use case

For the sake of this document the reference example will be building a source image from Source RPMs (SRPMs).

The current command to build this is:
```shell
$ ls SRCRPMS/*.src.rpm | wc -l
103
$ ./BuildSourceImage.sh -o ./output -s ./SRCRPMS/
[SrcImg][INFO] calling source collection drivers
[SrcImg][INFO]  --> context_dir
[SrcImg][INFO]  --> extra_src_dir
[SrcImg][INFO]  --> rpm_dir
[SrcImg][INFO]  --> rpm_fetch
[SrcImg][INFO] packed 'oci:/home/vbatts/src/github.com/containers/BuildSourceImage/SrcImg/tmp/SrcImg.z3HxHN:latest-source'
[SrcImg][INFO] succesfully packed 'oci:/home/vbatts/src/github.com/containers/BuildSourceImage/SrcImg/tmp/SrcImg.z3HxHN:latest-source'
[SrcImg][INFO] copied to oci:./output:latest-source
```

## The Output Image

From the example above, `oci:./output:latest-source` is where the source image is written to.
This is an [OCI Image Layout](https://github.com/opencontainers/image-spec/blob/v1.0.1/image-layout.md).

```shell
./output
├── blobs
│   └── sha256
│       ├── 01db9482eb66aa679d84e1737f0fb3f97424b7e758c8dff0567bfafbcd13dca0
[...]
│       └── fc02f78fb2d75df57893716d9beed4ea86d3adec8ef5aa7cbf6a52fb24ac0a79
├── index.json
└── oci-layout

2 directories, 107 files
```

### image-index (manifest-list)

At the root of this output is the `index.json` which an [OCI image-index](https://github.com/opencontainers/image-spec/blob/v1.0.1/image-index.md).
For our example, here are the [`jq` formatted] contents of `index.json`:

```json
{
  "schemaVersion": 2,
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:60632c06e3ff9637fd5e5feb3f8768590fc94f9a701f99bc88a8f9e07c737b71",
      "size": 1935,
      "annotations": {
        "com.redhat.image.type": "source",
        "org.opencontainers.image.ref.name": "latest-source"
      }
    }
  ]
}
```

The list of a single manifest points to digest `sha256:60632c06e3ff9637fd5e5feb3f8768590fc94f9a701f99bc88a8f9e07c737b71`.
_Notice_: We are overloading the use of the mediaType `application/vnd.oci.image.manifest.v1+json` so that the nested list of "`layers`" objects are nicely handled by the endpoint registry's garbage-collection.
Here we include "`annotations`" denoting both the image tag, as well as an arbitrary type to indicate the type of this image.
Using a "type" in this way is a complement pattern to the "platform.os" of a runnable container image.

### manifest

Using the digest pointed to in the image-index, is the [OCI manifest](https://github.com/opencontainers/image-spec/blob/v1.0.1/manifest.md) for this source image.
Generally these manifest are geared for runnable container images, that will be fetched and composed from layers of file systems.
For this first version of source container images, the layers are file systems, but that contain the source objects that a corresponding runnable image are comprised of.

```json
{
  "schemaVersion": 2,
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "sha256:6083b2ea7b049ca9cc1d4708c160aec7a145960207be3c7bea19bec7e46f1ed1",
    "size": 948
  },
  "layers": [
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar",
      "size": 20480,
      "digest": "sha256:f24d714aee6b35aa16ddd892d3b789678e703ca09fa64ecf966ca1c58a388c62",
      "annotations": {
        "source.artifact.filename": "basesystem-10.0-7.el7.centos.src.rpm",
        "source.artifact.name": "basesystem",
        "source.artifact.version": "10.0",
        "source.artifact.epoch": "10.0",
        "source.artifact.release": "7.el7.centos",
        "source.artifact.mimetype": "application/x-rpm",
        "source.artifact.pkgid": "d5194181f6f572552e89e2d721612492",
        "source.artifact.buildtime": "1403865430"
      }
    },
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar",
      "size": 20480,
      "digest": "sha256:4b6016d4b66e9cfd6a3731e22ac3805b648ddd06e2b13c9530475409ee3e3514",
      "annotations": {
        "source.artifact.filename": "rootfiles-8.1-11.el7.src.rpm",
        "source.artifact.name": "rootfiles",
        "source.artifact.version": "8.1",
        "source.artifact.epoch": "8.1",
        "source.artifact.release": "11.el7",
        "source.artifact.mimetype": "application/x-rpm",
        "source.artifact.pkgid": "e1cca1fe49265b419a01a686194406ef",
        "source.artifact.buildtime": "1402344692"
      }
    },
    [...]
```

Here we point to a "config" for the sake of compatibility, and have "layers" of the source image.
Each layer is the sources of a component of the resulting image.
Again, for the sake of compatibility with older clients, each layer has the source stored in a TAR archive.

Since each item in the array of layers is an [OCI image descriptor](https://github.com/opencontainers/image-spec/blob/v1.0.1/descriptor.md#properties), we utilize attaching annotations to each source object.
These annotation keys are to give insight to the nature of the content in the referenced blob.
Also, while there may be annotations specific to the mimetype of source i.e. `source.artifact.epoch` and `source.artifact.pkgid` are generally RPM specific, the keys are intended to be generic across source types.
Obviously having these kinds of generic, comparable values is a known challenge.

### Config

For this first version of source images, the "`config`" pointed to by the mediaType "`application/vnd.oci.image.config.v1+json`" is the most pointless, but is there for broadest reception by client tooling.
This is where the environment variables and command entrypoints would exist, but we have none.
Here is the [`jq` formatted] contents of that config blob:

```json
{
  "created": "2020-02-06T14:02:23.746051982-05:00",
  "architecture": "amd64",
  "os": "linux",
  "config": {},
  "rootfs": {
    "type": "layers",
    "diff_ids": [
      "sha256:f24d714aee6b35aa16ddd892d3b789678e703ca09fa64ecf966ca1c58a388c62",
      "sha256:4b6016d4b66e9cfd6a3731e22ac3805b648ddd06e2b13c9530475409ee3e3514",
      "sha256:09ca0817168b2cbd93e06a1b31a44f611e308abd2591df3c8f9d5d633668de19"
    ]
  },
  "history": [
    {
      "created": "2020-02-06T14:02:23.180531458-05:00",
      "created_by": "#(nop) BuildSourceImage.sh version 0.2.0-dev adding artifact: 8731e2c6d61bdebe2ac2301fdd80ea3223830f2b37c04511a48820f3b8b68b55"
    },
    {
      "created": "2020-02-06T14:02:23.466891360-05:00",
      "created_by": "#(nop) BuildSourceImage.sh version 0.2.0-dev adding artifact: 676c8563e990f5312fc3de24be00a955fe302eee47f06b3c0a1935d472d6073b"
    },
    {
      "created": "2020-02-06T14:02:23.746051982-05:00",
      "created_by": "#(nop) BuildSourceImage.sh version 0.2.0-dev adding artifact: 708825c991ae0a190d0e28fed3ca3d0874d5d9fedd8d6ad83fb0c77a8636d11d"
    }
  ]
}
```

Honestly, none of this current data structure should be used be any clients of source images.
Though any clients that are not aware of source images, could still fetch these data structures, and not strictly fail to unknown types.

#### Next generation config

Ideally this "config" will be document like a software bill of materials (SBOM).
Join the OCI weekly discussions, and follow the [OCI Artifacts](https://github.com/opencontainers/artifacts) for possibilities.

### Blobs

In the first version of this source image approach, each of the "layer" blobs is a tar archive, as most container runtimes and registries expect.

During this source image version that layers are TAR archives, the format of their contents are as follows:

* a "blobs" top-level directory
  * the source object itself is stored in a [blob digest](https://github.com/opencontainers/image-spec/blob/v1.0.1/descriptor.md#digests) directory structure
* a source-collector top-level directory
  * the file name of source object, as a symlink pointing to the hashed blob

```shell
$ file ./output/blobs/sha256/fc02f78fb2d75df57893716d9beed4ea86d3adec8ef5aa7cbf6a52fb24ac0a79
./output/blobs/sha256/fc02f78fb2d75df57893716d9beed4ea86d3adec8ef5aa7cbf6a52fb24ac0a79: gzip compressed data, original size 399360
$ tar tvf ./output/blobs/sha256/fc02f78fb2d75df57893716d9beed4ea86d3adec8ef5aa7cbf6a52fb24ac0a79
drwxrw-rw- root/root         0 1969-12-31 19:00 ./
drwxrwxrwx root/root         0 1969-12-31 19:00 ./blobs/
drwxrwxrwx root/root         0 1969-12-31 19:00 ./blobs/sha256/
-rw-rw-rw- root/root    392884 1969-12-31 19:00 ./blobs/sha256/f78861cf3acb8335b7c4c0fee9286f0f8e8743c64f6698a9f8de8f92e2f31454
drwxrwxrwx root/root         0 1969-12-31 19:00 ./rpm_dir/
lrwxrwxrwx root/root         0 1969-12-31 19:00 ./rpm_dir/libverto-0.3.0-8.fc31.src.rpm -> ../blobs/sha256/f78861cf3acb8335b7c4c0fee9286f0f8e8743c64f6698a9f8de8f92e2f31454
```

Logic being: trying to eliminate chances of collision of objects when a collection of these source layers are unpacked together.


## Unpacked

Unpacking these "layers" will create a folder of all the source artifacts that comprise the source image.

```shell
$ ./BuildSourceImage.sh unpack ./output/ ./unpack
[SrcImg][INFO] [unpacking] layer sha256:16644f25b9842037fcedcee7740f8bb5d56ab2045923924b14814a7a9ddb068b
[SrcImg][INFO] [unpacking] layer sha256:3287455f170c017e664c0b78e3161fe586d835d774c562fe7f289972cd3df1da
[...]
[SrcImg][INFO] [unpacking] layer sha256:918c58b1e7feb07f04d9119b1f8faa0d0d9dd5d6f08221124ddd422a3c462f5d
[SrcImg][INFO] [unpacking] layer sha256:e49c55a056bc351e5df5183e361d97bc5d224a802a42d81834c4cabb404f13d6
```

This destination directory that has been unpacked to will be in a nested `rootfs/` directory.
A behavior inherited from `umoci`.

Each of the "source collection drivers" makes a subdirectory for the artifacts it collects.

