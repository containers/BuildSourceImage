#!/bin/bash
# This script requires an OCI IMAGE Name to pull.
# The script generates a SOURCE Image based on the OCI Image
# Script must be executed on the same OS or newer as the image.

export ABV_NAME="SrcImg"
# TODO maybe a flag for this?
export source_image_suffix="-source"


_usage() {
    echo "Usage: $(basename $0) [-b <path>] [-c <path>] [-e <path>] [-o <path>] [-p] IMAGE"
    echo ""
    echo -e "       -b <path>\tbase path for source image builds"
    echo -e "       -c <path>\tbuild context for the container image. Can be provided via CONTEXT_DIR env variable"
    echo -e "       -e <path>\textra src for the container image. Can be provided via EXTRA_SRC_DIR env variable"
    echo -e "       -o <path>\toutput the OCI image to path. Can be provided via OUTPUT_DIR env variable"
    echo -e "       -d <drivers>\toutput the OCI image to path. Can be provided via OUTPUT_DIR env variable"
    echo -e "       -l\t\tlist the source drivers available"
    echo -e "       -p\t\tpush source image after build"
    echo -e "       -D\t\tdebuging output. Can be set via DEBUG env variable"
    exit 1
}

#
# sanity checks on startup
#
_init() {
    if [ $# -lt 1 ] ; then
        _usage
    fi

    set -o pipefail

    # check for tools we depend on
    for cmd in jq skopeo dnf file find ; do
        if [ -z "$(command -v ${cmd})" ] ; then
            # TODO: maybe this could be individual checks so it can report
            # where to find the tools
            echo "ERROR: please install '${cmd}' package"
        fi
    done
}

_is_sourced() {
    # https://unix.stackexchange.com/a/215279
    # thanks @tianon
    [ "${FUNCNAME[${#FUNCNAME[@]} - 1]}" == 'source' ]
}

# count $character $string
_count() {
    #expr $(echo "${2}" | tr "${1}" '\n' | wc -l) - 1
    c="${2//[^${1}]}"
    echo -n ${#c}
}

# size of file in bytes
_size() {
    local file="${1}"
    stat -c "%s" "${file}" | tr -d '\n'
}

# date timestamp in RFC 3339, to the nanosecond
_date_ns() {
    date --rfc-3339=ns | tr -d '\n'
}

# local `mktemp -d`
_mktemp_d() {
    mktemp -d "${TMPDIR:-/tmp}/${ABV_NAME}.XXXXXX"
}

# local `mktemp`
_mktemp() {
    mktemp "${TMPDIR:-/tmp}/${ABV_NAME}.XXXXXX"
}

# local rm -rf
_rm_rf() {
    debug "rm -rf $@"
    #rm -rf $@
}

# local tar
_tar() {
    if [ -n "${DEBUG}" ] ; then
        tar -v $@
    else
        tar $@
    fi
}

#
# output things, only when $DEBUG is set
#
debug() {
    if [ -n "${DEBUG}" ] ; then
        echo "[${ABV_NAME}][DEBUG] ${@}"
    fi
}

#
# general echo but with prefix
#
info() {
    echo "[${ABV_NAME}][INFO] ${@}"
}

#
# parse the OCI image reference, accounting for:
# * transport name
# * presence or lack of transport port number
# * presence or lack of digest
# * presence or lack of image tag
#

#
# return the image reference's digest, if any
#
parse_img_digest() {
    local ref="${1}"
    local digest=""
    if [ "$(_count '@' ${ref})" -gt 0 ] ; then
        digest="${ref##*@}" # the digest after the "@"
    fi
    echo -n "${digest}"
}

#
# determine image base name (without tag or digest)
#
parse_img_base() {
    local ref="${1%@*}" # just the portion before the digest "@"
    local base="${ref}" default to the same
    if [ "$(_count ':' $(echo ${ref} | tr '/' '\n' | tail -1 ))" -gt 0 ] ; then
        # which means everything before it is the base image name, **including
        # transport (which could have a port delineation), and even a URI
        base="$(echo ${ref} | rev | cut -d : -f 2 | rev )"
    fi
    echo -n "${base}"
}

#
# determine, or guess, the image tag from the provided image reference
#
parse_img_tag() {
    local ref="${1%@*}" # just the portion before the digest "@"
    local tag="latest" # default tag
    if [ "$(_count ':' $(echo ${ref} | tr '/' '\n' | tail -1 ))" -gt 0 ] ; then
        # if there are colons in the last segment after '/', then get that tag name
        tag="$(echo ${ref} | tr '/' '\n' | tail -1 | cut -d : -f 2 )"
    fi
    echo -n "${tag}"
}

#
# an inline prefixer for containers/image tools
#
ref_prefix() {
    local ref="${1}"

    # get the supported prefixes of the current version of skopeo
    IFS=", "
    local pfxs=( $(skopeo copy --help | grep -A1 "Supported transports:" | grep -v "Supported transports") )
    unset IFS

    for pfx in ${pfxs[@]} ; do
        if echo ${ref} | grep -q "^${pfx}:" ; then
            # break when we match
            echo ${ref}
            return 0
        fi
    done
    # else default
    echo "docker://${ref}"
}

#
# an inline namer for the source image
# Initially this is a tagging convention (which if we try estesp/manifest-tool
# can be directly mapped into a manifest-list/image-index).
#
ref_src_img_tag() {
    local ref="${1}"
    echo -n "$(parse_img_tag ${ref})${source_image_suffix}"
}

#
# call out to registry for the image reference's digest checksum
#
fetch_img_digest() {
    local ref="${1}"
    ## TODO: check for authfile, creds, and whether it's an insecure registry
    local dgst=$(skopeo inspect "$(ref_prefix ${ref})" | jq .Digest | tr -d \")
    local ret=$?
    if [ $ret -ne 0 ] ; then
        echo "ERROR: check the image reference: ${ref}" >&2
        return $ret
    fi

    echo -n "${dgst}"
}

#
# pull down the image to an OCI layout
# arguments: image ref
# returns: path:tag to the OCI layout
#
# any commands should only output to stderr, so that the caller can receive the
# path reference to the OCI layout.
#
fetch_img() {
    local ref="${1}"
    local dst="${2}"

    mkdir -p "${dst}"

    local base="$(parse_img_base ${ref})"
    local tag="$(parse_img_tag ${ref})"
    local dgst="$(parse_img_digest ${ref})"
    local from=""
    # skopeo currently only support _either_ tag _or_ digest, so we'll be specific.
    if [ -n "${dgst}" ] ; then
        from="$(ref_prefix ${base})@${dgst}"
    else
        from="$(ref_prefix ${base}):${tag}"
    fi

    ## TODO: check for authfile, creds, and whether it's an insecure registry
    ## destination name must have the image tag included (umoci expects it)
    skopeo \
        copy \
        "${from}" \
        "oci:${dst}:${tag}" >&2
    echo -n "${dst}:${tag}"
}

#
# upack_img <oci layout path> <unpack path>
#
unpack_img() {
    local image_dir="${1}"
    local unpack_dir="${2}"

    if [ -d "${unpack_dir}" ] ; then
        _rm_rf "${unpack_dir}"
    fi

    # TODO perhaps if uid == 0 and podman is present then we can try it?
    if [ -z "$(command -v umoci)" ] ; then
        # can be done as non-root (even in a non-root container)
        unpack_img_umoci "${image_dir}" "${unpack_dir}"
    else
        # can be done as non-root (even in a non-root container)
        unpack_img_bash "${image_dir}" "${unpack_dir}"
    fi
}

#
# unpack an image layout using only jq and bash
#
unpack_img_bash() {
    local image_dir="${1}"
    local unpack_dir="${2}"

    local mnfst_dgst="$(cat "${image_dir}"/index.json | jq '.manifests[0].digest' | tr -d \" )"

    # Since we're landing the reference as an OCI layout, this mediaType is fairly predictable
    # TODO don't always assume +gzip
    layer_dgsts="$(cat ${image_dir}/blobs/${mnfst_dgst/:/\/} | \
        jq '.layers[] | select(.mediaType == "application/vnd.oci.image.layer.v1.tar+gzip") | .digest' | tr -d \")"

    mkdir -vp "${unpack_dir}"
    for dgst in ${layer_dgsts} ; do
        path="${image_dir}/blobs/${dgst/:/\/}"
        tmp_file=$(_mktemp_d)
        zcat "${path}" | _tar -t > $tmp_file # TODO cleanup these files

        # look for '.wh.' entries. They must be removed from the rootfs
        # _before_ extracting the archive, then the .wh. entries themselves
        # need to not remain afterwards
        grep '\.wh\.' "${tmp_file}" | while read line ; do
            # if `some/path/.wh.foo` then `rm -rf `${unpack_dir}/some/path/foo`
            # if `some/path/.wh..wh..opq` then `rm -rf `${unpack_dir}/some/path/*`
            if [ "$(basename ${line})" == ".wh..wh..opq" ] ; then
                _rm_rf "${unpack_dir}/$(dirname ${line})/*"
            elif basename "${line}" | grep -qe '^\.wh\.' ; then
                name=$(basename "${line}" | sed -e 's/^\.wh\.//')
                _rm_rf "${unpack_dir}/$(dirname ${line})/${name}"
            fi
        done

        info "[unpacking] layer ${dgst}"
        # unpack layer to rootfs (without whiteouts)
        zcat "${path}" | _tar --restrict --no-xattr --no-acls --no-selinux --exclude='*.wh.*' -x -C "${unpack_dir}"

        # some of the directories get unpacked as 0555, so removing them gives an EPERM
        find "${unpack_dir}" -type d -exec chmod 0755 "{}" \;
    done
}

#
# unpack using umoci
#
unpack_img_umoci() {
    local image_dir="${1}"
    local unpack_dir="${2}"

    debug "unpackging with umoci"
    # always assume we're not root I reckon
    umoci unpack --rootless --image "${image_dir}" "${unpack_dir}" >&2
}

# TODO this is not worked out yet
push_img() {
    local ref="${1}"
    local path="${2}"

    ## TODO: check for authfile, creds, and whether it's an insecure registry
    skopeo copy "oci:${path}:$(ref_src_img_tag ${ref})" "$(ref_prefix ${ref})"
}

#
# sets up a basic new OCI layout, for an image with the provided (or default 'latest') tag
#
layout_new() {
    local out_dir="${1}"
    local image_tag="${2:-latest}"

    mkdir -p "${out_dir}/blobs/sha256"
    echo '{"imageLayoutVersion":"1.0.0"}' > "${out_dir}/oci-layout"
    local config='
{
  "created": "'$(_date_ns)'",
  "architecture": "amd64",
  "os": "linux",
  "config": {},
  "rootfs": {
    "type": "layers",
    "diff_ids": []
  }
}
    '
    local config_sum=$(echo "${config}" | jq -c | tr -d '\n' | sha256sum | awk '{ print $1 }' | tr -d '\n')
    echo "${config}" | jq -c | tr -d '\n' > "${out_dir}/blobs/sha256/${config_sum}"

    local mnfst='
{
  "schemaVersion": 2,
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "sha256:'"${config_sum}"'",
    "size": '"$(_size ${out_dir}/blobs/sha256/${config_sum})"'
  },
  "layers": []
}
    '
    local mnfst_sum=$(echo "${mnfst}" | jq -c | tr -d '\n' | sha256sum | awk '{ print $1 }' | tr -d '\n')
    echo "${mnfst}" | jq -c | tr -d '\n' > "${out_dir}/blobs/sha256/${mnfst_sum}"

    echo '
{
  "schemaVersion": 2,
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:'"${mnfst_sum}"'",
      "size": '"$(_size ${out_dir}/blobs/sha256/${mnfst_sum})"',
      "annotations": {
        "org.opencontainers.image.ref.name": "'"${image_tag}"'"
      }
    }
  ]
}
    ' | jq -c | tr -d '\n' > "${out_dir}/index.json"
}

