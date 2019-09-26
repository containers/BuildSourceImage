FROM docker.io/library/fedora:latest

RUN dnf install -y jq skopeo findutils file 'dnf-command(download)'

COPY ./BuildSourceImage.sh /usr/local/bin/BuildSourceImage.sh

ENV BASE_DIR=/tmp

ENTRYPOINT ["/usr/local/bin/BuildSourceImage.sh"]
