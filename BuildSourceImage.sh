#!/bin/sh

# This script requires an OCI IMAGE Name to pull.
# The script generates a SOURCE Image based on the OCI Image
# Script must be executed on the same OS or newer as the image.
if test $# -lt 2 ; then
    echo Usage: $(basename $0) IMAGE CONTEXT_DIR [EXTRA_SRC_DIR]
    exit 1
fi
export IMAGE=$1
export SRC_RPM_DIR=$(pwd)/SRCRPMS
export SRC_IMAGE=$1-src
export CONTEXT_DIR=$2
export EXTRA_SRC_DIR=$3
export IMAGE_CTR=$(buildah from ${IMAGE})
export IMAGE_MNT=$(buildah mount ${IMAGE_CTR})
#
# From the executable image, get the RELEASEVER of the image
#
RELEASE=$(rpm -q --queryformat "%{VERSION}\n" --root $IMAGE_MNT -f /etc/os-release)
#
# From the executable image, list the SRC RPMS used to build the image
#
SRC_RPMS=$(rpm -qa --root ${IMAGE_MNT} --queryformat '%{SOURCERPM}\n' | grep -v '^gpg-pubkey' | sort -u)
buildah umount ${IMAGE_CTR}
buildah rm ${IMAGE_CTR}

#
# For each SRC_RPMS used to build the executable image, download the SRC RPM
# and generate a layer in the SRC RPM.
#
mkdir -p ${SRC_RPM_DIR}
pushd ${SRC_RPM_DIR} > /dev/null
export SRC_CTR=$(buildah from scratch)
for srpm in ${SRC_RPMS}; do
    if [ ! -f ${srpm} ]; then
	RPM=$(echo ${srpm} | sed 's/.src.rpm$//g')
	dnf download --release $RELEASE --source $RPM || continue
    fi
    echo "Adding ${srpm}"
    touch --date=@`rpm -q --qf '%{buildtime}' ${srpm}` ${srpm}
    buildah add ${SRC_CTR} ${srpm} /RPMS/
    buildah config --created-by "/bin/sh -c #(nop) ADD file:$(sha256sum ${srpm} | cut -f1 -d' ') in /RPMS" ${SRC_CTR}
    export IMG=$(buildah commit --omit-timestamp --disable-compression --rm ${SRC_CTR})
    export SRC_CTR=$(buildah from ${IMG})
done
popd > /dev/null
#
# If the caller specified a context directory,
# add it to the CONTEXT DIR in SRC IMAGE
#
if [ ! -z "${CONTEXT_DIR}" ]; then
    CONTEXT_DIR=$(cd ${CONTEXT_DIR}; pwd)
    buildah add ${SRC_CTR} ${CONTEXT_DIR} /CONTEXT
    buildah config --created-by "/bin/sh -c #(nop) ADD file:$(cd ${CONTEXT_DIR}; tar cf - . | sha256sum -| cut -f1 -d' ') in /CONTEXT" ${SRC_CTR}
    export IMG=$(buildah commit --omit-timestamp --rm ${SRC_CTR})
    export SRC_CTR=$(buildah from ${IMG})
fi

#
# If the caller specified a extra directory,
# add it to the CONTEXT DIR in SRC IMAGE
#
if [ ! -z "${EXTRA_SRC_DIR}" ]; then
    buildah add ${SRC_CTR} ${EXTRA_SRC_DIR} /EXTRA
    buildah config --created-by "/bin/sh -c #(nop) ADD file:$(cd ${EXTRA_SRC_DIR}; tar cf - . | sha256sum -| cut -f1 -d' ') in /CONTEXT" ${SRC_CTR}
    export IMG=$(buildah commit --omit-timestamp --rm ${EXTRA_SRC_CTR})
    export SRC_CTR=$(buildah from ${IMG})
fi

# Cleanup and remove source container
buildah rm ${SRC_CTR}

#
# Add the final name to our image
#
buildah tag $IMG $SRC_IMAGE

# Push SRC_IMAGE to Registry
# buildah push $SRC_IMAGE REGISTRY_NAME/$SRC_IMAGE
