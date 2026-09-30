FROM alpine:3.18

RUN apk add --no-cache \
    openssh-server \
    bash \
    shadow \
    python3 \
    coreutils \
    findutils \
    procps \
    iproute2 \
    util-linux \
    socat \
    tar \
    gzip \
    curl

RUN mkdir -p \
    /var/run/sshd \
    /run/deploy \
    /opt/deploy \
    /var/lib/deploy \
    /srv/releases

COPY entrypoint.sh /entrypoint.sh

RUN chmod 755 /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
