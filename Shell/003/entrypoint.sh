#!/bin/sh

set -eu

ssh-keygen -A

USER="${SSH_USER:-${SHELL_USER:-${USER_NAME:-${USERNAME:-${USER:-root}}}}}"
PASS="${SSH_PASSWORD:-${SHELL_PASSWORD:-${PASSWORD:-${USER_PASSWORD:-cyberanzen123}}}}"
FLAG_VAL="${CHALLENGE_FLAG:-${FLAG:-${DYNAMIC_FLAG:-NECROX{broken_deployment_chain}}}}"

if [ "$USER" = "root" ]; then
    USER="ctf"
fi

getent group deployops >/dev/null 2>&1 || addgroup -S deployops
getent group releaseops >/dev/null 2>&1 || addgroup -S releaseops

if ! id "$USER" >/dev/null 2>&1; then
    adduser -D -s /bin/bash "$USER"
fi

echo "$USER:$PASS" | chpasswd
addgroup "$USER" deployops 2>/dev/null || true

if ! id releasebot >/dev/null 2>&1; then
    adduser -D -s /bin/bash releasebot
fi

addgroup releasebot releaseops 2>/dev/null || true

passwd -l root >/dev/null 2>&1 || true
passwd -l releasebot >/dev/null 2>&1 || true

rm -f /flag.txt
rm -f "/home/$USER/flag.txt"

printf '%s\n' "$FLAG_VAL" > /root/flag.txt
chmod 400 /root/flag.txt
chown root:root /root/flag.txt

printf '%s\n' 'NECROX{not_the_real_flag}' > /flag.txt
chmod 444 /flag.txt

mkdir -p "/home/$USER"
printf '%s\n' 'NECROX{decoy_broken_deployment}' > "/home/$USER/flag.txt"
chmod 444 "/home/$USER/flag.txt"
chown "$USER:$USER" "/home/$USER/flag.txt"

mkdir -p \
    /run/deploy \
    /opt/deploy/bin \
    /opt/deploy/config \
    /opt/deploy/registry \
    /opt/deploy/logs \
    /var/lib/deploy/incoming \
    /var/lib/deploy/artifacts \
    /var/lib/deploy/queue \
    /srv/releases/current \
    /srv/releases/staging

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

chmod 750 /opt/deploy/config
chmod 770 /opt/deploy/logs
chmod 770 /var/lib/deploy/incoming
chmod 770 /var/lib/deploy/artifacts

mkdir -p /home/releasebot/.ssh
chmod 700 /home/releasebot/.ssh
chown -R releasebot:releasebot /home/releasebot/.ssh

if [ ! -f /home/releasebot/.ssh/id_ed25519 ]; then
    ssh-keygen \
        -q \
        -t ed25519 \
        -N "" \
        -f /home/releasebot/.ssh/id_ed25519
fi

cat /home/releasebot/.ssh/id_ed25519.pub \
    > /home/releasebot/.ssh/authorized_keys

chmod 600 \
    /home/releasebot/.ssh/id_ed25519 \
    /home/releasebot/.ssh/authorized_keys

chmod 644 \
    /home/releasebot/.ssh/id_ed25519.pub

chown -R releasebot:releasebot /home/releasebot/.ssh

cat > /opt/deploy/config/runner.env <<'EOF_RUNNER'
RUNNER_TOKEN=RUNNER_7f31c9a4e2b8
REGISTRY_TOKEN=REGISTRY_2c48d0aa8f71e6c4
REGISTRY=http://127.0.0.1:18080
RUNNER=northstar-runner-01
EOF_RUNNER

chown root:deployops /opt/deploy/config/runner.env
chmod 640 /opt/deploy/config/runner.env

cat > /opt/deploy/config/release.conf <<'EOF_CONF'
SERVICE=northstar-api
BROKER=/run/deploy/broker.sock
REVIEW=/run/deploy/review.sock
QUEUE=/var/lib/deploy/queue
RELEASE=/srv/releases/current
WORKER=northstar-release-worker
EOF_CONF

chown root:deployops /opt/deploy/config/release.conf
chmod 640 /opt/deploy/config/release.conf