# TODO this is not finished yet
# call this for every artifact, to insert it into an OCI layout
# args:
#   * a path to the layout
#   * a path to the artifact
#   * the path inside the tar
#   * tag used in the layout (default is 'latest')
#
layout_insert() {
    local out_dir="${1}"
    local artifact_path="${2}"
    local tar_path="${3}"
    local image_tag="${4:-latest}"

    local mnfst_list="${out_dir}/index.json"
    # get the digest to the manifest
    test -f "${mnfst_list}" || return 1
    local mnfst_dgst="$(cat ${mnfst_list} | jq '
        .manifests[]
        |  select(.annotations."org.opencontainers.image.ref.name" == "'${image_tag}'")
        | .digest
    ' | tr -d \" | tr -d '\n' )"
    local mnfst="${out_dir}/blobs/${mnfst_dgst/:/\/}"
    test -f "${mnfst}" || return 1

    # make tar of new object
    local tmpdir="$(_mktemp_d)"
    # TODO account for "artifact_path" being a directory?
    local sum="$(sha256sum ${artifact_path} | awk '{ print $1 }')"
    # making a blob store in the layer
    mkdir -p "${tmpdir}/blobs/sha256"
    cp "${artifact_path}" "${tmpdir}/blobs/sha256/${sum}"
    if [ "$(basename ${tar_path})" == "$(basename ${artifact_path})" ] ; then
        mkdir -p "${tmpdir}/$(dirname ${tar_path})"
        # TODO this symlink need to be relative path, not to `/blobs/...`
        ln -s "/blobs/sha256/${sum}" "${tmpdir}/${tar_path}"
    else
        mkdir -p "${tmpdir}/${tar_path}"
        # TODO this symlink need to be relative path, not to `/blobs/...`
        ln -s "/blobs/sha256/${sum}" "${tmpdir}/${tar_path}/$(basename ${artifact_path})"
    fi
    local tmptar="$(_mktemp)"

    # zero all the things for as consistent blobs as possible
    _tar -C "${tmpdir}" --mtime=@0 --owner=0 --group=0 --mode='a+rw' --no-xattrs --no-selinux --no-acls -cf "${tmptar}" .
    _rm_rf "${tmpdir}"

    # checksum tar and move to blobs/sha256/$checksum
    local tmptar_sum="$(sha256sum ${tmptar} | awk '{ print $1 }')"
    local tmptar_size="$(_size ${tmptar})"
    mv "${tmptar}" "${out_dir}/blobs/sha256/${tmptar_sum}"

    # find and read the prior config, mapped from the manifest
    local config_sum="$(jq '.config.digest' "${mnfst}" | tr -d \")"

    # use `jq` to append to prior config
    local tmpconfig="$(_mktemp)"
    cat "${out_dir}/blobs/${config_sum/:/\/}" | jq -c \
        --arg date "$(_date_ns)" \
        --arg tmptar_sum "${tmptar_sum}" \
        --arg sum "${sum}" \
        '
        .created = "$date"
        | .rootfs.diff_ids = .rootfs.diff_ids + [
            "sha256:$tmptar_sum"
        ]
        | .history = .history + [
            {
                "created": "$date",
                "created_by": "#(nop) BuildSourceImage adding artifact: $sum"
            }
        ]
        ' > "${tmpconfig}"
    _rm_rf "${out_dir}/blobs/${config_sum/:/\/}"

    # rename the config blob to its new checksum
    local tmpconfig_sum="$(sha256sum ${tmpconfig} | awk '{ print $1 }')"
    local tmpconfig_size="$(_size ${tmpconfig})"
    mv "${tmpconfig}" "${out_dir}/blobs/sha256/${tmpconfig_sum}"

    # append layers list in the manifest, and its new config mapping
    local tmpmnfst="$(_mktemp)"
    cat "${mnfst}" | jq -c \
        --arg tmpconfig_sum "${tmpconfig_sum}" \
        --arg tmpconfig_size "${tmpconfig_size}" \
        --arg tmptar_sum "${tmptar_sum}" \
        --arg tmptar_size "${tmptar_size}" \
        --arg artifact "$(basename ${artifact_path})" \
        --arg sum "${sum}" \
        '
        .config.digest = "sha256:$tmpconfig_sum"
        | .config.size = $tmpconfig_size
        | .layers = .layers + [
            {
                "mediaType": "application/vnd.oci.image.layer.v1.tar",
                "size": $tmptar_size,
                "digest": "sha256:$tmptar_sum",
                "annotations": {
                    "com.redhat.layer.type": "source",
                    "com.redhat.layer.content": "$artifact",
                    "com.redhat.layer.content.checksum": "sha256:$sum"
                }
            }
        ]
        ' > "${tmpmnfst}"
    _rm_rf "${mnfst}"

    # rename the manifest blob to its new checksum
    local tmpmnfst_sum="$(sha256sum ${tmpmnfst} | awk '{ print $1 }')"
    local tmpmnfst_size="$(_size ${tmpmnfst})"
    mv "${tmpmnfst}" "${out_dir}/blobs/sha256/${tmpmnfst_sum}"

    # map the mnfst_list to the new mnfst checksum
    local tmpmnfst_list="$(_mktemp)"
    cat "${mnfst_list}" | jq -c \
        --arg tag "${image_tag}" \
        --arg tmpmnfst_sum "${tmpmnfst_sum}" \
        --arg tmpmnfst_size "${tmpmnfst_size}" \
        '
        .manifests = [(.manifests[] | select(.annotations."org.opencontainers.image.ref.name" != "$tag") )]
            + [
                {
                    "mediaType": "application/vnd.oci.image.manifest.v1+json",
                    "digest": "sha256:$tmpmnfst_sum",
                    "size": $tmpmnfst_size,
                    "annotations": {
                        "com.redhat.image.type": "source"
                        "org.opencontainers.image.ref.name": "$tag"
                    }
                }
            ]
        ' > "${tmpmnfst_list}"
    mv "${tmpmnfst_list}" "${mnfst_list}"
}


