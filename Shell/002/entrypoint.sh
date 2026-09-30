#!/bin/sh
set -eu

# 1. Generate SSH host keys dynamically if they do not exist
ssh-keygen -A

# 2. Grab variables injected by k8sWorker.js
USER="${SSH_USER:-${SHELL_USER:-${USER_NAME:-${USERNAME:-${USER:-root}}}}}"
PASS="${SSH_PASSWORD:-${SHELL_PASSWORD:-${PASSWORD:-${USER_PASSWORD:-cyberanzen123}}}}"
FLAG_VAL="${CHALLENGE_FLAG:-${FLAG:-${DYNAMIC_FLAG:-NECROX{broken_deployment_chain}}}}"

# Doom shell connections should always be non-root by default.
if [ "$USER" = "root" ]; then
    USER="ctf"
fi

# 3. Base groups and accounts
if ! getent group deployops >/dev/null 2>&1; then
    addgroup -S deployops
fi

if ! getent group releaseops >/dev/null 2>&1; then
    addgroup -S releaseops
fi

if ! id "$USER" >/dev/null 2>&1; then
    echo "[Entrypoint] Creating SSH user: $USER"
    adduser -D -s /bin/bash "$USER"
fi

echo "$USER:$PASS" | chpasswd
addgroup "$USER" deployops 2>/dev/null || true

if ! id releasebot >/dev/null 2>&1; then
    adduser -D -s /bin/bash releasebot
fi

if ! id buildbot >/dev/null 2>&1; then
    adduser -S -H -s /sbin/nologin buildbot
fi

addgroup releasebot releaseops 2>/dev/null || true

# Keep root and the internal release identity unreachable through password auth.
passwd -l root >/dev/null 2>&1 || true
passwd -l releasebot >/dev/null 2>&1 || true

# 4. Never expose the real flag through common shell locations.
rm -f /flag.txt 2>/dev/null || true
rm -f "/home/$USER/flag.txt" 2>/dev/null || true

printf '%s\n' "$FLAG_VAL" > /root/flag.txt
chmod 400 /root/flag.txt
chown root:root /root/flag.txt

# Deliberate decoys prevent trivial flag-file solves.
printf '%s\n' 'NECROX{not_the_real_flag}' > /flag.txt
chmod 444 /flag.txt

mkdir -p "/home/$USER"
printf '%s\n' 'NECROX{decoy_broken_deployment}' > "/home/$USER/flag.txt"
chmod 444 "/home/$USER/flag.txt"
chown "$USER:$USER" "/home/$USER/flag.txt" 2>/dev/null || true

# 5. Directory layout
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

chown root:root /opt/deploy /opt/deploy/bin /opt/deploy/config /opt/deploy/registry
chown root:deployops /opt/deploy/logs /var/lib/deploy/incoming /var/lib/deploy/artifacts
chown root:root /var/lib/deploy/queue /srv/releases /srv/releases/current /srv/releases/staging
chown root:deployops /run/deploy

chmod 755 /opt/deploy /opt/deploy/config
chmod 700 /opt/deploy/bin /opt/deploy/registry
chmod 770 /opt/deploy/logs /var/lib/deploy/incoming /var/lib/deploy/artifacts
chmod 750 /var/lib/deploy/queue
chmod 755 /srv/releases /srv/releases/current
chmod 770 /srv/releases/staging /run/deploy

# 6. First trust boundary: runner credential readable by deploy operators.
cat > /opt/deploy/config/runner.env <<'CFG'
RUNNER_TOKEN=RUNNER_7f31c9a4e2b8
RUNNER_NAME=northstar-runner-01
BROKER_SOCKET=/run/deploy/broker.sock
REGISTRY_URL=http://127.0.0.1:18080
CFG

chown root:deployops /opt/deploy/config/runner.env
chmod 640 /opt/deploy/config/runner.env

# 7. Second trust boundary: legacy runner diagnostic logging leaks a registry token.
cat > /opt/deploy/logs/runner-debug.log <<'EOFLOG'
2026-09-29T21:33:08Z runner=northstar-runner-01 mode=production
2026-09-29T21:33:09Z registry_url=http://127.0.0.1:18080
2026-09-29T21:33:09Z registry_auth=Bearer REGISTRY_2c48d0aa8f71e6c4
2026-09-29T21:33:10Z warning=legacy-debug-enabled
2026-09-29T21:33:12Z note=remove debug logging after migration
EOFLOG

