#!/bin/bash

# This script builds a Source Image via "drivers" to collect source

export ABV_NAME="SrcImg"
# TODO maybe a flag for this?
export source_image_suffix="-source"

# output version string
_version() {
    echo "$(basename "${0}") version 0.2.0-dev"
}

# output the cli usage and exit
_usage() {
    _version
    echo "Usage: $(basename "$0") [-D] [-b <path>] [-c <path>] [-e <path>] [-r <path>] [-o <path>] [-i <image>] [-p <image>] [-l] [-d <drivers>]"
    echo ""
    echo "          Container Source Image tool"
    echo ""
    echo -e "       -b <path>\tbase path for source image builds"
    echo -e "       -c <path>\tbuild context for the container image. Can be provided via CONTEXT_DIR env variable"
    echo -e "       -e <path>\textra src for the container image. Can be provided via EXTRA_SRC_DIR env variable"
    echo -e "       -s <path>\tdirectory of SRPMS to add. Can be provided via SRPM_DIR env variable"
    echo -e "       -o <path>\toutput the OCI image to path. Can be provided via OUTPUT_DIR env variable"
    echo -e "       -d <drivers>\tenumerate specific source drivers to run"
    echo -e "       -l\t\tlist the source drivers available"
    echo -e "       -i <image>\timage reference to fetch and inspect its rootfs to derive sources"
    echo -e "       -p <image>\tpush source image to specified reference after build"
    echo -e "       -D\t\tdebuging output. Can be set via DEBUG env variable"
    echo -e "       -h\t\tthis usage information"
    echo -e "       -v\t\tversion"
    echo -e ""
    echo -e "    Subcommands:"
    echo -e "       unpack\tUnpack an OCI layout to a rootfs directory"
    echo -e ""
}

# sanity checks on startup
_init() {
    set -o pipefail

    # check for tools we depend on
    for cmd in jq skopeo dnf file find tar stat date ; do
        if [ -z "$(command -v ${cmd})" ] ; then
            # TODO: maybe this could be individual checks so it can report
            # where to find the tools
            _error "please install package to provide '${cmd}'"
        fi
    done
}

# enable access to some of functions as subcommands!
_subcommand() {
    local command="${1}"
    local ret

    shift

    case "${command}" in
        unpack)
            # (vb) i'd prefer this subcommand directly match the function name, but it isn't as pretty.
            unpack_img "${@}"
            ret=$?
            exit "${ret}"
            ;;
    esac
}

# _is_sourced tests whether this script is being source, or executed directly
_is_sourced() {
    # https://unix.stackexchange.com/a/215279
    # thanks @tianon
    [ "${FUNCNAME[${#FUNCNAME[@]} - 1]}" == 'source' ]
}

