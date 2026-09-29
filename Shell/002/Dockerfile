FROM redis:8.2.1-alpine

USER root

RUN apk update && \
    apk add --no-cache \
        openssh-server \
        bash \
        shadow \
        su-exec && \
    mkdir -p /var/run/sshd \
               /run/sshd \
               /opt/app \
               /opt/secret \
               /var/log/redis

RUN echo "root:ctf" | chpasswd && \
    adduser -D -s /bin/bash ctf && \
    echo "ctf:ctf" | chpasswd

WORKDIR /root

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]