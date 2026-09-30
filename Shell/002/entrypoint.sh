#!/bin/sh
set -eu

ssh-keygen -A

USER="${SSH_USER:-${SHELL_USER:-${USER_NAME:-${USERNAME:-${USER:-ctf}}}}}"
PASS="${SSH_PASSWORD:-${SHELL_PASSWORD:-${PASSWORD:-${USER_PASSWORD:-cyberanzen123}}}}"
FLAG_VAL="${CHALLENGE_FLAG:-${FLAG:-${DYNAMIC_FLAG:-CYBERANZEN{broken_deployment}}}}"

if [ "$USER" = "root" ]; then
    USER=ctf
fi

if ! id "$USER" >/dev/null 2>&1; then
    adduser -D -s /bin/bash "$USER"
fi

addgroup "$USER" deploy 2>/dev/null || true
addgroup "$USER" sshusers 2>/dev/null || true
echo "$USER:$PASS" | chpasswd
passwd -l root >/dev/null 2>&1 || true

printf '%s\n' "$FLAG_VAL" > /root/flag.txt
chmod 400 /root/flag.txt
chown root:root /root/flag.txt

cat > /etc/northstar/deployer.env <<'ENV'
BROKER_SOCKET=/run/northstar/deployer.sock
RUNNER_TOKEN=ns_runner_4f1d6c8e93a72b51
RELEASE_ROOT=/srv/releases/incoming
STAGING_ROOT=/srv/releases/staging
LIVE_ROOT=/srv/releases/live
ENV
chmod 640 /etc/northstar/deployer.env
chown root:deploy /etc/northstar/deployer.env

cat > /etc/northstar/hooks/post_deploy.sh <<'HOOK'
#!/bin/sh
set -eu
release_dir="${1:-/srv/releases/live}"
printf '%s %s\n' "$(date -u +%FT%TZ)" "$release_dir" >> /var/lib/northstar/deploy.log
HOOK
chmod 750 /etc/northstar/hooks/post_deploy.sh
chown root:root /etc/northstar/hooks/post_deploy.sh

cat > /opt/northstar/runtime/deployer.py <<'PY'
#!/usr/bin/env python3
import json
import grp
import os
import socket
import threading
import time

SOCKET = "/run/northstar/deployer.sock"
ENV = "/etc/northstar/deployer.env"
QUEUE = "/var/lib/northstar/jobs"
INCOMING = "/srv/releases/incoming"
STAGING = "/srv/releases/staging"
LIVE = "/srv/releases/live"
TOKEN = ""

with open(ENV, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line.startswith("RUNNER_TOKEN="):
            TOKEN = line.split("=", 1)[1]

def reply(conn, obj):
    conn.sendall((json.dumps(obj) + "\n").encode())

def handle(conn):
    try:
        raw = conn.recv(65535)
        if not raw:
            return
        req = json.loads(raw.decode())
        action = req.get("action")

        if action == "status":
            reply(conn, {
                "service": "northstar-deployer",
                "socket": SOCKET,
                "incoming": INCOMING,
                "staging": STAGING,
                "live": LIVE,
                "queue_depth": len([x for x in os.listdir(QUEUE) if x.endswith('.json')])
            })
            return

        if action == "list_artifacts":
            files = []
            for name in sorted(os.listdir(INCOMING)):
                path = os.path.join(INCOMING, name)
                if os.path.isfile(path):
                    files.append(name)
            reply(conn, {"artifacts": files})
            return

        if action == "approve":
            if req.get("token") != TOKEN:
                reply(conn, {"ok": False, "error": "runner authentication failed"})
                return
            artifact = req.get("artifact", "")
            path = os.path.join(INCOMING, artifact)
            if not artifact or os.path.basename(artifact) != artifact or not os.path.isfile(path):
                reply(conn, {"ok": False, "error": "invalid artifact"})
                return
            marker = path + ".approved"
            with open(marker, "w", encoding="utf-8") as f:
                f.write(str(int(time.time())))
            os.chown(marker, 0, grp.getgrnam("deploy").gr_gid)
            os.chmod(marker, 0o640)
            reply(conn, {"ok": True, "approved": artifact})
            return

        if action == "deploy":
            if req.get("token") != TOKEN:
                reply(conn, {"ok": False, "error": "runner authentication failed"})
                return
            artifact = req.get("artifact", "")
            path = os.path.join(INCOMING, artifact)
            marker = path + ".approved"
            if not artifact or os.path.basename(artifact) != artifact:
                reply(conn, {"ok": False, "error": "invalid artifact"})
                return
            if not os.path.isfile(path) or not os.path.isfile(marker):
                reply(conn, {"ok": False, "error": "artifact not approved"})
                return
            job_id = f"job-{int(time.time())}-{os.getpid()}"
            job_path = os.path.join(QUEUE, job_id + ".json")
            job = {"id": job_id, "artifact": artifact, "created": time.time()}
            with open(job_path, "w", encoding="utf-8") as f:
                json.dump(job, f)
            os.chown(job_path, 0, grp.getgrnam("deploy").gr_gid)
            os.chmod(job_path, 0o640)
            reply(conn, {"ok": True, "queued": job_id})
            return

        if action == "job":
            job_id = req.get("id", "")
            if not job_id or os.path.basename(job_id) != job_id:
                reply(conn, {"ok": False, "error": "invalid job"})
                return
            path = os.path.join(QUEUE, job_id + ".json")
            if not os.path.isfile(path):
                reply(conn, {"ok": False, "error": "not found"})
                return
            with open(path, "r", encoding="utf-8") as f:
                reply(conn, {"ok": True, "job": json.load(f)})
            return

        reply(conn, {"ok": False, "error": "unknown action"})
    except Exception as exc:
        try:
            reply(conn, {"ok": False, "error": str(exc)})
        except Exception:
            pass
    finally:
        conn.close()

def main():
    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCKET)
    os.chown(SOCKET, 0, grp.getgrnam("deploy").gr_gid)
    os.chmod(SOCKET, 0o660)
    srv.listen(32)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()

