FROM fedora

RUN dnf install -y skopeo golang jq git
RUN dnf install -y make findutils
ENV GOPATH=/usr/share/gocode
ENV GOBIN=/usr/local/bin
RUN git clone https://github.com/openSUSE/umoci $GOPATH/src/github.com/openSUSE/umoci
RUN cd $GOPATH/src/github.com/openSUSE/umoci && \
    make && \
    mv umoci /usr/local/bin

COPY . /usr/local/bin/

RUN mkdir -p /output
ENV OUTPUT_DIR=/output
VOLUME /output

ENV SRC_DIR=/src
VOLUME /src

#ENTRYPOINT ["/usr/local/bin/BuildSourceImage.sh"]