chown root:deployops /opt/deploy/logs/runner-debug.log
chmod 640 /opt/deploy/logs/runner-debug.log

# 8. Build the releasebot SSH identity.
mkdir -p /home/releasebot/.ssh
chmod 700 /home/releasebot/.ssh
chown -R releasebot:releasebot /home/releasebot/.ssh

if [ ! -f /home/releasebot/.ssh/id_ed25519 ]; then
    ssh-keygen -q -t ed25519 -N '' -f /home/releasebot/.ssh/id_ed25519
fi

cat /home/releasebot/.ssh/id_ed25519.pub > /home/releasebot/.ssh/authorized_keys
chmod 600 /home/releasebot/.ssh/authorized_keys /home/releasebot/.ssh/id_ed25519
chmod 644 /home/releasebot/.ssh/id_ed25519.pub
chown -R releasebot:releasebot /home/releasebot/.ssh

# 9. Local artifact registry.
cat > /opt/deploy/bin/registry.py <<'PYBLOCK'
#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

TOKEN = "REGISTRY_2c48d0aa8f71e6c4"
ROOT = Path("/opt/deploy/registry")

class Handler(BaseHTTPRequestHandler):
    server_version = "NorthstarRegistry/1.3"

    def log_message(self, fmt, *args):
        with open("/opt/deploy/logs/registry.log", "a") as f:
            f.write((fmt % args) + "\n")

    def authorized(self):
        return self.headers.get("Authorization", "") == "Bearer " + TOKEN

    def send_json(self, status, obj):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self.authorized():
            self.send_json(401, {"error": "registry authentication required"})
            return

        if self.path == "/v1/catalog":
            self.send_json(200, {
                "name": "northstar-internal",
                "repositories": ["northstar-api", "northstar-worker"],
                "tags": {
                    "northstar-api": ["1.8.1", "1.9.2", "1.9.4-legacy"],
                    "northstar-worker": ["3.2.0"]
                }
            })
            return

        prefix = "/v1/blob/"
        if self.path.startswith(prefix):
            name = self.path[len(prefix):]
            target = ROOT / name
            if "/" in name or not target.is_file():
                self.send_json(404, {"error": "artifact not found"})
                return

            data = target.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        self.send_json(404, {"error": "not found"})

HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
PYBLOCK
chmod 700 /opt/deploy/bin/registry.py

# 10. Deployment broker. deployops can submit artifacts but cannot promote them.
cat > /opt/deploy/bin/deploy-broker.py <<'PYBLOCK'
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
    send(conn, "NORTHSTAR DEPLOYMENT BROKER v3")
    send(conn, "Commands: AUTH STATUS SUBMIT HELP")

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
                send(conn, "AUTH <token> | STATUS | SUBMIT <artifact-name>")
                continue

            if command == "AUTH":
                authenticated = argument == TOKEN
                send(conn, "AUTH OK" if authenticated else "AUTH FAILED")
                continue

            if command == "STATUS":
                send(conn, "runner=northstar-runner-01 state=healthy queue=promotion-gated")
                continue

            if command == "SUBMIT":
                if not authenticated:
                    send(conn, "ERR authentication required")
                    continue

                name = os.path.basename(argument)
                if not name.endswith(".tar.gz"):
                    send(conn, "ERR only .tar.gz artifacts accepted")
                    continue

                source = INCOMING / name
                if not source.is_file():
                    send(conn, "ERR artifact not found in incoming")
                    continue

                job_id = uuid.uuid4().hex[:12]
                target = ARTIFACTS / (job_id + ".tar.gz")
                target.write_bytes(source.read_bytes())
                (QUEUE / (job_id + ".pending")).write_text(target.name + "\n")
                source.unlink(missing_ok=True)

                log(f"submitted job={job_id} artifact={target.name}")
                send(conn, f"SUBMITTED {job_id}")
                continue

            send(conn, "ERR unknown command")
    finally:
        conn.close()

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(SOCKET)
os.chmod(SOCKET, 0o660)
try:
    import grp
    os.chown(SOCKET, 0, grp.getgrnam("deployops").gr_gid)
