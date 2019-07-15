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
SRC_CTR=$(buildah from scratch)
SRC_MNT=$(buildah mount ${SRC_CTR})
#
# From the executable image, get the RELEASEVER of the image
# 
RELEASE=$(rpm -q --queryformat "%{VERSION}\n" --root $IMAGE_MNT -f /etc/os-release)
#
# From the executable image, list the SRC RPMS used to build the image
# 
SRC_RPMS=$(rpm -qa --root ${IMAGE_MNT} --queryformat '%{SOURCERPM}\n' | grep -v '^gpg-pubkey' | sort -u)

#
# Create directory in source container image for RPMS
#
mkdir -p ${SRC_RPM_DIR} ${SRC_MNT}/RPMS
#
# For each SRC_RPMS used to build the executable image, download the SRC RPM
# and generate a layer in the SRC RPM.
# 
(cd ${SRC_RPM_DIR};
set -x
for i in ${SRC_RPMS}; do
    if [ ! -f $i ]; then
         RPM=$(echo $i | sed 's/.src.rpm$//g')
         dnf download --release $RELEASE --source $RPM || continue
    fi
    cp $i $SRC_MNT/RPMS
    buildah commit $SRC_CTR $i
done
)
#
# If the caller specified a context directory,
# add it to the CONTEXT DIR in SRC IMAGE
#
if [ ! -z "${CONTEXT_DIR}" ]; then
    cp -R ${CONTEXT_DIR} ${SRC_MNT}/CONTEXT
    buildah commit $SRC_CTR $1_$(echo $(CONTEXT_DIR) | sed 's|/|_|g')
fi

#
# If the caller specified a extra directory,
# add it to the CONTEXT DIR in SRC IMAGE
#
if [ ! -z "${EXTRA_SRC_DIR}" ]; then
    cp -R ${EXTRA_SRC_DIR} ${SRC_MNT}/EXTRA
    buildah commit $SRC_CTR $1_$(echo $(EXTRA_SRC_DIR) | sed 's|/|_|g')
fi

#
# Commit the SRC_CTR TO a SRC_IMAGE
#
buildah commit $SRC_CTR $SRC_IMAGE

# Push SRC_IMAGE to Registry
# buildah push $SRC_IMAGE REGISTRY_NAME/$SRC_IMAGE

# Cleanup and remove containers
buildah umount ${SRC_CTR} ${IMAGE_CTR}
buildah rm ${SRC_CTR} ${IMAGE_CTR}
