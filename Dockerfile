FROM docker.io/library/fedora:latest

RUN dnf install -y jq skopeo findutils file 'dnf-command(download)'

COPY ./BuildSourceImage.sh /usr/local/bin/BuildSourceImage.sh

RUN mkdir -p /output
ENV OUTPUT_DIR=/output
VOLUME /output

ENTRYPOINT ["/usr/local/bin/BuildSourceImage.sh"]