except Exception:
    pass

server.listen(20)
log("broker started")

while True:
    connection, _ = server.accept()
    threading.Thread(target=handle, args=(connection,), daemon=True).start()
PYBLOCK
chmod 700 /opt/deploy/bin/deploy-broker.py

# 11. Privileged promotion daemon. Only releasebot can access this socket.
cat > /opt/deploy/bin/promotiond.py <<'PYBLOCK'
#!/usr/bin/env python3
import os
import pwd
import socket
import struct
from pathlib import Path

SOCKET = "/run/deploy/review.sock"
QUEUE = Path("/var/lib/deploy/queue")
LOG = Path("/opt/deploy/logs/promotion.log")
RELEASEBOT_UID = pwd.getpwnam("releasebot").pw_uid

try:
    os.unlink(SOCKET)
except FileNotFoundError:
    pass

def log(message):
    with LOG.open("a") as f:
        f.write(message + "\n")

def peer_uid(conn):
    data = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
    _, uid, _ = struct.unpack("3i", data)
    return uid

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(SOCKET)
os.chmod(SOCKET, 0o660)

try:
    import grp
    os.chown(SOCKET, 0, grp.getgrnam("releaseops").gr_gid)
except Exception:
    pass

server.listen(10)

while True:
    conn, _ = server.accept()
    try:
        uid = peer_uid(conn)
        request = conn.recv(4096).decode(errors="replace").strip()

        if uid != RELEASEBOT_UID:
            conn.sendall(b"ERR promotion access denied\n")
            continue

        bits = request.split()
        if len(bits) != 2 or bits[0].upper() != "PROMOTE":
            conn.sendall(b"ERR usage: PROMOTE <job-id>\n")
            continue

        job_id = bits[1]
        pending = QUEUE / (job_id + ".pending")
        approved = QUEUE / (job_id + ".approved")

        if not pending.is_file():
            conn.sendall(b"ERR pending job not found\n")
            continue

        pending.rename(approved)
        log(f"promoted job={job_id} uid={uid}")
        conn.sendall(("PROMOTED " + job_id + "\n").encode())
    finally:
        conn.close()
PYBLOCK
chmod 700 /opt/deploy/bin/promotiond.py

# 12. Root release worker. The archive trust boundary is deliberately broken.
cat > /opt/deploy/bin/release-worker.py <<'PYBLOCK'
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

def run_hook():
    hook = RELEASE / "hooks" / "post-install.sh"
    if hook.is_file():
        os.chmod(hook, 0o755)
        os.system(str(hook))

def process(job_file):
    job_id = job_file.name.split(".")[0]
    artifact_name = job_file.read_text().strip()
    artifact = ARTIFACTS / artifact_name

    if not artifact.is_file():
        log(f"job={job_id} missing artifact={artifact_name}")
        job_file.unlink(missing_ok=True)
        return

    # Intentional deployment vulnerability:
    # archive member paths and symlink targets are trusted by the root worker.
    with tarfile.open(artifact, "r:gz") as archive:
        archive.extractall(RELEASE)

    run_hook()
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
PYBLOCK
chmod 700 /opt/deploy/bin/release-worker.py

# 13. Player-side control for submission only.
cat > /usr/local/bin/deployctl <<'SHBLOCK'
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
    [ $# -eq 2 ] || { echo "usage: deployctl submit <artifact.tar.gz>"; exit 1; }
    [ -f "$2" ] || { echo "artifact not found"; exit 1; }

    base=$(basename -- "$2")
    case "$base" in
      *.tar.gz) ;;
      *) echo "artifact must end with .tar.gz"; exit 1 ;;
    esac

    cp -- "$2" "$INCOMING/$base"

    . /opt/deploy/config/runner.env

    {
      printf 'AUTH %s\n' "$RUNNER_TOKEN"
      printf 'SUBMIT %s\n' "$base"
    } | socat - UNIX-CONNECT:"$SOCK"
    ;;
  *)
    echo "usage: deployctl {status|help|submit}"
    exit 1
    ;;
esac
SHBLOCK
chmod 755 /usr/local/bin/deployctl

