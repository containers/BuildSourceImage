FROM fedora

RUN dnf install -y jq skopeo findutils file 'dnf-command(download)'

COPY . /usr/local/bin/

RUN mkdir -p /output
ENV OUTPUT_DIR=/output
VOLUME /output

ENV SRC_DIR=/src
VOLUME /src

ENTRYPOINT ["/usr/local/bin/BuildSourceImage.sh"]
