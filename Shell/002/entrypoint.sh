#!/bin/sh

# 1. Generate SSH host keys dynamically if they do not exist
ssh-keygen -A

# 2. Grab variables injected by k8sWorker.js
USER="${SSH_USER:-${SHELL_USER:-${USER_NAME:-${USERNAME:-${USER:-root}}}}}"
PASS="${SSH_PASSWORD:-${SHELL_PASSWORD:-${PASSWORD:-${USER_PASSWORD:-cyberanzen123}}}}"
FLAG_VAL="${CHALLENGE_FLAG:-${FLAG:-${DYNAMIC_FLAG:-CYBERANZEN{broken_deployment_chain}}}}"

# 3. Prepare challenge filesystem
mkdir -p \
    /opt/broken-deployment/bin \
    /opt/broken-deployment/config \
    /opt/broken-deployment/artifacts \
    /opt/broken-deployment/logs \
    /run/deploy \
    /var/spool/deploy/queue \
    /var/spool/deploy/processed \
    /srv/releases/current \
    /srv/releases/staging

# Root-only flag
printf '%s\n' "$FLAG_VAL" > /root/flag.txt
chmod 400 /root/flag.txt
chown root:root /root/flag.txt

rm -f /flag.txt
rm -f /home/ctf/flag.txt

# 4. Create dynamic user if non-root and set password
echo "[Entrypoint] Configuring account for SSH user: $USER..."

if [ "$USER" != "root" ]; then
    if ! id "$USER" >/dev/null 2>&1; then
        echo "[Entrypoint] User $USER does not exist. Creating user account..."
        adduser -D -s /bin/bash "$USER" 2>/dev/null || \
        useradd -m -s /bin/bash "$USER" 2>/dev/null
    fi

    addgroup "$USER" deployops 2>/dev/null || true
fi

echo "$USER:$PASS" | chpasswd

# Do not give the player the root password
passwd -l root >/dev/null 2>&1 || true

# 5. Deployment broker
cat > /opt/broken-deployment/bin/broker.py <<'PY'
#!/usr/bin/env python3

import json
import os
import socket
import threading
import time

SOCKET_PATH = "/run/deploy/broker.sock"
TOKEN_PATH = "/opt/broken-deployment/config/runner.env"
QUEUE_DIR = "/var/spool/deploy/queue"
LOG_PATH = "/opt/broken-deployment/logs/broker.log"

RUNNER_TOKEN = "RUNNER-7f3d9c2a-88a1-4d12-broken"

os.makedirs(os.path.dirname(SOCKET_PATH), exist_ok=True)
os.makedirs(QUEUE_DIR, exist_ok=True)
os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)

with open(TOKEN_PATH, "w") as f:
    f.write("RUNNER_TOKEN=" + RUNNER_TOKEN + "\n")
    f.write("BROKER_MODE=production\n")
    f.write("DIAGNOSTIC_MODE=legacy\n")

os.chown(TOKEN_PATH, 0, 0)
os.chmod(TOKEN_PATH, 0o640)

def log(message):
    with open(LOG_PATH, "a") as f:
        f.write(
            time.strftime("%Y-%m-%d %H:%M:%S ") +
            message +
            "\n"
        )

def send(conn, obj):
    conn.sendall((json.dumps(obj) + "\n").encode())

def handle(conn):
    try:
        raw = conn.recv(8192).decode(errors="ignore").strip()

        if not raw:
            return

        parts = raw.split(" ", 2)
        command = parts[0].upper()

        if command == "INFO":
            send(conn, {
                "service": "northstar-deployment-broker",
                "version": "2.7.4",
                "socket": SOCKET_PATH,
                "queue": QUEUE_DIR,
                "worker": "northstar-release-worker",
                "diagnostic": "enabled"
            })
            return

        if command == "DIAG":
            try:
                exposed = open(TOKEN_PATH).read().strip()
            except Exception:
                exposed = "unavailable"

            send(conn, {
                "diagnostic": True,
                "runner_config": exposed,
                "finding": "internal service credentials exposed through a diagnostic endpoint"
            })
            return

        if command == "STATUS":
            send(conn, {
                "queue_depth": len(os.listdir(QUEUE_DIR)),
                "worker_user": "root",
                "release_root": "/srv/releases/current"
            })
            return

        if command == "SUBMIT":

            if len(parts) != 3:
                send(conn, {
                    "error": "usage: SUBMIT <token> <artifact>"
                })
                return

            token = parts[1]
            artifact = parts[2]

            if token != RUNNER_TOKEN:
                send(conn, {
                    "error": "invalid runner token"
                })
                return

            if not os.path.isfile(artifact):
                send(conn, {
                    "error": "artifact not found"
                })
                return

            name = os.path.basename(artifact)

            if not name.endswith(".tar.gz"):
                send(conn, {
                    "error": "only .tar.gz artifacts accepted"
                })
                return

            target = os.path.join(QUEUE_DIR, name)

            with open(artifact, "rb") as src:
                with open(target, "wb") as dst:
                    dst.write(src.read())

            os.chmod(target, 0o640)

            meta = target + ".json"

            with open(meta, "w") as f:
                json.dump(
                    {
                        "artifact": target,
                        "submitted_by": "runner",
                        "approved": True
                    },
                    f
                )

            log("accepted artifact " + target)

            send(conn, {
                "accepted": True,
                "artifact": target,
                "approved": True
            })

            return

        send(conn, {
            "error": "unknown command"
        })

    except Exception as exc:

        log("handler error: " + repr(exc))

        try:
            send(conn, {
                "error": "internal broker error"
            })
        except Exception:
            pass

    finally:
        conn.close()

if os.path.exists(SOCKET_PATH):
    os.unlink(SOCKET_PATH)

server = socket.socket(
    socket.AF_UNIX,
    socket.SOCK_STREAM
)

server.bind(SOCKET_PATH)

os.chmod(
    SOCKET_PATH,
    0o660
)

try:
    import grp

    os.chown(
        SOCKET_PATH,
        0,
        grp.getgrnam("deployops").gr_gid
    )
except Exception:
    pass

server.listen(20)

log(
    "broker listening on " +
    SOCKET_PATH
)

while True:
    conn, _ = server.accept()

    threading.Thread(
        target=handle,
        args=(conn,),
        daemon=True
    ).start()
PY

chmod 755 /opt/broken-deployment/bin/broker.py
chown root:root /opt/broken-deployment/bin/broker.py

# 6. Root release worker
cat > /opt/broken-deployment/bin/release-worker.py <<'PY'
#!/usr/bin/env python3

import json
import os
import subprocess
import tarfile
import time

QUEUE = "/var/spool/deploy/queue"
PROCESSED = "/var/spool/deploy/processed"
CURRENT = "/srv/releases/current"
LOG = "/opt/broken-deployment/logs/worker.log"

os.makedirs(QUEUE, exist_ok=True)
os.makedirs(PROCESSED, exist_ok=True)
os.makedirs(CURRENT, exist_ok=True)

def log(message):
    with open(LOG, "a") as f:
        f.write(
            time.strftime("%Y-%m-%d %H:%M:%S ") +
            message +
            "\n"
        )

def run_hook():

    hook = os.path.join(
        CURRENT,
        "hooks",
        "post-install.sh"
    )

    if os.path.isfile(hook) and os.access(hook, os.X_OK):

        log(
            "executing post-install hook"
        )

        subprocess.run(
            [hook],
            cwd=CURRENT,
            check=False
        )

while True:

    try:

        for name in os.listdir(QUEUE):

            if not name.endswith(".tar.gz"):
                continue

            archive = os.path.join(
                QUEUE,
                name
            )

            meta = archive + ".json"

            if not os.path.isfile(meta):
                continue

            try:

                with open(meta) as f:
                    info = json.load(f)

            except Exception:
                continue

            if not info.get("approved"):
                continue

            log(
                "processing " +
                archive
            )

            try:

                # Intentionally unsafe extraction for the challenge.
                with tarfile.open(
                    archive,
                    "r:gz"
                ) as tar:

                    tar.extractall(
                        CURRENT
                    )

                run_hook()

            except Exception as exc:

                log(
                    "release error: " +
                    repr(exc)
                )

            processed_archive = os.path.join(
                PROCESSED,
                name
            )

            processed_meta = (
                processed_archive +
                ".json"
            )

            try:

                os.replace(
                    archive,
                    processed_archive
                )

                os.replace(
                    meta,
                    processed_meta
                )

            except Exception:
                pass

    except Exception as exc:

        log(
            "worker loop error: " +
            repr(exc)
        )

    time.sleep(2)
PY

chmod 755 /opt/broken-deployment/bin/release-worker.py
chown root:root /opt/broken-deployment/bin/release-worker.py

# 7. Deployment client
cat > /opt/broken-deployment/bin/deployctl <<'SH'
#!/bin/sh

SOCK="/run/deploy/broker.sock"

case "${1:-}" in

    info)
        printf 'INFO\n' |
        socat - UNIX-CONNECT:"$SOCK"
        ;;

    diag)
        printf 'DIAG\n' |
        socat - UNIX-CONNECT:"$SOCK"
        ;;

    status)
        printf 'STATUS\n' |
        socat - UNIX-CONNECT:"$SOCK"
        ;;

    submit)
        TOKEN="$2"
        ARTIFACT="$3"

        printf 'SUBMIT %s %s\n' \
            "$TOKEN" \
            "$ARTIFACT" |
        socat - UNIX-CONNECT:"$SOCK"
        ;;

    *)
        echo "usage: deployctl {info|diag|status|submit}"
        exit 1
        ;;

esac
SH

chmod 755 /opt/broken-deployment/bin/deployctl
chown root:root /opt/broken-deployment/bin/deployctl

# 8. Deployment configuration
cat > /opt/broken-deployment/config/release.conf <<'EOF'
SERVICE=northstar-api
RELEASE_ROOT=/srv/releases/current
ARTIFACT_QUEUE=/var/spool/deploy/queue
BROKER_SOCKET=/run/deploy/broker.sock
WORKER=northstar-release-worker
EOF

# 9. Deployment logs
cat > /opt/broken-deployment/logs/deployment.log <<'EOF'
2026-09-28 22:14:11 deployment broker started
2026-09-28 22:14:15 runner connected
2026-09-28 22:14:18 diagnostic request accepted
2026-09-28 22:15:02 release worker waiting for approved artifacts
EOF

# 10. Permissions
chown -R root:root /opt/broken-deployment/bin

chown root:deployops \
    /opt/broken-deployment/config \
    /opt/broken-deployment/logs \
    /opt/broken-deployment/artifacts

chmod 750 \
    /opt/broken-deployment/config

chmod 775 \
    /opt/broken-deployment/logs \
    /opt/broken-deployment/artifacts

# 11. Start deployment broker
python3 \
    /opt/broken-deployment/bin/broker.py \
    >/opt/broken-deployment/logs/broker.stdout \
    2>&1 &

BROKER_PID=$!

# 12. Start privileged release worker
python3 \
    /opt/broken-deployment/bin/release-worker.py \
    >/opt/broken-deployment/logs/worker.stdout \
    2>&1 &

WORKER_PID=$!

printf '%s\n' "$BROKER_PID" \
    > /run/deploy/broker.pid

printf '%s\n' "$WORKER_PID" \
    > /run/deploy/worker.pid

# 13. Wait for the deployment socket
i=0

while [ ! -S /run/deploy/broker.sock ] &&
      [ "$i" -lt 30 ]; do

    sleep 1

    i=$((i + 1))

done

# 14. Ensure SSH allows password login and root login
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

echo "PermitRootLogin yes" \
    >> /etc/ssh/sshd_config

echo "KbdInteractiveAuthentication yes" \
    >> /etc/ssh/sshd_config

echo "UsePAM no" \
    >> /etc/ssh/sshd_config

echo "PubkeyAuthentication yes" \
    >> /etc/ssh/sshd_config

# 15. Unset sensitive environment variables
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

# 16. Start SSH daemon in the foreground
exec /usr/sbin/sshd -D -e