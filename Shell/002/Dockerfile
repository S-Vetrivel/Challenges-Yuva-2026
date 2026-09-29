FROM redis:8.2.1-bookworm

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        bash \
        gosu \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd /var/log/redis /opt/app /opt/secret

WORKDIR /opt/challenge

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 22 6379

ENTRYPOINT ["/entrypoint.sh"]