# count $character $string
_count_char_in_string() {
    c="${2//[^${1}]}"
    echo -n ${#c}
}

# size of file/directory in bytes
_size() {
    du -b "${1}" | awk '{ ORS=""; print $1 }' 
}

# date timestamp in RFC 3339, to the nanosecond, but slightly golang style ...
_date_ns() {
    date --rfc-3339=ns | tr ' ' 'T' | tr -d '\n'
}

# local `mktemp -d`
_mktemp_d() {
    local v
    v=$(mktemp -d "${TMPDIR:-/tmp}/${ABV_NAME}.XXXXXX")
    _debug "mktemp -d --> ${v}"
    echo "${v}"
}

# local `mktemp`
_mktemp() {
    local v
    v=$(mktemp "${TMPDIR:-/tmp}/${ABV_NAME}.XXXXXX")
    _debug "mktemp --> ${v}"
    echo "${v}"
}

# local rm -rf
_rm_rf() {
    _debug "rm -rf ${*}"
    rm -rf "${@}"
}

# local mkdir -p
_mkdir_p() {
    if [ -n "${DEBUG}" ] ; then
        mkdir -vp "${@}"
    else
        mkdir -p "${@}"
    fi
}

# local tar
_tar() {
    if [ -n "${DEBUG}" ] ; then
        tar -v "${@}"
    else
        tar "${@}"
    fi
}

_rpm_download() {
    if [ "$(command -v yumdownloader)" != "" ] ; then
        yumdownloader "${@}"
    else
        dnf download "${@}"
    fi
}

# output things, only when $DEBUG is set
_debug() {
    if [ -n "${DEBUG}" ] ; then
        echo "[${ABV_NAME}][DEBUG] ${*}" >&2
    fi
}

# general echo but with prefix
_info() {
    echo "[${ABV_NAME}][INFO] ${*}"
}

_warn() {
    echo "[${ABV_NAME}][WARN] ${*}" >&2
}

# general echo but with prefix
_error() {
    echo "[${ABV_NAME}][ERROR] ${*}" >&2
    exit 1
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
    if [ "$(_count_char_in_string '@' "${ref}")" -gt 0 ] ; then
        digest="${ref##*@}" # the digest after the "@"
    fi
    echo -n "${digest}"
}

#
# determine image base name (without tag or digest)
#
parse_img_base() {
    local ref="${1%@*}" # just the portion before the digest "@"
    local base="${ref}" # default base is their reference
    local last_word="" # splitting up their reference to get the last word/chunk
    last_word="$(echo "${ref}" | tr '/' '\n' | tail -1 )"
    if [ "$(_count_char_in_string ':' "${last_word}")" -gt 0 ] ; then
        # which means everything before it is the base image name, **including
        # transport (which could have a port delineation), and even a URI like network ports.
        base="$(echo "${ref}" | rev | cut -d : -f 2 | rev )"
    fi
    echo -n "${base}"
}

#
# determine, or guess, the image tag from the provided image reference
#
parse_img_tag() {
    local ref="${1%@*}" # just the portion before the digest "@"
    local tag="latest" # default tag

    if [ -z "${ref}" ] ; then
        echo -n "${tag}"
        return 0
    fi

    local last_word="" # splitting up their reference to get the last word/chunk
    last_word="$(echo "${ref}" | tr '/' '\n' | tail -1 )"
    if [ "$(_count_char_in_string ':' "${last_word}")" -gt 0 ] ; then
        # if there are colons in the last segment after '/', then get that tag name
        tag="${last_word#*:}" # this parameter expansion removes the prefix pattern before the ':'
    fi
    echo -n "${tag}"
}

#
# an inline prefixer for containers/image tools
#
ref_prefix() {
    local ref="${1}"
    local pfxs
    local ret

    # get the supported prefixes of the current version of skopeo
    mapfile -t pfxs < <(skopeo copy --help | grep -A1 "Supported transports:" | grep -v "Supported transports" | sed 's/, /\n/g')
    ret=$?
    if [ ${ret} -ne 0 ] ; then
        return ${ret}
    fi

    for pfx in "${pfxs[@]}" ; do
        if echo "${ref}" | grep -q "^${pfx}:" ; then
            # break if we match a known prefix
            echo "${ref}"
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
    echo -n "$(parse_img_tag "${ref}")""${source_image_suffix}"
}

#
# call out to registry for the image reference's digest checksum
#
fetch_img_digest() {
    local ref="${1}"
    local dgst
    local ret

    ## TODO: check for authfile, creds, and whether it's an insecure registry
    dgst=$(skopeo inspect "$(ref_prefix "${ref}")" | jq .Digest | tr -d \")
    ret=$?
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
    local base
    local tag
    local dgst
    local from
    local ret

    _mkdir_p "${dst}"

    base="$(parse_img_base "${ref}")"
    tag="$(parse_img_tag "${ref}")"
    dgst="$(parse_img_digest "${ref}")"
    from=""
    # skopeo currently only support _either_ tag _or_ digest, so we'll be specific.
    if [ -n "${dgst}" ] ; then
        from="$(ref_prefix "${base}")@${dgst}"
    else
        from="$(ref_prefix "${base}"):${tag}"
    fi

    ## TODO: check for authfile, creds, and whether it's an insecure registry
    ## destination name must have the image tag included (umoci expects it)
    skopeo \
        copy \
        "${from}" \
        "oci:${dst}:${tag}" >&2
    ret=$?
    if [ ${ret} -ne 0 ] ; then
        return ${ret}
    fi
    echo -n "${dst}:${tag}"
}

#
# upack_img <oci layout path> <unpack path>
#
unpack_img() {
    local image_dir="${1}"
    local unpack_dir="${2}"
    local ret

    while getopts ":h" opts; do
        case "${opts}" in
            *)
                echo "$0 unpack <oci layout path> <unpack path>"
                return 1
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${image_dir}" ] || [ -z "${unpack_dir}" ] ; then
        _error "[unpack_img] blank arguments provided"
    fi

    if [ -d "${unpack_dir}" ] ; then
        _rm_rf "${unpack_dir}"
    fi

    if [ -n "$(command -v umoci)" ] ; then
        # can be done as non-root (even in a non-root container)
        unpack_img_umoci "${image_dir}" "${unpack_dir}"
        ret=$?
        if [ ${ret} -ne 0 ] ; then
            return ${ret}
        fi
    else
        # can be done as non-root (even in a non-root container)
        unpack_img_bash "${image_dir}" "${unpack_dir}"
        ret=$?
        if [ ${ret} -ne 0 ] ; then
            return ${ret}
        fi
    fi
}

#
# unpack an image layout using only jq and bash
#
unpack_img_bash() {
    local image_dir="${1}"
    local unpack_dir="${2}"
    local mnfst_dgst
    local layer_dgsts
    local ret

    _debug "unpacking with bash+jq"

    # for compat with umoci (which wants the image tag as well)
    if echo "${image_dir}" | grep -q ":" ; then
        image_dir="${image_dir%:*}"
    fi

    mnfst_dgst="$(jq '.manifests[0].digest' "${image_dir}"/index.json | tr -d \")"
    ret=$?
    if [ ${ret} -ne 0 ] ; then
        return ${ret}
    fi

    # TODO this will need to be refactored when we start seeing +zstd layers.
    # Then it will be better to no just get a list of digests, but maybe to
    # iterate on each descriptor independently?
    layer_dgsts="$(jq '.layers | map(select(.mediaType == "application/vnd.oci.image.layer.v1.tar+gzip"),select(.mediaType == "application/vnd.oci.image.layer.v1.tar"),select(.mediaType == "application/vnd.docker.image.rootfs.diff.tar.gzip")) | .[] | .digest' "${image_dir}"/blobs/"${mnfst_dgst/://}" | tr -d \")"
    ret=$?
    if [ ${ret} -ne 0 ] ; then
        return ${ret}
    fi

    _mkdir_p "${unpack_dir}/rootfs"
    for dgst in ${layer_dgsts} ; do
        path="${image_dir}/blobs/${dgst/://}"
        tmp_file=$(_mktemp)
        zcat "${path}" | _tar -t > "$tmp_file"

        # look for '.wh.' entries. They must be removed from the rootfs
        # _before_ extracting the archive, then the .wh. entries themselves
        # need to not remain afterwards
        grep '\.wh\.' "${tmp_file}" | while read -r wh_path ; do
            # if `some/path/.wh.foo` then `rm -rf `${unpack_dir}/some/path/foo`
            # if `some/path/.wh..wh..opq` then `rm -rf `${unpack_dir}/some/path/*`
            if [ "$(basename "${wh_path}")" == ".wh..wh..opq" ] ; then
                _rm_rf "${unpack_dir}/rootfs/$(dirname "${wh_path}")/*"
            elif basename "${wh_path}" | grep -qe '^\.wh\.' ; then
                name=$(basename "${wh_path}" | sed -e 's/^\.wh\.//')
                _rm_rf "${unpack_dir}/rootfs/$(dirname "${wh_path}")/${name}"
            fi
        done

        _info "[unpacking] layer ${dgst}"
        # unpack layer to rootfs (without whiteouts)
        zcat "${path}" | _tar --restrict --no-xattr --no-acls --no-selinux --exclude='*.wh.*' -x -C "${unpack_dir}/rootfs"
        ret=$?
        if [ ${ret} -ne 0 ] ; then
            return ${ret}
        fi

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

    _debug "unpacking with umoci"
    # always assume we're not root I reckon
    umoci unpack --rootless --image "${image_dir}" "${unpack_dir}" >&2
    ret=$?
    return $ret
}

#
# copy an image from one location to another
#
push_img() {
    local src="${1}"
    local dst="${2}"

    _debug "pushing image ${src} to ${dst}"
    ## TODO: check for authfile, creds, and whether it's an insecure registry
    skopeo copy --quiet --dest-tls-verify=false "$(ref_prefix "${src}")" "$(ref_prefix "${dst}")" # XXX for demo only
    #skopeo copy "$(ref_prefix "${src}")" "$(ref_prefix "${dst}")"
    ret=$?
    return $ret
}

#
# sets up a basic new OCI layout, for an image with the provided (or default 'latest') tag
#
layout_new() {
    local out_dir="${1}"
    local image_tag="${2:-latest}"
    local ret

    if [ -n "$(command -v umoci)" ] ; then
        layout_new_umoci "${out_dir}" "${image_tag}"
        ret=$?
        if [ ${ret} -ne 0 ] ; then
            return ${ret}
        fi
    else
        layout_new_bash "${out_dir}" "${image_tag}"
        ret=$?
        if [ ${ret} -ne 0 ] ; then
            return ${ret}
        fi
    fi
}

#
# sets up new OCI layout, using `umoci`
#
layout_new_umoci() {
    local out_dir="${1}"
    local image_tag="${2:-latest}"
    local ret

    # umoci expects the layout path to _not_ exist and will fail if it does exist
    _rm_rf "${out_dir}"

    umoci init --layout "${out_dir}"
    ret=$?
    if [ "${ret}" -ne 0 ] ; then
        return "${ret}"
    fi

    # XXX currently does not support adding the rich annotations like I've done with the _bash
    # https://github.com/openSUSE/umoci/issues/298
    umoci new --image "${out_dir}:${image_tag}"
    ret=$?
    if [ "${ret}" -ne 0 ] ; then
        return "${ret}"
    fi
}

#
# sets up new OCI layout, all with bash and jq
#
layout_new_bash() {
    local out_dir="${1}"
    local image_tag="${2:-latest}"
    local config
    local mnfst
    local config_sum
    local mnfst_sum
    local ret

    _mkdir_p "${out_dir}/blobs/sha256"
    echo '{"imageLayoutVersion":"1.0.0"}' > "${out_dir}/oci-layout"
    config='
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
    config_sum=$(echo "${config}" | jq -c | tr -d '\n' | sha256sum | awk '{ ORS=""; print $1 }')
    ret=$?
    if [ "${ret}" -ne 0 ] ; then
        return "${ret}"
    fi
    echo "${config}" | jq -c | tr -d '\n' > "${out_dir}/blobs/sha256/${config_sum}"
    ret=$?
    if [ "${ret}" -ne 0 ] ; then
        return "${ret}"
    fi

    mnfst='
{
  "schemaVersion": 2,
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "sha256:'"${config_sum}"'",
    "size": '"$(_size "${out_dir}"/blobs/sha256/"${config_sum}")"'
  },
  "layers": []
}
    '
    mnfst_sum=$(echo "${mnfst}" | jq -c | tr -d '\n' | sha256sum | awk '{ ORS=""; print $1 }')
    echo "${mnfst}" | jq -c | tr -d '\n' > "${out_dir}/blobs/sha256/${mnfst_sum}"

    echo '
{
  "schemaVersion": 2,
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:'"${mnfst_sum}"'",
      "size": '"$(_size "${out_dir}"/blobs/sha256/"${mnfst_sum}")"',
      "annotations": {
        "org.opencontainers.image.ref.name": "'"${image_tag}"'"
      }
    }
  ]
}
    ' | jq -c | tr -d '\n' > "${out_dir}/index.json"
}