#
# Source Collection Drivers
#
#   presently just bash functions. *notice* prefix the function name as `sourcedriver_`
#   May become a ${ABV_NAME}/drivers.d/
#
# Arguments:
#  * image ref
#  * path to inspect
#  * output path for source (specifc to this driver)
#  * output path for source json metadata (this addresses the files to be added and it's metadata)
#
# TODO TBD this does not account for how to pack/layer the sources collected here.
# This was my thought for outputing a `source.json` file, which is not a
# standard, but could be an array of metadata about _each_ object that should
# be packed.
#

#
# driver to determine and fetch source rpms, based on the rootfs
#
sourcedriver_rpm_fetch() {
    local ref="${1}"
    local rootfs="${2}"
    local out_dir="${3}"
    local manifest_dir="${4}"

    # Get the RELEASEVER from the image
    local release=$(rpm -q --queryformat "%{VERSION}\n" --root ${rootfs} -f /etc/os-release)

    # From the rootfs of the works image, build out the src rpms to operate over
    for srcrpm in $(rpm -qa --root ${rootfs} --queryformat '%{SOURCERPM}\n' | grep -v '^gpg-pubkey' | sort -u) ; do
        local rpm=${srcrpm%*.src.rpm}
        if [ ! -f "${out_dir}/${srcrpm}" ] ; then
            info "--> fetching ${srcrpm}"
            # XXX i wonder if all the srcrpms could be downloaded at once,
            # rather than serial. This would require building a new list of
            # files that are not present in ${out_dir}.
            dnf download \
                --quiet \
                --installroot "${rootfs}" \
                --release "${release}" \
                --destdir "${out_dir}" \
                --source \
                "${rpm}" || continue
        else
            info "--> using cached ${srcrpm}"
        fi

        # XXX one day, check and confirm with %{sourcepkgid}
        # https://bugzilla.redhat.com/show_bug.cgi?id=1741715
        #local rpm_sourcepkgid=$(rpm -q --root ${rootfs} --queryformat '%{sourcepkgid}' "${rpm}")
        local srcrpm_buildtime=$( rpm -qp --qf '%{buildtime}' ${out_dir}/${srcrpm} )
        local srcrpm_pkgid=$( rpm -qp --qf '%{pkgid}' ${out_dir}/${srcrpm} )
        touch --date=@${srcrpm_buildtime} ${out_dir}/${srcrpm}
        local mimetype="$(file --brief --mime-type ${out_dir}/${srcrpm})"

        local source_info="${manifest_dir}/${srcrpm}.json"
        jq \
            -n \
            --arg name ${srcrpm} \
            --arg buildtime "${srcrpm_buildtime}" \
            --arg mimetype "${mimetype}" \
            '
                    {
                        "name" : $name,
                        "annotations": {
                            "source.mediaType": $mimetype,
                            "source.mediaType": $mimetype,
                            "source.artifact.buildtime": $buildtime
                        }
                }
            ' \
            > "${source_info}"
    done
}

