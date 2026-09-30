#!/bin/sh

# 1. Generate SSH host keys dynamically if they do not exist
ssh-keygen -A

# 2. Grab variables injected by k8sWorker.js with the same aliases as the standard shell template
USER="${SSH_USER:-${SHELL_USER:-${USER_NAME:-${USERNAME:-${USER:-root}}}}}"
PASS="${SSH_PASSWORD:-${SHELL_PASSWORD:-${PASSWORD:-${USER_PASSWORD:-cyberanzen123}}}}}"
FLAG_VAL="${CHALLENGE_FLAG:-${FLAG:-${DYNAMIC_FLAG:-NECROX{broken_deployment_chain}}}}"

# Never allow the injected SSH identity to become root
if [ "$USER" = "root" ]; then
    USER="ctf"
fi

# 3. Create the dynamic player account if needed
echo "[Entrypoint] Configuring account for SSH user: $USER..."

if ! id "$USER" >/dev/null 2>&1; then
    adduser -D -s /bin/bash "$USER" 2>/dev/null || \
    useradd -m -s /bin/bash "$USER" 2>/dev/null
fi

echo "$USER:$PASS" | chpasswd

addgroup "$USER" deployops 2>/dev/null || true

# Ensure releasebot exists even if image setup was changed
if ! id releasebot >/dev/null 2>&1; then
    adduser -D -s /bin/bash releasebot
fi

addgroup releasebot releaseops 2>/dev/null || true
passwd -l releasebot >/dev/null 2>&1 || true
passwd -l root >/dev/null 2>&1 || true

# 4. Create challenge filesystem
mkdir -p \
    /run/deploy \
    /opt/deploy/bin \
    /opt/deploy/config \
    /opt/deploy/logs \
    /opt/deploy/registry \
    /var/lib/deploy/incoming \
    /var/lib/deploy/artifacts \
    /var/lib/deploy/queue \
    /srv/releases/current \
    /srv/releases/staging \
    /home/releasebot/.ssh

# 5. The real flag is root-only
printf '%s\n' "$FLAG_VAL" > /root/flag.txt
chmod 400 /root/flag.txt
chown root:root /root/flag.txt

# 6. Decoy flag only
printf '%s\n' 'NECROX{deployment_diagnostic_decoy}' > /flag.txt
chmod 444 /flag.txt

printf '%s\n' 'NECROX{deployment_operator_decoy}' > "/home/$USER/flag.txt"
chmod 444 "/home/$USER/flag.txt"
chown "$USER:$USER" "/home/$USER/flag.txt"

# 7. Permissions
chown root:root \
    /opt/deploy \
    /opt/deploy/bin \
    /opt/deploy/config \
    /opt/deploy/registry \
    /var/lib/deploy/queue \
    /srv/releases \
    /srv/releases/current \
    /srv/releases/staging

chown root:deployops \
    /opt/deploy/logs \
    /var/lib/deploy/incoming \
    /var/lib/deploy/artifacts

chmod 755 /opt/deploy
chmod 755 /opt/deploy/bin
chmod 750 /opt/deploy/config
chmod 770 /opt/deploy/logs
chmod 770 /var/lib/deploy/incoming
chmod 770 /var/lib/deploy/artifacts
chmod 755 /var/lib/deploy/queue

# 8. Generate releasebot SSH key
if [ ! -f /home/releasebot/.ssh/id_ed25519 ]; then
    ssh-keygen \
        -q \
        -t ed25519 \
        -N "" \
        -f /home/releasebot/.ssh/id_ed25519
fi

cat /home/releasebot/.ssh/id_ed25519.pub \
    > /home/releasebot/.ssh/authorized_keys

chmod 700 /home/releasebot/.ssh
chmod 600 /home/releasebot/.ssh/id_ed25519
chmod 600 /home/releasebot/.ssh/authorized_keys
chmod 644 /home/releasebot/.ssh/id_ed25519.pub

chown -R releasebot:releasebot /home/releasebot/.ssh

# 9. Runner configuration
cat > /opt/deploy/config/runner.env <<'EOF'
RUNNER_NAME=northstar-runner-01
RUNNER_TOKEN=RUNNER_7f31c9a4e2b8
REGISTRY_TOKEN=REGISTRY_2c48d0aa8f71e6c4
REGISTRY=http://127.0.0.1:18080
BROKER=/run/deploy/broker.sock
EOF

chown root:deployops /opt/deploy/config/runner.env
chmod 640 /opt/deploy/config/runner.env

# 10. Deployment configuration
cat > /opt/deploy/config/release.conf <<'EOF'
SERVICE=northstar-api
BROKER_SOCKET=/run/deploy/broker.sock
REVIEW_SOCKET=/run/deploy/review.sock
QUEUE=/var/lib/deploy/queue
RELEASE_ROOT=/srv/releases/current
WORKER=northstar-release-worker
EOF

chown root:deployops /opt/deploy/config/release.conf
chmod 640 /opt/deploy/config/release.conf

# 11. Logs containing realistic deployment artifacts
cat > /opt/deploy/logs/runner-debug.log <<'EOF'
2026-09-28T18:01:14Z runner boot
2026-09-28T18:01:21Z loading deployment configuration
2026-09-28T18:02:07Z registry authentication successful
2026-09-28T18:02:09Z requesting northstar-api:1.9.4-legacy
2026-09-28T18:02:11Z release credential cache enabled
2026-09-28T18:02:12Z deployment broker connected
2026-09-28T18:03:01Z waiting for release approval
EOF

chown root:deployops /opt/deploy/logs/runner-debug.log
chmod 640 /opt/deploy/logs/runner-debug.log

cat > /opt/deploy/logs/deployment.log <<'EOF'
2026-09-28T18:11:02Z release worker initialized
2026-09-28T18:11:03Z deployment queue initialized
2026-09-28T18:11:05Z promotion gate enabled
2026-09-28T18:11:08Z worker waiting
EOF

chown root:deployops /opt/deploy/logs/deployment.log
chmod 640 /opt/deploy/logs/deployment.log

# 12. Create backend controller
cat > /opt/deploy/bin/backend.py <<'PY'
#!/usr/bin/env python3

import http.server
import json
import os
import pwd
import socket
import struct
import tarfile
import threading
import time
import uuid
from pathlib import Path

BROKER = "/run/deploy/broker.sock"
REVIEW = "/run/deploy/review.sock"

BASE = Path("/opt/deploy")
CONFIG = BASE / "config"
LOGS = BASE / "logs"
REGISTRY = BASE / "registry"

INCOMING = Path("/var/lib/deploy/incoming")
ARTIFACTS = Path("/var/lib/deploy/artifacts")
QUEUE = Path("/var/lib/deploy/queue")
RELEASE = Path("/srv/releases/current")

RUNNER_TOKEN = "RUNNER_7f31c9a4e2b8"
REGISTRY_TOKEN = "REGISTRY_2c48d0aa8f71e6c4"

RELEASEBOT_UID = pwd.getpwnam("releasebot").pw_uid

def log(name, message):
    with open(LOGS / name, "a") as f:
        f.write(
            time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            + " "
            + message
            + "\n"
        )

def json_response(handler, code, value):
    raw = json.dumps(value).encode()

    handler.send_response(code)
    handler.send_header(
        "Content-Type",
        "application/json"
    )
    handler.send_header(
        "Content-Length",
        str(len(raw))
    )
    handler.end_headers()

    handler.wfile.write(raw)

