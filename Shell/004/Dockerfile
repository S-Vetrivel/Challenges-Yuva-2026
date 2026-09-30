FROM alpine:3.18

RUN apk update && \
    apk add --no-cache \
        openssh-server \
        bash \
        shadow \
        python3 \
        py3-pip \
        ca-certificates && \
    mkdir -p /var/run/sshd

RUN sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config && \
    echo "" >> /etc/ssh/sshd_config && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "KbdInteractiveAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "UsePAM no" >> /etc/ssh/sshd_config

RUN echo "root:ctf" | chpasswd && \
    adduser -D -s /bin/bash ctf && \
    echo "ctf:ctf" | chpasswd

RUN mkdir -p /opt/wsocket

RUN python3 -m pip install \
    --break-system-packages \
    --no-cache-dir \
    websockets==12.0

WORKDIR /root

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]