#
# If the caller specified a context directory,
#
# slightly special driver, as it has a flag/env passed in, that it uses
#
sourcedriver_context_dir() {
    local ref="${1}"
    local rootfs="${2}"
    local out_dir="${3}"
    local manifest_dir="${4}"

if [ -n "${CONTEXT_DIR}" ]; then
    context_dir=$(cd ${CONTEXT_DIR}; pwd)
    buildah add ${SRC_CTR} ${context_dir} /CONTEXT
    buildah config --created-by "/bin/sh -c #(nop) ADD file:$(cd ${context_dir}; _tar -cf - . | sha256sum -| cut -f1 -d' ') in /CONTEXT" ${SRC_CTR}
    export IMG=$(buildah commit --omit-timestamp --rm ${SRC_CTR})
    export SRC_CTR=$(buildah from ${IMG})
fi
}

#
# If the caller specified a extra directory
#
# slightly special driver, as it has a flag/env passed in, that it uses
#
sourcedriver_extra_src_dir() {
    local ref="${1}"
    local rootfs="${2}"
    local out_dir="${3}"
    local manifest_dir="${4}"

    if [ -n "${EXTRA_SRC_DIR}" ]; then
    fi
}


main() {
    _init ${@}

    local base_dir="$(pwd)/${ABV_NAME}"
    # using the bash builtin to parse
    while getopts ":hplDc:e:o:b:d:" opts; do
        case "${opts}" in
            b)
                base_dir="${OPTARG}"
                ;;
            c)
                local context_dir=${OPTARG}
                ;;
            e)
                local extra_src_dir=${OPTARG}
                ;;
            o)
                local output_dir=${OPTARG}
                ;;
            d)
                drivers=${OPTARG}
                ;;
            l)
                list_drivers=1
                ;;
            p)
                push=1
                ;;
            D)
                export DEBUG=1
                ;;
            h)
                _usage
                ;;
            *)
                _usage
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -n "${list_drivers}" ] ; then
        set | grep '^sourcedriver_.* () ' | tr -d ' ()'
        exit 0
    fi

    export CONTEXT_DIR="${CONTEXT_DIR:-$context_dir}"
    export EXTRA_SRC_DIR="${EXTRA_SRC_DIR:-$extra_src_dir}"

    local output_dir="${OUTPUT_DIR:-$output_dir}"
    local src_dir="${base_dir}/src"
    local work_dir="${base_dir}/work"

    export TMPDIR="${work_dir}/tmp"
    if [ -d "${TMPDIR}" ] ; then
        _rm_rf "${TMPDIR}"
    fi
    mkdir -p "${TMPDIR}"

    IMAGE_REF="${1}"
    debug "IMAGE_REF: ${IMAGE_REF}"

    IMAGE_REF_BASE="$(parse_img_base ${IMAGE_REF})"
    debug "IMAGE_REF_BASE: ${IMAGE_REF_BASE}"

    IMAGE_TAG="$(parse_img_tag ${IMAGE_REF})"
    debug "IMAGE_TAG: ${IMAGE_TAG}"

    IMAGE_DIGEST="$(parse_img_digest ${IMAGE_REF})"
    # determine missing digest before fetch, so that we fetch the precise image
    # including its digest.
    if [ -z "${IMAGE_DIGEST}" ] ; then
        IMAGE_DIGEST="$(fetch_img_digest ${IMAGE_REF_BASE}:${IMAGE_TAG})"
    fi
    debug "IMAGE_DIGEST: ${IMAGE_DIGEST}"

    # if inspect and fetch image, then to an OCI layout dir
    if [ ! -d "${work_dir}/layouts/${IMAGE_DIGEST/:/\/}" ] ; then
        # we'll store the image to a path based on its digest, that it can be reused
        img_layout="$(fetch_img ${IMAGE_REF_BASE}:${IMAGE_TAG}@${IMAGE_DIGEST} ${work_dir}/layouts/${IMAGE_DIGEST/:/\/} )"
    else
        img_layout="${work_dir}/layouts/${IMAGE_DIGEST/:/\/}:${IMAGE_TAG}"
    fi
    debug "image layout: ${img_layout}"

    # setup rootfs, from that OCI layout
    local unpack_dir="${work_dir}/unpacked/${IMAGE_DIGEST/:/\/}"
    if [ ! -d "${unpack_dir}" ] ; then
        unpack_img ${img_layout} ${unpack_dir}
    fi
    debug "unpacked dir: ${unpack_dir}"

    # clear prior driver's info about source to insert into Source Image
    _rm_rf "${work_dir}/driver/${IMAGE_DIGEST/:/\/}"

    if [ -n "${drivers}" ] ; then
        # clean up the args passed by the caller ...
        drivers="$(echo ${drivers} | tr ',' ' '| tr '\n' ' ')"
    else
        drivers="$(set | grep '^sourcedriver_.* () ' | tr -d ' ()' | tr '\n' ' ')"
    fi
    # iterate on the drivers
    #for driver in sourcedriver_rpm_fetch ; do
    for driver in ${drivers} ; do
        info "calling $driver"
        mkdir -vp "${src_dir}/${IMAGE_DIGEST/:/\/}/${driver#sourcedriver_*}"
        mkdir -vp "${work_dir}/driver/${IMAGE_DIGEST/:/\/}/${driver#sourcedriver_*}"
        $driver \
            "${IMAGE_REF_BASE}:${IMAGE_TAG}@${IMAGE_DIGEST}" \
            "${unpack_dir}/rootfs" \
            "${src_dir}/${IMAGE_DIGEST/:/\/}/${driver#sourcedriver_*}" \
            "${work_dir}/driver/${IMAGE_DIGEST/:/\/}/${driver#sourcedriver_*}"

        # TODO walk the driver output to determine layers to be added
        # find "${work_dir}/driver/${IMAGE_DIGEST/:/\/}/${driver#sourcedriver_*}" -type f -name '*.json'
    done

    # TODO maybe look to a directory like /usr/libexec/BuildSourceImage/drivers/ for drop-ins to run

    # TODO commit the image
    # This is going to be a hand craft of composing these layers using just bash and jq

