#!/bin/sh

# This script requires an OCI IMAGE Name to pull.
# The script generates a SOURCE Image based on the OCI Image
# Script must be executed on the same OS or newer as the image.
IMAGE=$1
SRC_RPM_DIR=SRCRPMS
SRC_IMAGE=$1-src
CONTEXT_DIR=$2
EXTRA_SRC_DIR=$3
IMAGE_CTR=$(buildah from ${IMAGE})
IMAGE_MNT=$(buildah mount ${IMAGE_CTR})
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
pushd ${SRC_RPM_DIR}
export SRC_CTR=$(buildah from scratch)
for i in ${SRC_RPMS}; do
    if [ ! -f $i ]; then
	RPM=$(echo $i | sed 's/.src.rpm$//g')
	dnf download --release $RELEASE --source $RPM || continue
    fi
    echo "Adding $i"
    touch --date='@0' $i
    buildah add --add-history ${SRC_CTR} $i /RPMS
    export IMG=$(buildah commit --rm ${SRC_CTR} $i)
    export SRC_CTR=$(buildah from ${IMG})
done
popd
#
# If the caller specified a context directory,
# add it to the CONTEXT DIR in SRC IMAGE
#
if [ ! -z "${CONTEXT_DIR}" ]; then
    buildah add --add-history ${SRC_CTR} ${CONTEXT_DIR} /CONTEXT
    export IMG=$(buildah commit --rm $SRC_CTR $1_$(echo $(CONTEXT_DIR) | sed 's|/|_|g'))
    export SRC_CTR=$(buildah from ${IMG})
fi

#
# If the caller specified a extra directory,
# add it to the CONTEXT DIR in SRC IMAGE
#
if [ ! -z "${EXTRA_SRC_DIR}" ]; then
    buildah add --add-history ${SRC_CTR} ${EXTRA_SRC_DIR} /EXTRA
    export IMG=$(buildah commit --rm $EXTRA_SRC_CTR $1_$(echo $(CONTEXT_DIR) | sed 's|/|_|g'))
    export SRC_CTR=$(buildah from ${IMG})
fi

# Cleanup and remove source container
buildah rm ${SRC_CTR}

#
# Commit the SRC_CTR TO a SRC_IMAGE
#
buildah tag $IMG $SRC_IMAGE

# Push SRC_IMAGE to Registry
# buildah push $SRC_IMAGE REGISTRY_NAME/$SRC_IMAGE