# call this for every artifact, to insert it into an OCI layout
# args:
#   * a path to the layout
#   * a path to the artifact
#   * the path inside the tar
#   * json file to slurp in as annotations for this layer's OCI descriptor
#   * tag used in the layout (default is 'latest')
#
layout_insert() {
    local out_dir="${1}"
    local artifact_path="${2}"
    local tar_path="${3}"
    local annotations_file="${4}"
    local image_tag="${5:-latest}"
    local ret

    if [ -n "$(command -v umoci)" ] ; then
        layout_insert_umoci "${out_dir}" "${artifact_path}" "${tar_path}" "${annotations_file}" "${image_tag}"
        ret=$?
        if [ ${ret} -ne 0 ] ; then
            return ${ret}
        fi
    else
        layout_insert_bash "${out_dir}" "${artifact_path}" "${tar_path}" "${annotations_file}" "${image_tag}"
        ret=$?
        if [ ${ret} -ne 0 ] ; then
            return ${ret}
        fi
    fi
}

layout_insert_umoci() {
    local out_dir="${1}"
    local artifact_path="${2}"
    local tar_path="${3}"
    local annotations_file="${4}"
    local image_tag="${5:-latest}"
    local sum
    local ret

    # prep the blob path for inside the layer, so we can just copy that whole path in
    tmpdir="$(_mktemp_d)"

    # TODO account for "artifact_path" being a directory?
    sum="$(sha256sum "${artifact_path}" | awk '{ print $1 }')"

    _mkdir_p "${tmpdir}/blobs/sha256"
    cp "${artifact_path}" "${tmpdir}/blobs/sha256/${sum}"
    if [ "$(basename "${tar_path}")" == "$(basename "${artifact_path}")" ] ; then
        _mkdir_p "${tmpdir}/$(dirname "${tar_path}")"
        # TODO this symlink need to be relative path, not to `/blobs/...`
        ln -s "/blobs/sha256/${sum}" "${tmpdir}/${tar_path}"
    else
        _mkdir_p "${tmpdir}/${tar_path}"
        # TODO this symlink need to be relative path, not to `/blobs/...`
        ln -s "/blobs/sha256/${sum}" "${tmpdir}/${tar_path}/$(basename "${artifact_path}")"
    fi

    # XXX currently does not support adding the rich annotations like I've done with the _bash
    # https://github.com/openSUSE/umoci/issues/298
    # XXX this insert operation can not disable compression
    # https://github.com/openSUSE/umoci/issues/300
    umoci insert \
        --rootless \
        --image "${out_dir}:${image_tag}" \
        --history.created "$(_date_ns)" \
        --history.comment "#(nop) $(_version) adding artifact: ${sum}" \
        "${tmpdir}" "/"
    ret=$?
    if [ ${ret} -ne 0 ] ; then
        return ${ret}
    fi
}