cat > /opt/deploy/logs/runner-debug.log <<'EOF_LOG'
2026-09-28T18:01:14Z runner boot
2026-09-28T18:02:07Z registry authentication successful
2026-09-28T18:02:09Z legacy artifact requested
2026-09-28T18:02:11Z release credential cache enabled
2026-09-28T18:02:12Z deployment broker connected
2026-09-28T18:03:01Z waiting for release approval
EOF_LOG

chown root:deployops /opt/deploy/logs/runner-debug.log
chmod 640 /opt/deploy/logs/runner-debug.log

cat > /opt/deploy/logs/deployment.log <<'EOF_LOG'
2026-09-28T18:11:02Z worker started uid=0
2026-09-28T18:11:03Z deployment queue initialized
2026-09-28T18:11:05Z promotion gate enabled
2026-09-28T18:11:08Z release worker waiting
EOF_LOG

chown root:deployops /opt/deploy/logs/deployment.log
chmod 640 /opt/deploy/logs/deployment.log

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

BASE = Path("/opt/deploy")
REGISTRY = BASE / "registry"
LOGS = BASE / "logs"

INCOMING = Path("/var/lib/deploy/incoming")
ARTIFACTS = Path("/var/lib/deploy/artifacts")
QUEUE = Path("/var/lib/deploy/queue")
RELEASE = Path("/srv/releases/current")

BROKER_SOCKET = "/run/deploy/broker.sock"
REVIEW_SOCKET = "/run/deploy/review.sock"

RUNNER_TOKEN = "RUNNER_7f31c9a4e2b8"
REGISTRY_TOKEN = "REGISTRY_2c48d0aa8f71e6c4"

RELEASEBOT_UID = pwd.getpwnam("releasebot").pw_uid

for path in [
    REGISTRY,
    LOGS,
    INCOMING,
    ARTIFACTS,
    QUEUE,
    RELEASE
]:
    path.mkdir(parents=True, exist_ok=True)


def log(filename, message):
    with open(LOGS / filename, "a") as f:
        f.write(
            time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) +
            " " +
            message +
            "\n"
        )


