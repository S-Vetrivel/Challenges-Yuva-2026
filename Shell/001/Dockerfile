FROM alpine:3.20

RUN apk add --no-cache openssh

RUN mkdir -p /run/sshd

WORKDIR /opt/challenge

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]