# 14. releasebot-only promotion helper.
cat > /usr/local/bin/releasectl <<'SHBLOCK'
#!/bin/sh
set -eu

SOCK=/run/deploy/review.sock

case "${1:-}" in
  promote)
    [ $# -eq 2 ] || { echo "usage: releasectl promote <job-id>"; exit 1; }
    printf 'PROMOTE %s\n' "$2" | socat - UNIX-CONNECT:"$SOCK"
    ;;
  *)
    echo "usage: releasectl promote <job-id>"
    exit 1
    ;;
esac
SHBLOCK
chown root:releaseops /usr/local/bin/releasectl
chmod 750 /usr/local/bin/releasectl

# 15. Seed an intentionally interesting legacy artifact in the registry.
rm -rf /tmp/legacy-release
mkdir -p /tmp/legacy-release/metadata /tmp/legacy-release/keys

printf '%s\n' 'northstar-api legacy build 1.9.4' \
    > /tmp/legacy-release/metadata/BUILD.txt

printf '%s\n' 'releasebot deployment identity retained for rollback compatibility' \
    > /tmp/legacy-release/metadata/NOTE.txt

cp /home/releasebot/.ssh/id_ed25519 \
    /tmp/legacy-release/keys/releasebot_id_ed25519

chmod 600 /tmp/legacy-release/keys/releasebot_id_ed25519

tar -czf /opt/deploy/registry/northstar-api_1.9.4-legacy.tar.gz \
    -C /tmp/legacy-release .

rm -rf /tmp/legacy-release

# 16. Baseline release structure.
mkdir -p /srv/releases/current/hooks

cat > /srv/releases/current/hooks/post-install.sh <<'SHBLOCK'
#!/bin/sh
echo "baseline northstar release" >> /opt/deploy/logs/worker.log
SHBLOCK

chmod 755 /srv/releases/current/hooks/post-install.sh

# 17. Files that guide enumeration without directly giving the solution.
cat > /opt/deploy/logs/worker.log <<'EOFLOG'
2026-09-28T18:11:02Z worker started uid=0
2026-09-28T18:11:09Z promotion policy=releasebot-only
2026-09-28T18:11:11Z release hooks enabled
EOFLOG

cat > /opt/deploy/config/release-policy.txt <<'EOFCONF'
Northstar deployment policy

1. Artifact submission is handled by the deployment broker.
2. Promotion is intentionally separated from submission.
3. Legacy releasebot retains promotion authority during the migration.
4. Release hooks are executed by the privileged worker after promotion.
EOFCONF

chmod 640 /opt/deploy/config/release-policy.txt
chown root:deployops /opt/deploy/config/release-policy.txt

# 18. Start backend services.
python3 /opt/deploy/bin/registry.py \
    >/opt/deploy/logs/registry.stdout \
    2>&1 &
REGISTRY_PID=$!

python3 /opt/deploy/bin/deploy-broker.py \
    >/opt/deploy/logs/broker.stdout \
    2>&1 &
BROKER_PID=$!

python3 /opt/deploy/bin/promotiond.py \
    >/opt/deploy/logs/promotion.stdout \
    2>&1 &
PROMOTION_PID=$!

python3 /opt/deploy/bin/release-worker.py \
    >/opt/deploy/logs/worker.stdout \
    2>&1 &
WORKER_PID=$!

sleep 1

# 19. Ensure socket ownership after startup.
if [ -S /run/deploy/broker.sock ]; then
    chown root:deployops /run/deploy/broker.sock
    chmod 660 /run/deploy/broker.sock
fi

if [ -S /run/deploy/review.sock ]; then
    chown root:releaseops /run/deploy/review.sock
    chmod 660 /run/deploy/review.sock
fi

# 20. SSH settings matching the working Doom shell template.
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

# 21. Remove deployment secrets from the environment before SSH starts.
unset SSH_PASSWORD SHELL_PASSWORD PASSWORD USER_PASSWORD
unset SSH_USER SHELL_USER USER_NAME USERNAME USER
unset FLAG CHALLENGE_FLAG DYNAMIC_FLAG

# 22. Keep SSHD in the foreground exactly like the Doom shell template.
exec /usr/sbin/sshd -D -e