layout_insert_bash() {
    local out_dir="${1}"
    local artifact_path="${2}"
    local tar_path="${3}"
    local annotations_file="${4}"
    local image_tag="${5:-latest}"
    local mnfst_list
    local mnfst_dgst
    local mnfst
    local tmpdir
    local sum
    local tmptar
    local tmptar_sum
    local tmptar_size
    local config_sum
    local tmpconfig
    local tmpconfig_sum
    local tmpconfig_size
    local tmpmnfst
    local tmpmnfst_sum
    local tmpmnfst_size
    local tmpmnfst_list

    mnfst_list="${out_dir}/index.json"
    # get the digest to the manifest
    test -f "${mnfst_list}" || return 1
    mnfst_dgst="$(jq --arg tag "${image_tag}" '
        .manifests[]
        |  select(.annotations."org.opencontainers.image.ref.name" == $tag )
        | .digest
    ' "${mnfst_list}" | tr -d \" | tr -d '\n' )"
    mnfst="${out_dir}/blobs/${mnfst_dgst/://}"
    test -f "${mnfst}" || return 1

    # make tar of new object
    tmpdir="$(_mktemp_d)"
    # TODO account for "artifact_path" being a directory?
    sum="$(sha256sum "${artifact_path}" | awk '{ print $1 }')"
    # making a blob store in the layer
    _mkdir_p "${tmpdir}/blobs/sha256"
    cp "${artifact_path}" "${tmpdir}/blobs/sha256/${sum}"
    if [ "$(basename "${tar_path}")" == "$(basename "${artifact_path}")" ] ; then
        _mkdir_p "${tmpdir}/$(dirname "${tar_path}")"
        # TODO this symlink need to be relative path, not to `/blobs/...`
        ln -s "../blobs/sha256/${sum}" "${tmpdir}/${tar_path}"
    else
        _mkdir_p "${tmpdir}/${tar_path}"
        # TODO this symlink need to be relative path, not to `/blobs/...`
        ln -s "../blobs/sha256/${sum}" "${tmpdir}/${tar_path}/$(basename "${artifact_path}")"
    fi
    tmptar="$(_mktemp)"

    # zero all the things for as consistent blobs as possible
    _tar -C "${tmpdir}" --mtime=@0 --owner=0 --group=0 --mode='a+rw' --no-xattrs --no-selinux --no-acls -cf "${tmptar}" .
    _rm_rf "${tmpdir}"

    # checksum tar and move to blobs/sha256/$checksum
    tmptar_sum="$(sha256sum "${tmptar}" | awk '{ ORS=""; print $1 }')"
    tmptar_size="$(_size "${tmptar}")"
    mv "${tmptar}" "${out_dir}/blobs/sha256/${tmptar_sum}"

    # find and read the prior config, mapped from the manifest
    config_sum="$(jq '.config.digest' "${mnfst}" | tr -d \")"

    # use `jq` to append to prior config
    tmpconfig="$(_mktemp)"
    jq -c \
        --arg date "$(_date_ns)" \
        --arg tmptar_sum "sha256:${tmptar_sum}" \
        --arg comment "#(nop) $(_version) adding artifact: ${sum}" \
        '
        .created = $date
        | .rootfs.diff_ids += [ $tmptar_sum ]
        | .history += [
            {
                "created": $date,
                "created_by": $comment
            }
        ]
        ' "${out_dir}/blobs/${config_sum/://}" > "${tmpconfig}"
    _rm_rf "${out_dir}/blobs/${config_sum/://}"

    # rename the config blob to its new checksum
    tmpconfig_sum="$(sha256sum "${tmpconfig}" | awk '{ ORS=""; print $1 }')"
    tmpconfig_size="$(_size "${tmpconfig}")"
    mv "${tmpconfig}" "${out_dir}/blobs/sha256/${tmpconfig_sum}"

    # append layers list in the manifest, and its new config mapping
    tmpmnfst="$(_mktemp)"
    jq -c \
        --arg tmpconfig_sum "sha256:${tmpconfig_sum}" \
        --arg tmpconfig_size "${tmpconfig_size}" \
        --arg tmptar_sum "sha256:${tmptar_sum}" \
        --arg tmptar_size "${tmptar_size}" \
        --arg artifact "$(basename "${artifact_path}")" \
        --arg sum "sha256:${sum}" \
        --slurpfile annotations_slup "${annotations_file}" \
        '
        .config.digest = $tmpconfig_sum
        | .config.size = ($tmpconfig_size|tonumber)
        | {
            "com.redhat.layer.type": "source",
            "com.redhat.layer.content": $artifact,
            "com.redhat.layer.content.checksum": $sum
            } + $annotations_slup[0] as $annotations_merge
        | .layers += [
            {
                "mediaType": "application/vnd.oci.image.layer.v1.tar",
                "size": ($tmptar_size|tonumber),
                "digest": $tmptar_sum,
                "annotations": $annotations_merge
            }
        ]
        ' "${mnfst}" > "${tmpmnfst}"
    ret=$?
    if [ $ret -ne 0 ] ; then
        return 1
    fi
    _rm_rf "${mnfst}"

    # rename the manifest blob to its new checksum
    tmpmnfst_sum="$(sha256sum "${tmpmnfst}" | awk '{ ORS=""; print $1 }')"
    tmpmnfst_size="$(_size "${tmpmnfst}")"
    mv "${tmpmnfst}" "${out_dir}/blobs/sha256/${tmpmnfst_sum}"

    # map the mnfst_list to the new mnfst checksum
    tmpmnfst_list="$(_mktemp)"
    jq -c \
        --arg tag "${image_tag}" \
        --arg tmpmnfst_sum "sha256:${tmpmnfst_sum}" \
        --arg tmpmnfst_size "${tmpmnfst_size}" \
        '
            [(.manifests[] | select(.annotations."org.opencontainers.image.ref.name" != $tag) )] as $manifests_reduced
            | [
                {
                    "mediaType": "application/vnd.oci.image.manifest.v1+json",
                    "digest": $tmpmnfst_sum,
                    "size": ($tmpmnfst_size|tonumber),
                    "annotations": {
                        "com.redhat.image.type": "source",
                        "org.opencontainers.image.ref.name": $tag
                    }
                }
              ] as $manifests_new
            | .manifests = $manifests_reduced + $manifests_new
        ' "${mnfst_list}" > "${tmpmnfst_list}"
    ret=$?
    if [ $ret -ne 0 ] ; then
        return 1
    fi
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
#  * output path for JSON file of source's annotations
#
# The JSON of source annotations is the key to discovering the source artifact
# to be added and including rich metadata about that archive into the final
# image.
# The name of each JSON file is appending '.json' to the artifact's name. So if
# you have `foo-1.0.src.rpm` then there MUST be a corresponding
# `foo-1.0.src.rpm.json`.
# The data structure in this annotation is just a dict/hashmap, with key/val
# according to
# https://github.com/opencontainers/image-spec/blob/master/annotations.md
#

#
# driver to determine and fetch source rpms, based on the rootfs
#
sourcedriver_rpm_fetch() {
    local self="${0#sourcedriver_*}"
    local ref="${1}"
    local rootfs="${2}"
    local out_dir="${3}"
    local manifest_dir="${4}"
    local release
    local rpm
    local srcrpm_buildtime
    local srcrpm_pkgid
    local srcrpm_name
    local srcrpm_version
    local srcrpm_epoch
    local srcrpm_release
    local mimetype

    # Get the RELEASEVER from the image
    release=$(rpm -q --queryformat "%{VERSION}\n" --root "${rootfs}" -f /etc/os-release)

    # From the rootfs of the works image, build out the src rpms to operate over
    for srcrpm in $(rpm -qa --root "${rootfs}" --queryformat '%{SOURCERPM}\n' | grep -v '^gpg-pubkey' | sort -u) ; do
        if [ "${srcrpm}" == "(none)" ] ; then
            continue
        fi

        rpm=${srcrpm%*.src.rpm}
        if [ ! -f "${out_dir}/${srcrpm}" ] ; then
            _debug "--> fetching ${srcrpm}"
            _rpm_download \
                --quiet \
                --installroot "${rootfs}" \
                --release "${release}" \
                --destdir "${out_dir}" \
                --source \
                "${rpm}"
            ret=$?
            if [ $ret -ne 0 ] ; then
                _warn "failed to fetch ${srcrpm}"
                continue
            fi
        else
            _debug "--> using cached ${srcrpm}"
        fi

        # TODO one day, check and confirm with %{sourcepkgid}
        # https://bugzilla.redhat.com/show_bug.cgi?id=1741715
        #rpm_sourcepkgid=$(rpm -q --root ${rootfs} --queryformat '%{sourcepkgid}' "${rpm}")
        srcrpm_buildtime=$(rpm -qp --nosignature --qf '%{buildtime}' "${out_dir}"/"${srcrpm}" )
        srcrpm_pkgid=$(rpm -qp --nosignature --qf '%{pkgid}' "${out_dir}"/"${srcrpm}" )
        srcrpm_name=$(rpm -qp --nosignature --qf '%{name}' "${out_dir}"/"${srcrpm}" )
        srcrpm_version=$(rpm -qp --nosignature --qf '%{version}' "${out_dir}"/"${srcrpm}" )
        srcrpm_epoch=$(rpm -qp --nosignature --qf '%{epoch}' "${out_dir}"/"${srcrpm}" )
        srcrpm_release=$(rpm -qp --nosignature --qf '%{release}' "${out_dir}"/"${srcrpm}" )
        mimetype="$(file --brief --mime-type "${out_dir}"/"${srcrpm}")"
        jq \
            -n \
            --arg filename "${srcrpm}" \
            --arg name "${srcrpm_name}" \
            --arg version "${srcrpm_version}" \
            --arg epoch "${srcrpm_epoch}" \
            --arg release "${srcrpm_release}" \
            --arg buildtime "${srcrpm_buildtime}" \
            --arg mimetype "${mimetype}" \
            '
                {
                    "source.artifact.filename": $filename,
                    "source.artifact.name": $name,
                    "source.artifact.version": $version,
                    "source.artifact.epoch": $epoch,
                    "source.artifact.release": $release,
                    "source.artifact.mimetype": $mimetype,
                    "source.artifact.buildtime": $buildtime
                }
            ' \
            > "${manifest_dir}/${srcrpm}.json"
        ret=$?
        if [ $ret -ne 0 ] ; then
            return 1
        fi
    done
}

#
# driver to only package rpms from a provided rpm directory
# (koji use-case)
#
sourcedriver_rpm_dir() {
    local self="${0#sourcedriver_*}"
    local ref="${1}"
    local rootfs="${2}"
    local out_dir="${3}"
    local manifest_dir="${4}"
    local srcrpm_buildtime
    local srcrpm_pkgid
    local srcrpm_name
    local srcrpm_version
    local srcrpm_epoch
    local srcrpm_release
    local mimetype

    if [ -n "${SRPM_DIR}" ]; then
        _debug "[$self] writing to $out_dir and $manifest_dir"
        find "${SRPM_DIR}" -type f -name '*src.rpm' | while read -r srcrpm ; do
            cp "${srcrpm}" "${out_dir}"
            srcrpm="$(basename "${srcrpm}")"
            _debug "[$self] --> ${srcrpm}"
            srcrpm_buildtime=$(rpm -qp --nosignature --qf '%{buildtime}' "${out_dir}"/"${srcrpm}" )
            srcrpm_pkgid=$(rpm -qp --nosignature --qf '%{pkgid}' "${out_dir}"/"${srcrpm}" )
            srcrpm_name=$(rpm -qp --nosignature --qf '%{name}' "${out_dir}"/"${srcrpm}" )
            srcrpm_version=$(rpm -qp --nosignature --qf '%{version}' "${out_dir}"/"${srcrpm}" )
            srcrpm_epoch=$(rpm -qp --nosignature --qf '%{epoch}' "${out_dir}"/"${srcrpm}" )
            srcrpm_release=$(rpm -qp --nosignature --qf '%{release}' "${out_dir}"/"${srcrpm}" )
            mimetype="$(file --brief --mime-type "${out_dir}"/"${srcrpm}")"
            jq \
                -n \
                --arg filename "${srcrpm}" \
                --arg name "${srcrpm_name}" \
                --arg version "${srcrpm_version}" \
                --arg epoch "${srcrpm_epoch}" \
                --arg release "${srcrpm_release}" \
                --arg buildtime "${srcrpm_buildtime}" \
                --arg mimetype "${mimetype}" \
                --arg pkgid "${srcrpm_pkgid}" \
                '
                    {
                        "source.artifact.filename": $filename,
                        "source.artifact.name": $name,
                        "source.artifact.version": $version,
                        "source.artifact.epoch": $version,
                        "source.artifact.release": $release,
                        "source.artifact.mimetype": $mimetype,
                        "source.artifact.pkgid": $pkgid,
                        "source.artifact.buildtime": $buildtime
                    }
                ' \
                > "${manifest_dir}/${srcrpm}.json"
            ret=$?
            if [ $ret -ne 0 ] ; then
                return 1
            fi
        done
    fi
}

#
# If the caller specified a context directory,
#
# slightly special driver, as it has a flag/env passed in, that it uses
#
sourcedriver_context_dir() {
    local self="${0#sourcedriver_*}"
    local ref="${1}"
    local rootfs="${2}"
    local out_dir="${3}"
    local manifest_dir="${4}"
    local tarname
    local mimetype
    local source_info

    if [ -n "${CONTEXT_DIR}" ]; then
        _debug "$self: writing to $out_dir and $manifest_dir"
        tarname="context.tar"
        _tar -C "${CONTEXT_DIR}" \
            --mtime=@0 --owner=0 --group=0 --mode='a+rw' --no-xattrs --no-selinux --no-acls \
            -cf "${out_dir}/${tarname}" .
        mimetype="$(file --brief --mime-type "${out_dir}"/"${tarname}")"
        source_info="${manifest_dir}/${tarname}.json"
        jq \
            -n \
            --arg name "${tarname}" \
            --arg mimetype "${mimetype}" \
            '
                {
                    "source.artifact.name": $name,
                    "source.artifact.mimetype": $mimetype
                }
            ' \
            > "${source_info}"
        ret=$?
        if [ $ret -ne 0 ] ; then
            return 1
        fi
    fi
}

#
# If the caller specified a extra directory
#
# slightly special driver, as it has a flag/env passed in, that it uses
#
sourcedriver_extra_src_dir() {
    local self="${0#sourcedriver_*}"
    local ref="${1}"
    local rootfs="${2}"
    local out_dir="${3}"
    local manifest_dir="${4}"
    local tarname
    local mimetype
    local source_info

    if [ -n "${EXTRA_SRC_DIR}" ]; then
        _debug "$self: writing to $out_dir and $manifest_dir"
        tarname="extra-src.tar"
        _tar -C "${EXTRA_SRC_DIR}" \
            --mtime=@0 --owner=0 --group=0 --mode='a+rw' --no-xattrs --no-selinux --no-acls \
            -cf "${out_dir}/${tarname}" .
        mimetype="$(file --brief --mime-type "${out_dir}"/"${tarname}")"
        source_info="${manifest_dir}/${tarname}.json"
        jq \
            -n \
            --arg name "${tarname}" \
            --arg mimetype "${mimetype}" \
            '
                {
                    "source.artifact.name": $name,
                    "source.artifact.mimetype": $mimetype
                }
            ' \
            > "${source_info}"
        ret=$?
        if [ $ret -ne 0 ] ; then
            return 1
        fi
    fi
}


main() {
    local base_dir
    local input_context_dir
    local input_extra_src_dir
    local input_inspect_image_ref
    local input_srpm_dir
    local drivers
    local image_ref
    local img_layout
    local list_drivers
    local output_dir
    local push_image_ref
    local ret
    local rootfs
    local src_dir
    local src_img_dir
    local src_img_tag
    local src_name
    local unpack_dir
    local work_dir

    _init "${@}"
    _subcommand "${@}"

    base_dir="${BASE_DIR:-$(pwd)/${ABV_NAME}}"
    # using the bash builtin to parse
    while getopts ":hlvDi:c:s:e:o:b:d:p:" opts; do
        case "${opts}" in
            b)
                base_dir="${OPTARG}"
                ;;
            c)
                input_context_dir=${OPTARG}
                ;;
            e)
                input_extra_src_dir=${OPTARG}
                ;;
            d)
                drivers=${OPTARG}
                ;;
            h)
                _usage
                exit 0
                ;;
            i)
                input_inspect_image_ref=${OPTARG}
                ;;
            l)
                list_drivers=1
                ;;
            o)
                output_dir=${OPTARG}
                ;;
            p)
                push_image_ref=${OPTARG}
                ;;
            s)
                input_srpm_dir=${OPTARG}
                ;;
            v)
                _version
                exit 0
                ;;
            D)
                export DEBUG=1
                ;;
            *)
                _usage
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -n "${list_drivers}" ] ; then
        set | grep '^sourcedriver_.* () ' | tr -d ' ()'
        exit 0
    fi

    # "local" variables are not set in `env`, but are seen in `set`
    if [ "$(set | grep -c '^input_')" -eq 0 ] ; then
        _error "provide an input (example: $(basename "${0}") -i docker.io/centos -e ./my-sources/ )"
    fi

    # These three variables are slightly special, in that they're globals that
    # specific drivers will expect.
    export CONTEXT_DIR="${CONTEXT_DIR:-$input_context_dir}"
    export EXTRA_SRC_DIR="${EXTRA_SRC_DIR:-$input_extra_src_dir}"
    export SRPM_DIR="${SRPM_DIR:-$input_srpm_dir}"

    output_dir="${OUTPUT_DIR:-$output_dir}"

    export TMPDIR="${base_dir}/tmp"
    if [ -d "${TMPDIR}" ] ; then
        _rm_rf "${TMPDIR}"
    fi
    _mkdir_p "${TMPDIR}"
    ret=$?
    if [ ${ret} -ne 0 ] ; then
        _error "failed to mkdir ${TMP}"
    fi

    # setup rootfs to be inspected (if any)
    rootfs=""
    image_ref=""
    src_dir=""
    work_dir="${base_dir}/work"
    if [ -n "${input_inspect_image_ref}" ] ; then
        _debug "Image Reference provided: ${input_inspect_image_ref}"
        _debug "Image Reference base: $(parse_img_base "${input_inspect_image_ref}")"
        _debug "Image Reference tag: $(parse_img_tag "${input_inspect_image_ref}")"

        inspect_image_digest="$(parse_img_digest "${input_inspect_image_ref}")"
        # determine missing digest before fetch, so that we fetch the precise image
        # including its digest.
        if [ -z "${inspect_image_digest}" ] ; then
            inspect_image_digest="$(fetch_img_digest "$(parse_img_base "${input_inspect_image_ref}"):$(parse_img_tag "${input_inspect_image_ref}")")"
            ret=$?
            if [ ${ret} -ne 0 ] ; then
                _error "failed to detect image digest"
            fi
        fi
        _debug "inspect_image_digest: ${inspect_image_digest}"

        img_layout=""
        # if inspect and fetch image, then to an OCI layout dir
        if [ ! -d "${work_dir}/layouts/${inspect_image_digest/://}" ] ; then
            # we'll store the image to a path based on its digest, that it can be reused
            img_layout="$(fetch_img "$(parse_img_base "${input_inspect_image_ref}")":"$(parse_img_tag "${input_inspect_image_ref}")"@"${inspect_image_digest}" "${work_dir}"/layouts/"${inspect_image_digest/://}" )"
            ret=$?
            if [ ${ret} -ne 0 ] ; then
                _error "failed to copy image: $(parse_img_base "${input_inspect_image_ref}"):$(parse_img_tag "${input_inspect_image_ref}")@${inspect_image_digest}"
            fi
        else
            img_layout="${work_dir}/layouts/${inspect_image_digest/://}:$(parse_img_tag "${input_inspect_image_ref}")"
        fi
        _debug "image layout: ${img_layout}"

        # unpack or reuse fetched image
        unpack_dir="${work_dir}/unpacked/${inspect_image_digest/://}"
        if [ -d "${unpack_dir}" ] ; then
            _rm_rf "${unpack_dir}"
        fi
        unpack_img "${img_layout}" "${unpack_dir}"
        ret=$?
        if [ ${ret} -ne 0 ] ; then
            return ${ret}
        fi

        rootfs="${unpack_dir}/rootfs"
        image_ref="$(parse_img_base "${input_inspect_image_ref}"):$(parse_img_tag "${input_inspect_image_ref}")@${inspect_image_digest}"
        src_dir="${base_dir}/src/${inspect_image_digest/://}"
        work_dir="${base_dir}/work/${inspect_image_digest/://}"
        _info "inspecting image reference ${image_ref}"
    else
        # if we're not fething an image, then this is basically a nop
        rootfs="$(_mktemp_d)"
        image_ref="scratch"
        src_dir="$(_mktemp_d)"
        work_dir="$(_mktemp_d)"
    fi
    _debug "image layout: ${img_layout}"
    _debug "rootfs dir: ${rootfs}"

    # clear prior driver's info about source to insert into Source Image
    _rm_rf "${work_dir}/driver"

    if [ -n "${drivers}" ] ; then
        # clean up the args passed by the caller ...
        drivers="$(echo "${drivers}" | tr ',' ' '| tr '\n' ' ')"
    else
        drivers="$(set | grep '^sourcedriver_.* () ' | tr -d ' ()' | tr '\n' ' ')"
    fi

    # Prep the OCI layout for the source image
    src_img_dir="$(_mktemp_d)"
    src_img_tag="latest-source" # XXX this tag needs to be a reference to the image built from
    layout_new "${src_img_dir}" "${src_img_tag}"

    _info "calling source collection drivers"
    # iterate on the drivers
    #for driver in sourcedriver_rpm_fetch ; do
    for driver in ${drivers} ; do
        _info " --> ${driver#sourcedriver_*}"
        _mkdir_p "${src_dir}/${driver#sourcedriver_*}"
        _mkdir_p "${work_dir}/driver/${driver#sourcedriver_*}"
        $driver \
            "${image_ref}" \
            "${rootfs}" \
            "${src_dir}/${driver#sourcedriver_*}" \
            "${work_dir}/driver/${driver#sourcedriver_*}"
        ret=$?
        if [ $ret -ne 0 ] ; then
            _error "$driver failed"
        fi

        # walk the driver output to determine layers to be added
        find "${work_dir}/driver/${driver#sourcedriver_*}" -type f -name '*.json' | while read -r src_json ; do
            src_name=$(basename "${src_json}" .json)
            layout_insert \
                "${src_img_dir}" \
                "${src_dir}/${driver#sourcedriver_*}/${src_name}" \
                "/${driver#sourcedriver_*}/${src_name}" \
                "${src_json}" \
                "${src_img_tag}"
            ret=$?
            if [ $ret -ne 0 ] ; then
                # TODO probably just _error here to exit
                _warn "failed to insert layout layer for ${src_name}"
            fi
        done
    done

    _info "packed 'oci:$src_img_dir:${src_img_tag}'"

    # TODO maybe look to a directory like /usr/libexec/BuildSourceImage/drivers/ for drop-ins to run

    _info "succesfully packed 'oci:${src_img_dir}:${src_img_tag}'"
    _debug "$(skopeo inspect oci:"${src_img_dir}":"${src_img_tag}")"

    ## if an output directory is provided then save a copy to it
    if [ -n "${output_dir}" ] ; then
        _mkdir_p "${output_dir}"
        # XXX this $input_inspect_image_ref currently relies on the user passing in the `-i` flag
        push_img "oci:$src_img_dir:${src_img_tag}" "oci:$output_dir:$(ref_src_img_tag "$(parse_img_tag "${input_inspect_image_ref}")")"
        _info "copied to oci:$output_dir:$(ref_src_img_tag "$(parse_img_tag "${input_inspect_image_ref}")")"
    fi

    if [ -n "${push_image_ref}" ] ; then
        # XXX may have to parse this reference to ensure it is valid, and that it has a `-source` tag
        push_img "oci:$src_img_dir:${src_img_tag}" "${push_image_ref}"
    fi

}

# only exec main if this is being called (this way we can source and test the functions)
_is_sourced || main "${@}"

# vim:set shiftwidth=4 softtabstop=4 expandtab:
