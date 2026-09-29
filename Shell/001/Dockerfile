FROM alpine:3.20

RUN apk add --no-cache \
    openssh \
    bash \
    shadow \
    coreutils \
    grep \
    findutils

WORKDIR /opt/challenge

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