if __name__ == "__main__":
    main()
PY
chmod 750 /opt/northstar/runtime/deployer.py
chown root:root /opt/northstar/runtime/deployer.py

cat > /opt/northstar/runtime/worker.py <<'PY'
#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import tarfile
import time

QUEUE = "/var/lib/northstar/jobs"
INCOMING = "/srv/releases/incoming"
STAGING = "/srv/releases/staging"
LIVE = "/srv/releases/live"
HOOK = "/etc/northstar/hooks/post_deploy.sh"


def process(job_file):
    with open(job_file, "r", encoding="utf-8") as f:
        job = json.load(f)

    artifact = job["artifact"]
    src = os.path.join(INCOMING, artifact)
    stage = os.path.join(STAGING, job["id"])

    if not os.path.isfile(src):
        raise RuntimeError("artifact disappeared")

    os.makedirs(stage, exist_ok=True)

    with tarfile.open(src, "r:gz") as archive:
        archive.extractall(stage)

    for name in os.listdir(LIVE):
        path = os.path.join(LIVE, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    for name in os.listdir(stage):
        shutil.move(os.path.join(stage, name), os.path.join(LIVE, name))

    subprocess.run(["/bin/sh", HOOK, LIVE], check=False)

    os.unlink(job_file)
    try:
        os.unlink(src + ".approved")
    except FileNotFoundError:
        pass


def main():
    while True:
        files = sorted(
            os.path.join(QUEUE, name)
            for name in os.listdir(QUEUE)
            if name.endswith(".json")
        )
        for job_file in files:
            try:
                process(job_file)
            except Exception as exc:
                with open("/var/lib/northstar/worker-errors.log", "a", encoding="utf-8") as f:
                    f.write(f"{time.time()} {job_file} {exc}\n")
                try:
                    os.unlink(job_file)
                except FileNotFoundError:
                    pass
        time.sleep(1)

if __name__ == "__main__":
    main()
PY
chmod 750 /opt/northstar/runtime/worker.py
chown root:root /opt/northstar/runtime/worker.py

cat > /opt/northstar/bin/deployctl <<'CTL'
#!/usr/bin/env python3
import json
import socket
import sys

SOCKET = "/run/northstar/deployer.sock"
ENV = "/etc/northstar/deployer.env"

def token():
    with open(ENV, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("RUNNER_TOKEN="):
                return line.strip().split("=", 1)[1]
    return ""

def call(payload):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCKET)
    s.sendall((json.dumps(payload) + "\n").encode())
    data = s.recv(65535)
    s.close()
    print(data.decode().strip())

if len(sys.argv) < 2:
    print("usage: deployctl status | artifacts | approve <artifact> | deploy <artifact> | job <id>")
    raise SystemExit(1)

cmd = sys.argv[1]
if cmd == "status":
    call({"action": "status"})
elif cmd == "artifacts":
    call({"action": "list_artifacts"})
elif cmd == "approve" and len(sys.argv) == 3:
    call({"action": "approve", "artifact": sys.argv[2], "token": token()})
elif cmd == "deploy" and len(sys.argv) == 3:
    call({"action": "deploy", "artifact": sys.argv[2], "token": token()})
elif cmd == "job" and len(sys.argv) == 3:
    call({"action": "job", "id": sys.argv[2]})
else:
    print("usage: deployctl status | artifacts | approve <artifact> | deploy <artifact> | job <id>")
    raise SystemExit(1)
CTL
chmod 750 /opt/northstar/bin/deployctl
chown root:deploy /opt/northstar/bin/deployctl

cat > /opt/northstar/runtime/bootstrap-release.py <<'PY'
import gzip
import io
import tarfile

out = "/srv/releases/incoming/nightly-release.tar.gz"
content = b"northstar production release\n"
info = tarfile.TarInfo("README.txt")
info.size = len(content)
with tarfile.open(out, "w:gz") as archive:
    archive.addfile(info, io.BytesIO(content))
PY
python3 /opt/northstar/runtime/bootstrap-release.py
rm -f /opt/northstar/runtime/bootstrap-release.py
chown root:deploy /srv/releases/incoming/nightly-release.tar.gz
chmod 640 /srv/releases/incoming/nightly-release.tar.gz

printf '%s\n' 'release-history: 2026-09-29' 'runner: northstar-ci' > /var/lib/northstar/release-history.log
chown root:deploy /var/lib/northstar/release-history.log
chmod 640 /var/lib/northstar/release-history.log

printf '%s\n' 'current-release=northstar-2026.09.29' > /srv/releases/live/VERSION
chown root:root /srv/releases/live/VERSION
chmod 644 /srv/releases/live/VERSION

python3 /opt/northstar/runtime/deployer.py >/var/lib/northstar/deployer.log 2>&1 &
python3 /opt/northstar/runtime/worker.py >/var/lib/northstar/worker.log 2>&1 &

unset SSH_PASSWORD SHELL_PASSWORD PASSWORD USER_PASSWORD
unset SSH_USER SHELL_USER USER_NAME USERNAME USER
unset FLAG CHALLENGE_FLAG DYNAMIC_FLAG

exec /usr/sbin/sshd -D -e