class Registry(http.server.BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        log(
            "registry.log",
            fmt % args
        )

    def authorized(self):
        return (
            self.headers.get("Authorization", "")
            == "Bearer " + REGISTRY_TOKEN
        )

    def do_GET(self):

        if not self.authorized():
            json_response(
                self,
                401,
                {
                    "error":
                    "registry authentication required"
                }
            )
            return

        if self.path == "/v1/catalog":

            json_response(
                self,
                200,
                {
                    "repository":
                    "northstar-api",
                    "tags": [
                        "1.8.1",
                        "1.9.2",
                        "1.9.4-legacy"
                    ]
                }
            )
            return

        prefix = "/v1/blob/"

        if self.path.startswith(prefix):

            filename = self.path[len(prefix):]

            if "/" in filename:
                json_response(
                    self,
                    404,
                    {"error": "not found"}
                )
                return

            target = REGISTRY / filename

            if not target.is_file():
                json_response(
                    self,
                    404,
                    {"error": "not found"}
                )
                return

            data = target.read_bytes()

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "application/octet-stream"
            )
            self.send_header(
                "Content-Length",
                str(len(data))
            )
            self.end_headers()

            self.wfile.write(data)
            return

        json_response(
            self,
            404,
            {"error": "not found"}
        )

    def log_message(self, fmt, *args):
        return

def start_registry():

    server = http.server.ThreadingHTTPServer(
        ("127.0.0.1", 18080),
        Registry
    )

    log(
        "registry.log",
        "internal registry listening"
    )

    server.serve_forever()

def send_line(conn, value):
    conn.sendall(
        (value + "\n").encode()
    )

def broker_client(conn):

    authenticated = False

    send_line(
        conn,
        "NORTHSTAR DEPLOYMENT BROKER v3"
    )

    send_line(
        conn,
        "AUTH <token> | STATUS | SUBMIT <file> | HELP"
    )

    while True:

        data = conn.recv(4096)

        if not data:
            break

        line = data.decode(
            errors="replace"
        ).strip()

        if not line:
            continue

        parts = line.split(
            " ",
            1
        )

        command = parts[0].upper()

        argument = (
            parts[1].strip()
            if len(parts) == 2
            else ""
        )

        if command == "HELP":

            send_line(
                conn,
                "AUTH <token> | STATUS | SUBMIT <artifact>"
            )

            continue

        if command == "STATUS":

            send_line(
                conn,
                "state=healthy queue=promotion-gated"
            )

            continue

        if command == "AUTH":

            authenticated = (
                argument == RUNNER_TOKEN
            )

            send_line(
                conn,
                "AUTH OK"
                if authenticated
                else
                "AUTH FAILED"
            )

            continue

        if command == "SUBMIT":

            if not authenticated:

                send_line(
                    conn,
                    "ERR authentication required"
                )

                continue

            name = os.path.basename(
                argument
            )

            if not name.endswith(
                ".tar.gz"
            ):

                send_line(
                    conn,
                    "ERR archive required"
                )

                continue

            source = INCOMING / name

            if not source.is_file():

                send_line(
                    conn,
                    "ERR artifact not found"
                )

                continue

            job = uuid.uuid4().hex[:12]

            destination = (
                ARTIFACTS /
                (job + ".tar.gz")
            )

            destination.write_bytes(
                source.read_bytes()
            )

            (QUEUE / (
                job + ".pending"
            )).write_text(
                destination.name
            )

            source.unlink(
                missing_ok=True
            )

            log(
                "broker.log",
                "artifact submitted job=" + job
            )

            send_line(
                conn,
                "SUBMITTED " + job
            )

            continue

        send_line(
            conn,
            "ERR unknown command"
        )

def start_broker():

    try:
        os.unlink(BROKER)
    except FileNotFoundError:
        pass

    server = socket.socket(
        socket.AF_UNIX,
        socket.SOCK_STREAM
    )

    server.bind(BROKER)
    os.chmod(BROKER, 0o660)

    import grp

    os.chown(
        BROKER,
        0,
        grp.getgrnam("deployops").gr_gid
    )

    server.listen(10)

    while True:

        conn, _ = server.accept()

        threading.Thread(
            target=broker_client,
            args=(conn,),
            daemon=True
        ).start()

