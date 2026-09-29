FROM redis:8.2.1-alpine

USER root

RUN apk add --no-cache \
        openssh-server \
        bash \
        su-exec \
    && mkdir -p \
        /run/sshd \
        /var/run/sshd \
        /opt/app \
        /opt/secret \
        /var/log/redis \
        /var/lib/redis

RUN adduser -D -s /bin/bash ctf \
    && echo "ctf:ctf" | chpasswd

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]