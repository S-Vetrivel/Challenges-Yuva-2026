FROM alpine:3.18

RUN apk add --no-cache \
    openssh-server \
    bash \
    shadow \
    python3 \
    py3-pip \
    curl \
    jq \
    tar \
    gzip \
    openssl

RUN mkdir -p \
    /var/run/sshd \
    /run/northstar \
    /opt/northstar/bin \
    /opt/northstar/runtime \
    /etc/northstar \
    /etc/northstar/hooks \
    /var/lib/northstar \
    /var/lib/northstar/jobs \
    /srv/releases/incoming \
    /srv/releases/staging \
    /srv/releases/live

RUN addgroup -S deploy && \
    adduser -S -D -H -s /sbin/nologin -G deploy northstar && \
    adduser -D -s /bin/bash ctf && \
    addgroup ctf deploy && \
    echo 'ctf:ctf' | chpasswd && \
    passwd -l root

RUN sed -i '/^#*PermitRootLogin/d' /etc/ssh/sshd_config && \
    sed -i '/^#*PasswordAuthentication/d' /etc/ssh/sshd_config && \
    sed -i '/^#*KbdInteractiveAuthentication/d' /etc/ssh/sshd_config && \
    sed -i '/^#*UsePAM/d' /etc/ssh/sshd_config && \
    printf '%s\n' \
      'PermitRootLogin no' \
      'PasswordAuthentication yes' \
      'KbdInteractiveAuthentication yes' \
      'UsePAM no' \
      'AllowGroups sshusers' >> /etc/ssh/sshd_config && \
    addgroup -S sshusers && \
    addgroup ctf sshusers

RUN chown -R root:deploy /srv/releases /var/lib/northstar /run/northstar /opt/northstar && \
    chmod 2770 /srv/releases/incoming /srv/releases/staging /srv/releases/live && \
    chmod 2750 /var/lib/northstar /var/lib/northstar/jobs && \
    chmod 2750 /opt/northstar/bin

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]