def get_peer_uid(conn):

    data = conn.getsockopt(
        socket.SOL_SOCKET,
        socket.SO_PEERCRED,
        12
    )

    _, uid, _ = struct.unpack(
        "3i",
        data
    )

    return uid

def start_review():

    try:
        os.unlink(REVIEW)
    except FileNotFoundError:
        pass

    server = socket.socket(
        socket.AF_UNIX,
        socket.SOCK_STREAM
    )

    server.bind(REVIEW)
    os.chmod(REVIEW, 0o660)

    import grp

    os.chown(
        REVIEW,
        0,
        grp.getgrnam("releaseops").gr_gid
    )

    server.listen(10)

    while True:

        conn, _ = server.accept()

        try:

            uid = get_peer_uid(conn)

            request = conn.recv(
                4096
            ).decode(
                errors="replace"
            ).strip()

            if uid != RELEASEBOT_UID:

                send_line(
                    conn,
                    "ERR promotion access denied"
                )

                continue

            parts = request.split()

            if (
                len(parts) != 2 or
                parts[0].upper() != "PROMOTE"
            ):

                send_line(
                    conn,
                    "ERR usage PROMOTE <job>"
                )

                continue

            job = parts[1]

            pending = (
                QUEUE /
                (job + ".pending")
            )

            approved = (
                QUEUE /
                (job + ".approved")
            )

            if not pending.is_file():

                send_line(
                    conn,
                    "ERR job not found"
                )

                continue

            pending.rename(
                approved
            )

            log(
                "promotion.log",
                "promoted job=" + job
            )

            send_line(
                conn,
                "PROMOTED " + job
            )

        finally:
            conn.close()

def release_worker():

    while True:

        for approved in list(
            QUEUE.glob("*.approved")
        ):

            try:

                job = approved.name.split(".")[0]

                archive_name = approved.read_text().strip()

                archive = (
                    ARTIFACTS /
                    archive_name
                )

                if not archive.is_file():
                    approved.unlink(
                        missing_ok=True
                    )
                    continue

                log(
                    "worker.log",
                    "deploying job=" + job
                )

                with tarfile.open(
                    archive,
                    "r:gz"
                ) as tar:

                    # Intentionally vulnerable:
                    # archive is extracted as root without
                    # validating the post-install hook.
                    tar.extractall(
                        RELEASE
                    )

                hook = (
                    RELEASE /
                    "hooks" /
                    "post-install.sh"
                )

                if hook.is_file():

                    os.chmod(
                        hook,
                        0o755
                    )

                    os.system(
                        str(hook)
                    )

                log(
                    "worker.log",
                    "completed job=" + job
                )

                approved.unlink(
                    missing_ok=True
                )

                archive.unlink(
                    missing_ok=True
                )

            except Exception as exc:

                log(
                    "worker.log",
                    "worker error " + repr(exc)
                )

                approved.unlink(
                    missing_ok=True
                )

        time.sleep(2)

def main():

    workers = [
        threading.Thread(
            target=start_registry,
            daemon=True
        ),
        threading.Thread(
            target=start_broker,
            daemon=True
        ),
        threading.Thread(
            target=start_review,
            daemon=True
        ),
        threading.Thread(
            target=release_worker,
            daemon=True
        )
    ]

    for worker in workers:
        worker.start()

    while True:
        time.sleep(3600)

main()
PY

chmod 755 /opt/deploy/bin/backend.py
chown root:root /opt/deploy/bin/backend.py

# 13. Helper commands
cat > /usr/local/bin/deployctl <<'EOF'
#!/bin/sh

SOCK=/run/deploy/broker.sock

