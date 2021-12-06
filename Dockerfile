FROM quay.io/skopeo/stable

RUN dnf install -y jq findutils file wget 'dnf-command(download)'

COPY ./BuildSourceImage.sh /usr/local/bin/BuildSourceImage.sh

ENV BASE_DIR=/tmp

ENTRYPOINT ["/usr/local/bin/BuildSourceImage.sh"]
