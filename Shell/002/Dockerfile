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
    tar

RUN mkdir -p \
    /var/run/sshd \
    /run/deploy \
    /opt/deploy/bin \
    /opt/deploy/config \
    /opt/deploy/logs \
    /var/lib/deploy/queue \
    /var/lib/deploy/artifacts \
    /srv/releases/current \
    /srv/releases/staging

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]