echo "bailing here for now"
return 0

    ## if an output directory is provided then save a copy to it
    if [ -n "${output_dir}" ] ; then
        mkdir -p "${output_dir}"
        # XXX WIP
        push_img $src_img_dir "oci:$output_dir:$(ref_src_img_tag ${IMAGE_TAG})"
    fi

    if [ -n "${push}" ] ; then
        # XXX WIP
        push_img $src_dir $IMAGE_REF
    fi


#
# For each SRC_RPMS used to build the executable image, download the SRC RPM
# and generate a layer in the SRC RPM.
#
pushd ${SRC_RPM_DIR} > /dev/null
export SRC_CTR=$(buildah from scratch)
for i in ${SRC_RPMS}; do
    if [ ! -f $i ]; then
        RPM=$(echo $i | sed 's/.src.rpm$//g')
        dnf download --release $RELEASE --source $RPM || continue # TODO: perhaps log failures somewhere
    fi
    echo "Adding ${srpm}"
    touch --date=@`rpm -q --qf '%{buildtime}' ${srpm}` ${srpm}
    buildah add ${SRC_CTR} ${srpm} /RPMS/
    buildah config --created-by "/bin/sh -c #(nop) ADD file:$(sha256sum ${srpm} | cut -f1 -d' ') in /RPMS" ${SRC_CTR}
    export IMG=$(buildah commit --omit-timestamp --disable-compression --rm ${SRC_CTR})
    export SRC_CTR=$(buildah from ${IMG})
done
popd > /dev/null


}

# only exec main if this is being called (this way we can source and test the functions)
_is_sourced || main ${@}

# vim:set shiftwidth=4 softtabstop=4 expandtab:
