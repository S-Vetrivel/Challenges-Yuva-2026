#!/bin/sh
set -eu

ssh-keygen -A

USER="${SSH_USER:-${SHELL_USER:-${USER_NAME:-${USERNAME:-${USER:-root}}}}}"
PASS="${SSH_PASSWORD:-${SHELL_PASSWORD:-${PASSWORD:-${USER_PASSWORD:-cyberanzen123}}}}"
FLAG_VAL="${CHALLENGE_FLAG:-${FLAG:-${DYNAMIC_FLAG:-CYBERANZEN{broken_deployment_chain}}}}"

if [ "$USER" = "root" ]; then
    USER="ctf"
fi

if ! id "$USER" >/dev/null 2>&1; then
    adduser -D -s /bin/bash "$USER"
fi

echo "$USER:$PASS" | chpasswd

if ! getent group deployops >/dev/null 2>&1; then
    addgroup -S deployops
fi
addgroup "$USER" deployops 2>/dev/null || true

# Do not reuse the player's password for root.
passwd -l root >/dev/null 2>&1 || true

# Protected flag: only root can read it.
printf '%s\n' "$FLAG_VAL" > /root/flag.txt
chmod 400 /root/flag.txt
chown root:root /root/flag.txt

if ! id deploybot >/dev/null 2>&1; then
    adduser -S -H -s /sbin/nologin deploybot
fi

mkdir -p \
    /run/deploy \
    /opt/deploy/bin \
    /opt/deploy/config \
    /opt/deploy/logs \
    /var/lib/deploy/queue \
    /var/lib/deploy/artifacts \
    /var/lib/deploy/incoming \
    /srv/releases/current \
    /srv/releases/staging

chown root:root /opt/deploy /opt/deploy/bin /opt/deploy/config
chown root:deployops /opt/deploy/logs
chown root:deployops /var/lib/deploy/incoming /var/lib/deploy/artifacts
chown root:root /var/lib/deploy/queue /srv/releases /srv/releases/current /srv/releases/staging
chown root:deployops /run/deploy

chmod 755 /opt/deploy /opt/deploy/bin /opt/deploy/config
chmod 770 /opt/deploy/logs
chmod 770 /var/lib/deploy/incoming /var/lib/deploy/artifacts
chmod 750 /var/lib/deploy/queue
chmod 755 /srv/releases /srv/releases/current
chmod 770 /srv/releases/staging /run/deploy

# The deployment runner credential is intentionally exposed to the deployment operator.
cat > /opt/deploy/config/runner.env <<'CFG'
RUNNER_TOKEN=RUNNER_7f31c9a4e2b8
RUNNER_NAME=northstar-runner-01
BROKER_SOCKET=/run/deploy/broker.sock
CFG
chown root:deployops /opt/deploy/config/runner.env
chmod 640 /opt/deploy/config/runner.env

cat > /opt/deploy/bin/deploy-broker.py <<'PY'
#!/usr/bin/env python3
import os
import socket
import threading
import uuid
from pathlib import Path

SOCKET = "/run/deploy/broker.sock"
TOKEN = "RUNNER_7f31c9a4e2b8"
INCOMING = Path("/var/lib/deploy/incoming")
ARTIFACTS = Path("/var/lib/deploy/artifacts")
QUEUE = Path("/var/lib/deploy/queue")
LOG = Path("/opt/deploy/logs/broker.log")

for p in (INCOMING, ARTIFACTS, QUEUE):
    p.mkdir(parents=True, exist_ok=True)
Path("/run/deploy").mkdir(parents=True, exist_ok=True)

try:
    os.unlink(SOCKET)
except FileNotFoundError:
    pass

def log(message):
    with LOG.open("a") as f:
        f.write(message + "\n")

def send(conn, message):
    conn.sendall((message + "\n").encode())

def handle(conn):
    authenticated = False
    send(conn, "NORTHSTAR DEPLOYMENT BROKER v2")
    send(conn, "Commands: AUTH STATUS SUBMIT APPROVE HELP")
    try:
        while True:
            raw = conn.recv(4096)
            if not raw:
                return
            line = raw.decode(errors="replace").strip()
            if not line:
                continue
            bits = line.split(" ", 1)
            command = bits[0].upper()
            argument = bits[1].strip() if len(bits) == 2 else ""

            if command == "HELP":
                send(conn, "AUTH <token> | STATUS | SUBMIT <artifact-name> | APPROVE <job-id>")
                continue

            if command == "AUTH":
                authenticated = argument == TOKEN
                send(conn, "AUTH OK" if authenticated else "AUTH FAILED")
                continue

            if command == "STATUS":
                send(conn, "runner=northstar-runner-01 state=healthy queue=ready")
                continue

            if command == "SUBMIT":
                if not authenticated:
                    send(conn, "ERR authentication required")
                    continue
                name = os.path.basename(argument)
                if not name or name in (".", ".."):
                    send(conn, "ERR artifact required")
                    continue
                source = INCOMING / name
                if not source.is_file():
                    send(conn, "ERR artifact not found in incoming")
                    continue
                job_id = uuid.uuid4().hex[:12]
                target = ARTIFACTS / (job_id + ".tar")
                target.write_bytes(source.read_bytes())
                (QUEUE / (job_id + ".pending")).write_text(target.name + "\n")
                log(f"submitted job={job_id} artifact={target.name}")
                send(conn, f"SUBMITTED {job_id}")
                continue

            if command == "APPROVE":
                if not authenticated:
                    send(conn, "ERR authentication required")
                    continue
                job_id = argument.split()[0] if argument else ""
                pending = QUEUE / (job_id + ".pending")
                if not pending.exists():
                    send(conn, "ERR job not found")
                    continue
                pending.rename(QUEUE / (job_id + ".approved"))
                log(f"approved job={job_id}")
                send(conn, f"APPROVED {job_id}")
                continue

            send(conn, "ERR unknown command")
    finally:
        conn.close()

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(SOCKET)
os.chmod(SOCKET, 0o660)
server.listen(20)
log("broker started")

while True:
    connection, _ = server.accept()
    threading.Thread(target=handle, args=(connection,), daemon=True).start()
PY
chmod 750 /opt/deploy/bin/deploy-broker.py

cat > /opt/deploy/bin/release-worker.py <<'PY'
#!/usr/bin/env python3
import os
import tarfile
import time
from pathlib import Path

QUEUE = Path("/var/lib/deploy/queue")
ARTIFACTS = Path("/var/lib/deploy/artifacts")
RELEASE = Path("/srv/releases/current")
LOG = Path("/opt/deploy/logs/worker.log")


def log(message):
    with LOG.open("a") as f:
        f.write(message + "\n")


def process(job_file):
    job_id = job_file.name.split(".")[0]
    artifact_name = job_file.read_text().strip()
    artifact = ARTIFACTS / artifact_name

    if not artifact.is_file():
        log(f"job={job_id} missing artifact={artifact_name}")
        job_file.unlink(missing_ok=True)
        return

    # Intentional vulnerability:
    # the root release worker trusts archive contents and extracts them without
    # validating member paths or symlink targets.
    with tarfile.open(artifact, "r:*") as archive:
        archive.extractall(RELEASE)

    hook = RELEASE / "hooks" / "post-install.sh"
    if hook.is_file():
        os.chmod(hook, 0o755)
        os.system(str(hook))

    log(f"deployed job={job_id}")
    job_file.unlink(missing_ok=True)
    artifact.unlink(missing_ok=True)


while True:
    for approved in sorted(QUEUE.glob("*.approved")):
        try:
            process(approved)
        except Exception as exc:
            log(f"job={approved.name} failed={exc}")
            approved.unlink(missing_ok=True)
    time.sleep(1)
PY
chmod 750 /opt/deploy/bin/release-worker.py

cat > /usr/local/bin/deployctl <<'SH'
#!/bin/sh
set -eu

SOCK=/run/deploy/broker.sock
INCOMING=/var/lib/deploy/incoming

case "${1:-}" in
  status)
    printf 'STATUS\n' | socat - UNIX-CONNECT:"$SOCK"
    ;;
  help)
    printf 'HELP\n' | socat - UNIX-CONNECT:"$SOCK"
    ;;
  submit)
    [ $# -eq 2 ] || { echo "usage: deployctl submit <artifact.tar>"; exit 1; }
    [ -f "$2" ] || { echo "artifact not found"; exit 1; }
    base=$(basename -- "$2")
    cp -- "$2" "$INCOMING/$base"
    . /opt/deploy/config/runner.env
    {
      printf 'AUTH %s\n' "$RUNNER_TOKEN"
      printf 'SUBMIT %s\n' "$base"
    } | socat - UNIX-CONNECT:"$SOCK"
    ;;
  approve)
    [ $# -eq 2 ] || { echo "usage: deployctl approve <job-id>"; exit 1; }
    . /opt/deploy/config/runner.env
    {
      printf 'AUTH %s\n' "$RUNNER_TOKEN"
      printf 'APPROVE %s\n' "$2"
    } | socat - UNIX-CONNECT:"$SOCK"
    ;;
  *)
    echo "usage: deployctl {status|help|submit|approve}"
    exit 1
    ;;
esac
SH
chmod 755 /usr/local/bin/deployctl

# Seed a legitimate release so enumeration has something meaningful to inspect.
rm -rf /tmp/seed-release
mkdir -p /tmp/seed-release/hooks
cat > /tmp/seed-release/hooks/post-install.sh <<'SH'
#!/bin/sh
echo "northstar release baseline" >> /opt/deploy/logs/worker.log
SH
chmod 755 /tmp/seed-release/hooks/post-install.sh
tar -cf /var/lib/deploy/incoming/baseline.tar -C /tmp/seed-release .
rm -rf /tmp/seed-release

rm -f /run/deploy/broker.sock

# SSH settings matching the working Doom shell pattern.
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

# Start backend services, then keep sshd in the foreground so the container stays alive.
python3 /opt/deploy/bin/deploy-broker.py >/opt/deploy/logs/broker.stdout 2>&1 &
BROKER_PID=$!
sleep 0.3
chown root:deployops /run/deploy/broker.sock
chmod 660 /run/deploy/broker.sock

python3 /opt/deploy/bin/release-worker.py >/opt/deploy/logs/worker.stdout 2>&1 &
WORKER_PID=$!

cleanup() {
    kill "$WORKER_PID" "$BROKER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

unset SSH_PASSWORD SHELL_PASSWORD PASSWORD USER_PASSWORD
unset SSH_USER SHELL_USER USER_NAME USERNAME
unset FLAG CHALLENGE_FLAG DYNAMIC_FLAG

exec /usr/sbin/sshd -D -e