class RegistryHandler(http.server.BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        log("registry.log", fmt % args)

    def send_json(self, code, data):
        raw = json.dumps(data).encode()

        self.send_response(code)
        self.send_header(
            "Content-Type",
            "application/json"
        )
        self.send_header(
            "Content-Length",
            str(len(raw))
        )
        self.end_headers()
        self.wfile.write(raw)

    def authorized(self):
        return (
            self.headers.get("Authorization", "") ==
            "Bearer " + REGISTRY_TOKEN
        )

    def do_GET(self):

        if not self.authorized():
            self.send_json(
                401,
                {
                    "error":
                    "registry authentication required"
                }
            )
            return

        if self.path == "/v1/catalog":

            self.send_json(
                200,
                {
                    "name": "northstar-internal",
                    "repositories": [
                        "northstar-api",
                        "northstar-worker"
                    ],
                    "tags": {
                        "northstar-api": [
                            "1.8.1",
                            "1.9.2",
                            "1.9.4-legacy"
                        ],
                        "northstar-worker": [
                            "3.2.0"
                        ]
                    }
                }
            )
            return

        if self.path.startswith("/v1/blob/"):

            name = self.path[
                len("/v1/blob/"):
            ]

            if "/" in name:
                self.send_json(
                    404,
                    {"error": "artifact not found"}
                )
                return

            target = REGISTRY / name

            if not target.is_file():
                self.send_json(
                    404,
                    {"error": "artifact not found"}
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

        self.send_json(
            404,
            {"error": "not found"}
        )

    def do_POST(self):

        self.send_json(
            405,
            {"error": "method not allowed"}
        )


def registry_thread():

    server = http.server.ThreadingHTTPServer(
        ("127.0.0.1", 18080),
        RegistryHandler
    )

    log(
        "registry.log",
        "registry listening on 127.0.0.1:18080"
    )

    server.serve_forever()


def send_line(conn, text):
    conn.sendall(
        (text + "\n").encode()
    )


def broker_client(conn):

    authenticated = False

    send_line(
        conn,
        "NORTHSTAR DEPLOYMENT BROKER v3"
    )

    send_line(
        conn,
        "Commands: AUTH STATUS SUBMIT HELP"
    )

    while True:

        raw = conn.recv(4096)

        if not raw:
            break

        line = raw.decode(
            errors="replace"
        ).strip()

        if not line:
            continue

        pieces = line.split(
            " ",
            1
        )

        command = pieces[0].upper()

        argument = (
            pieces[1].strip()
            if len(pieces) == 2
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
                "runner=northstar-runner-01 state=healthy queue=promotion-gated"
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
                    "ERR only .tar.gz artifacts accepted"
                )

                continue

            source = INCOMING / name

            if not source.is_file():

                send_line(
                    conn,
                    "ERR artifact not found in incoming"
                )

                continue

            job = uuid.uuid4().hex[:12]

            target = (
                ARTIFACTS /
                (job + ".tar.gz")
            )

            target.write_bytes(
                source.read_bytes()
            )

            (
                QUEUE /
                (job + ".pending")
            ).write_text(
                target.name
            )

            source.unlink(
                missing_ok=True
            )

            log(
                "broker.log",
                "submitted job=" + job
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


def broker_thread():

    try:
        os.unlink(
            BROKER_SOCKET
        )
    except FileNotFoundError:
        pass

    server = socket.socket(
        socket.AF_UNIX,
        socket.SOCK_STREAM
    )

    server.bind(
        BROKER_SOCKET
    )

    os.chmod(
        BROKER_SOCKET,
        0o660
    )

    import grp

    os.chown(
        BROKER_SOCKET,
        0,
        grp.getgrnam(
            "deployops"
        ).gr_gid
    )

    server.listen(10)

    log(
        "broker.log",
        "broker started"
    )

    while True:

        conn, _ = server.accept()

        threading.Thread(
            target=broker_client,
            args=(conn,),
            daemon=True
        ).start()


def peer_uid(conn):

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


def review_thread():

    try:
        os.unlink(
            REVIEW_SOCKET
        )
    except FileNotFoundError:
        pass

    server = socket.socket(
        socket.AF_UNIX,
        socket.SOCK_STREAM
    )

    server.bind(
        REVIEW_SOCKET
    )

    os.chmod(
        REVIEW_SOCKET,
        0o660
    )

    import grp

    os.chown(
        REVIEW_SOCKET,
        0,
        grp.getgrnam(
            "releaseops"
        ).gr_gid
    )

    server.listen(10)

    log(
        "promotion.log",
        "promotion service started"
    )

    while True:

        conn, _ = server.accept()

        try:

            uid = peer_uid(
                conn
            )

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
                    "ERR usage: PROMOTE <job-id>"
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
                    "ERR pending job not found"
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


def process_release():

    for approved in sorted(
        QUEUE.glob(
            "*.approved"
        )
    ):

        try:

            job = approved.name.split(
                "."
            )[0]

            artifact_name = (
                approved.read_text()
                .strip()
            )

            artifact = (
                ARTIFACTS /
                artifact_name
            )

            if not artifact.is_file():

                approved.unlink(
                    missing_ok=True
                )

                continue

            log(
                "worker.log",
                "processing job=" + job
            )

            with tarfile.open(
                artifact,
                "r:gz"
            ) as archive:

                archive.extractall(
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
                "deployed job=" + job
            )

            approved.unlink(
                missing_ok=True
            )

            artifact.unlink(
                missing_ok=True
            )

        except Exception as exc:

            log(
                "worker.log",
                "error=" + repr(exc)
            )

            approved.unlink(
                missing_ok=True
            )


def worker_thread():

    log(
        "worker.log",
        "root release worker started"
    )

    while True:

        process_release()

        time.sleep(
            2
        )


def main():

    threads = [
        threading.Thread(
            target=registry_thread,
            daemon=True
        ),
        threading.Thread(
            target=broker_thread,
            daemon=True
        ),
        threading.Thread(
            target=review_thread,
            daemon=True
        ),
        threading.Thread(
            target=worker_thread,
            daemon=True
        )
    ]

    for thread in threads:
        thread.start()

    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
PY

chmod 755 /opt/deploy/bin/backend.py

cat > /usr/local/bin/deployctl <<'EOF_CTL'
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

    submit)

        TOKEN="$2"
        FILE="$3"

        printf 'AUTH %s\n' "$TOKEN"
        printf 'SUBMIT %s\n' "$(basename "$FILE")"

        ;;

    *)

        echo "usage:"
        echo "  deployctl status"
        echo "  deployctl help"

        ;;

esac
EOF_CTL

chmod 755 /usr/local/bin/deployctl

cat > /usr/local/bin/releasectl <<'EOF_RELEASE'
#!/bin/sh

SOCK=/run/deploy/review.sock

if [ "$1" != "promote" ]; then
    echo "usage: releasectl promote <job-id>"
    exit 1
fi

printf 'PROMOTE %s\n' "$2" |
socat - UNIX-CONNECT:"$SOCK"
EOF_RELEASE

chmod 755 /usr/local/bin/releasectl

cat > /opt/deploy/registry/northstar-api-1.9.4-legacy.txt <<'EOF_ARTIFACT'
NORTHSTAR LEGACY ARTIFACT
repository=northstar-api
tag=1.9.4-legacy

This artifact was retained for rollback compatibility.

releasebot deployment identity:
see embedded deployment metadata.

PRIVATE_KEY_LOCATION=/home/releasebot/.ssh/id_ed25519
EOF_ARTIFACT

chown root:root \
    /opt/deploy/registry/northstar-api-1.9.4-legacy.txt

chmod 644 \
    /opt/deploy/registry/northstar-api-1.9.4-legacy.txt

cat > /opt/deploy/bin/release-info <<'EOF_INFO'
#!/bin/sh

echo "Northstar Release Manager"
echo "release identity: releasebot"
echo "promotion socket: /run/deploy/review.sock"
echo "release root: /srv/releases/current"
EOF_INFO

chmod 755 /opt/deploy/bin/release-info

python3 \
    /opt/deploy/bin/backend.py \
    >/opt/deploy/logs/backend.stdout \
    2>&1 &

BACKEND_PID=$!

sleep 1

if [ ! -S /run/deploy/broker.sock ]; then
    echo "[Entrypoint] deployment broker failed"
    cat /opt/deploy/logs/backend.stdout 2>/dev/null || true
    exit 1
fi

if [ ! -S /run/deploy/review.sock ]; then
    echo "[Entrypoint] promotion service failed"
    cat /opt/deploy/logs/backend.stdout 2>/dev/null || true
    exit 1
fi

sed -i '/^#*PasswordAuthentication/d' \
    /etc/ssh/sshd_config 2>/dev/null || true

sed -i '/^#*PermitRootLogin/d' \
    /etc/ssh/sshd_config 2>/dev/null || true

sed -i '/^#*KbdInteractiveAuthentication/d' \
    /etc/ssh/sshd_config 2>/dev/null || true

sed -i '/^#*UsePAM/d' \
    /etc/ssh/sshd_config 2>/dev/null || true

sed -i '/^#*AuthenticationMethods/d' \
    /etc/ssh/sshd_config 2>/dev/null || true

sed -i '/^#*PubkeyAuthentication/d' \
    /etc/ssh/sshd_config 2>/dev/null || true

echo "PasswordAuthentication yes" \
    >> /etc/ssh/sshd_config

echo "PermitRootLogin no" \
    >> /etc/ssh/sshd_config

echo "KbdInteractiveAuthentication yes" \
    >> /etc/ssh/sshd_config

echo "UsePAM no" \
    >> /etc/ssh/sshd_config

echo "PubkeyAuthentication yes" \
    >> /etc/ssh/sshd_config

unset SSH_PASSWORD
unset SHELL_PASSWORD
unset PASSWORD
unset USER_PASSWORD

unset SSH_USER
unset SHELL_USER
unset USER_NAME
unset USERNAME
unset USER

unset FLAG
unset CHALLENGE_FLAG
unset DYNAMIC_FLAG

exec /usr/sbin/sshd -D -e