case "${1:-}" in

    status)
        printf 'STATUS\n' |
        socat - UNIX-CONNECT:"$SOCK"
        ;;

    help)
        printf 'HELP\n' |
        socat - UNIX-CONNECT:"$SOCK"
        ;;

    *)
        echo "usage: deployctl status"
        echo "       deployctl help"
        ;;

esac
EOF

chmod 755 /usr/local/bin/deployctl

cat > /usr/local/bin/releasectl <<'EOF'
#!/bin/sh

SOCK=/run/deploy/review.sock

if [ "${1:-}" != "promote" ]; then
    echo "usage: releasectl promote <job-id>"
    exit 1
fi

printf 'PROMOTE %s\n' "$2" |
socat - UNIX-CONNECT:"$SOCK"
EOF

chmod 755 /usr/local/bin/releasectl

# 14. Create legacy registry artifact containing the release identity
python3 - <<'PY'
import io
import os
import tarfile

registry = "/opt/deploy/registry/northstar-api-1.9.4-legacy.tar.gz"
key = "/home/releasebot/.ssh/id_ed25519"

with tarfile.open(registry, "w:gz") as tar:

    info = tarfile.TarInfo(
        "release-manifest.txt"
    )

    data = (
        b"northstar-api 1.9.4-legacy\n"
        b"release identity retained for rollback\n"
        b"operator=releasebot\n"
    )

    info.size = len(data)
    info.mode = 0o644

    tar.addfile(
        info,
        io.BytesIO(data)
    )

    with open(key, "rb") as f:
        key_data = f.read()

    key_info = tarfile.TarInfo(
        "backup/.rollback/id_ed25519"
    )

    key_info.size = len(key_data)
    key_info.mode = 0o600

    tar.addfile(
        key_info,
        io.BytesIO(key_data)
    )
PY

chown root:root \
    /opt/deploy/registry/northstar-api-1.9.4-legacy.tar.gz

chmod 644 \
    /opt/deploy/registry/northstar-api-1.9.4-legacy.tar.gz

# 15. Start the entire deployment backend as a single low-memory process
python3 \
    /opt/deploy/bin/backend.py \
    >/opt/deploy/logs/backend.log \
    2>&1 &

sleep 2

# 16. Validate backend startup
if [ ! -S /run/deploy/broker.sock ]; then
    echo "[Entrypoint] deployment broker failed"
    cat /opt/deploy/logs/backend.log 2>/dev/null || true
    exit 1
fi

if [ ! -S /run/deploy/review.sock ]; then
    echo "[Entrypoint] promotion service failed"
    cat /opt/deploy/logs/backend.log 2>/dev/null || true
    exit 1
fi

# 17. Ensure SSH configuration matches the dynamic Doom environment
sed -i '/^#*PasswordAuthentication/d' /etc/ssh/sshd_config 2>/dev/null || true
sed -i '/^#*PermitRootLogin/d' /etc/ssh/sshd_config 2>/dev/null || true
sed -i '/^#*KbdInteractiveAuthentication/d' /etc/ssh/sshd_config 2>/dev/null || true
sed -i '/^#*UsePAM/d' /etc/ssh/sshd_config 2>/dev/null || true
sed -i '/^#*AuthenticationMethods/d' /etc/ssh/sshd_config 2>/dev/null || true
sed -i '/^#*PubkeyAuthentication/d' /etc/ssh/sshd_config 2>/dev/null || true

echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
echo "KbdInteractiveAuthentication yes" >> /etc/ssh/sshd_config
echo "UsePAM no" >> /etc/ssh/sshd_config
echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config

# 18. Unset sensitive deployment variables before handing control to SSH
unset SSH_PASSWORD SHELL_PASSWORD PASSWORD USER_PASSWORD
unset SSH_USER SHELL_USER USER_NAME USERNAME USER
unset FLAG CHALLENGE_FLAG DYNAMIC_FLAG

# 19. Start SSH daemon in the foreground exactly like the Doom shell template
exec /usr/sbin/sshd -D -e