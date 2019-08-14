FROM quay.io/buildah/stable
RUN dnf install -y skopeo && \
    dnf clean all && \
    mkdir -p /output
COPY . /usr/local/bin/
VOLUME /var/lib/container
VOLUME /output
ENV OUTPUT_DIR=/output
ENTRYPOINT ["/usr/local/bin/BuildSourceImage.sh"]
