FROM redis:8.2.1-bookworm

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        bash \
        gosu \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd \
               /opt/app \
               /opt/secret \
               /var/log/redis \
               /var/lib/redis

WORKDIR /opt/challenge

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]