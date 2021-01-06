FROM docker.io/library/fedora:33

RUN dnf install -y jq skopeo findutils file wget 'dnf-command(download)'

COPY ./BuildSourceImage.sh /usr/local/bin/BuildSourceImage.sh

ENV BASE_DIR=/tmp

ENTRYPOINT ["/usr/local/bin/BuildSourceImage.sh"]
