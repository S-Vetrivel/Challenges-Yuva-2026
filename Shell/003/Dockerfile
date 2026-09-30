FROM alpine:3.18

# Install OpenSSH, shell utilities, Python and archive/network tools
RUN apk update && \
    apk add --no-cache \
        openssh-server \
        bash \
        shadow \
        python3 \
        tar \
        gzip \
        curl \
        socat \
        coreutils \
        findutils \
        procps \
        iproute2 && \
    mkdir -p /var/run/sshd

# Configure SSH
RUN sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config && \
    echo "" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config && \
    echo "KbdInteractiveAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "UsePAM no" >> /etc/ssh/sshd_config && \
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config

# Create challenge groups and base user
RUN addgroup -S deployops && \
    addgroup -S releaseops && \
    adduser -D -s /bin/bash ctf && \
    addgroup ctf deployops

# Create releasebot identity
RUN adduser -D -s /bin/bash releasebot && \
    addgroup releasebot releaseops && \
    passwd -l root && \
    passwd -l releasebot

WORKDIR /root

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]