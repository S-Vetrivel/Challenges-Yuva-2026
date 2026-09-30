#!/bin/sh

set -eu

ssh-keygen -A

USER="${SSH_USER:-${SHELL_USER:-${USER_NAME:-${USERNAME:-${USER:-root}}}}}"
PASS="${SSH_PASSWORD:-${SHELL_PASSWORD:-${PASSWORD:-${USER_PASSWORD:-cyberanzen123}}}}"
FLAG_VAL="${CHALLENGE_FLAG:-${FLAG:-${DYNAMIC_FLAG:-CYBERANZEN{websocket_phantom}}}}"

if [ "$USER" = "root" ]; then
    USER="ctf"
fi

echo "[Entrypoint] Configuring account for SSH user: $USER..."

if ! id "$USER" >/dev/null 2>&1; then
    echo "[Entrypoint] User $USER does not exist. Creating user account..."
    adduser -D -s /bin/bash "$USER" 2>/dev/null || \
    useradd -m -s /bin/bash "$USER" 2>/dev/null
fi

echo "$USER:$PASS" | chpasswd

mkdir -p \
    /opt/wsocket/bin \
    /opt/wsocket/config \
    /opt/wsocket/logs \
    /opt/wsocket/data/public \
    /opt/wsocket/data/cache \
    /run/wsocket

chown root:root \
    /opt/wsocket \
    /opt/wsocket/bin \
    /opt/wsocket/config \
    /opt/wsocket/logs \
    /opt/wsocket/data \
    /opt/wsocket/data/public \
    /opt/wsocket/data/cache

chmod 755 \
    /opt/wsocket \
    /opt/wsocket/bin \
    /opt/wsocket/config \
    /opt/wsocket/logs \
    /opt/wsocket/data \
    /opt/wsocket/data/public \
    /opt/wsocket/data/cache

printf '%s\n' "$FLAG_VAL" > /root/flag.txt
chmod 400 /root/flag.txt
chown root:root /root/flag.txt

printf '%s\n' 'CYBERANZEN{websocket_public_decoy}' > /flag.txt
chmod 444 /flag.txt

printf '%s\n' 'CYBERANZEN{websocket_shell_decoy}' > "/home/$USER/flag.txt"
chmod 444 "/home/$USER/flag.txt"
chown "$USER:$USER" "/home/$USER/flag.txt"

cat > /opt/wsocket/config/client.conf <<'EOF'
SERVICE=phantom-relay
WEBSOCKET=ws://127.0.0.1:8765
PUBLIC_ROOT=/opt/wsocket/data/public
CLIENT_MODE=operator
EOF

chmod 644 /opt/wsocket/config/client.conf

cat > /opt/wsocket/logs/socket.log <<'EOF'
2026-09-30T00:14:03Z phantom-relay starting
2026-09-30T00:14:03Z transport=websocket
2026-09-30T00:14:03Z listener=127.0.0.1:8765
2026-09-30T00:14:04Z operator diagnostic credential issued
2026-09-30T00:14:04Z operator_token=OPS_9f3c7a21d4b8
2026-09-30T00:14:04Z public export root=/opt/wsocket/data/public
2026-09-30T00:14:04Z admin ticket stored outside public export
2026-09-30T00:14:05Z relay ready
EOF

chmod 644 /opt/wsocket/logs/socket.log

cat > /opt/wsocket/config/admin.ticket <<'EOF'
ADMIN_4c91f2a7e8d6
EOF

chmod 600 /opt/wsocket/config/admin.ticket
chown root:root /opt/wsocket/config/admin.ticket

cat > /opt/wsocket/data/public/welcome.txt <<'EOF'
PHANTOM RELAY
=============

The relay backend is WebSocket-only.

Expected transport:
ws://127.0.0.1:8765

Available operator operations:
- auth
- whoami
- list
- read

Public export storage is intentionally legacy-compatible.
EOF

chmod 644 /opt/wsocket/data/public/welcome.txt

cat > /opt/wsocket/data/public/relay-notes.txt <<'EOF'
Operational note:

The operator console is restricted to the public export tree.

An administrator maintains a privileged ticket outside this tree.

The relay performs path validation before opening requested files.
EOF

chmod 644 /opt/wsocket/data/public/relay-notes.txt

cat > /opt/wsocket/bin/backend.py <<'PY'
#!/usr/bin/env python3

import asyncio
import json
import os
from pathlib import Path

import websockets

HOST = "127.0.0.1"
PORT = 8765

PUBLIC_ROOT = Path("/opt/wsocket/data/public")
CONFIG_ROOT = Path("/opt/wsocket/config")
FLAG = Path("/root/flag.txt")

OPERATOR_TOKEN = "OPS_9f3c7a21d4b8"
ADMIN_TOKEN = "ADMIN_4c91f2a7e8d6"


def reply(ok, **kwargs):
    data = {
        "ok": ok
    }
    data.update(kwargs)
    return json.dumps(data)


def read_file(path):
    try:
        raw = Path(path).read_text(errors="replace")
    except Exception as exc:
        return False, str(exc)

    if len(raw) > 8192:
        raw = raw[:8192]

    return True, raw


async def handler(websocket, path):

    role = "guest"

    await websocket.send(
        reply(
            True,
            service="phantom-relay",
            transport="websocket",
            version="2.4",
            authenticated=False
        )
    )

    async for raw in websocket:

        try:
            request = json.loads(raw)
        except Exception:
            await websocket.send(
                reply(
                    False,
                    error="invalid-json"
                )
            )
            continue

        if not isinstance(request, dict):
            await websocket.send(
                reply(
                    False,
                    error="object-required"
                )
            )
            continue

        op = str(
            request.get("op", "")
        ).lower()

        if op == "hello":
            await websocket.send(
                reply(
                    True,
                    service="phantom-relay",
                    transport="websocket",
                    role=role
                )
            )
            continue

        if op == "auth":

            token = str(
                request.get("token", "")
            )

            if token == OPERATOR_TOKEN:
                role = "operator"

                await websocket.send(
                    reply(
                        True,
                        message="operator-authenticated",
                        role=role
                    )
                )

            elif token == ADMIN_TOKEN:
                role = "admin"

                await websocket.send(
                    reply(
                        True,
                        message="administrator-authenticated",
                        role=role
                    )
                )

            else:
                await websocket.send(
                    reply(
                        False,
                        error="authentication-failed"
                    )
                )

            continue

        if op == "whoami":
            await websocket.send(
                reply(
                    True,
                    role=role
                )
            )
            continue

        if op == "list":

            if role == "guest":
                await websocket.send(
                    reply(
                        False,
                        error="authentication-required"
                    )
                )
                continue

            files = []

            for item in sorted(PUBLIC_ROOT.iterdir()):
                if item.is_file():
                    files.append(item.name)

            await websocket.send(
                reply(
                    True,
                    root=str(PUBLIC_ROOT),
                    files=files
                )
            )
            continue

        if op == "read":

            if role == "guest":
                await websocket.send(
                    reply(
                        False,
                        error="authentication-required"
                    )
                )
                continue

            requested = str(
                request.get("path", "")
            )

            if not requested:
                await websocket.send(
                    reply(
                        False,
                        error="path-required"
                    )
                )
                continue

            if role == "operator":

                target = os.path.join(
                    str(PUBLIC_ROOT),
                    requested
                )

                if not target.startswith(
                    str(PUBLIC_ROOT)
                ):
                    await websocket.send(
                        reply(
                            False,
                            error="access-denied"
                        )
                    )
                    continue

                success, content = read_file(target)

            elif role == "admin":

                if requested.startswith("/"):
                    target = requested
                else:
                    target = os.path.join(
                        str(PUBLIC_ROOT),
                        requested
                    )

                success, content = read_file(target)

            else:
                await websocket.send(
                    reply(
                        False,
                        error="invalid-role"
                    )
                )
                continue

            if not success:
                await websocket.send(
                    reply(
                        False,
                        error="read-failed",
                        detail=content
                    )
                )
                continue

            await websocket.send(
                reply(
                    True,
                    path=requested,
                    content=content
                )
            )
            continue

        if op == "debug":

            if role != "admin":
                await websocket.send(
                    reply(
                        False,
                        error="admin-only"
                    )
                )
                continue

            await websocket.send(
                reply(
                    True,
                    process=os.getpid(),
                    root_flag=str(FLAG),
                    config=str(CONFIG_ROOT)
                )
            )
            continue

        await websocket.send(
            reply(
                False,
                error="unknown-operation"
            )
        )


async def main():

    async with websockets.serve(
        handler,
        HOST,
        PORT
    ):
        print(
            f"phantom-relay listening on ws://{HOST}:{PORT}",
            flush=True
        )

        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
PY

chmod 755 /opt/wsocket/bin/backend.py
chown root:root /opt/wsocket/bin/backend.py

cat > /opt/wsocket/bin/wsctl <<'EOF'
#!/bin/sh

exec python3 /opt/wsocket/bin/wsctl.py "$@"
EOF

cat > /opt/wsocket/bin/wsctl.py <<'PY'
#!/usr/bin/env python3

import asyncio
import json
import sys

import websockets

URI = "ws://127.0.0.1:8765"


async def interactive():
    async with websockets.connect(URI) as ws:

        try:
            greeting = await ws.recv()
            print(greeting)
        except Exception:
            return

        for line in sys.stdin:

            line = line.strip()

            if not line:
                continue

            await ws.send(line)

            try:
                response = await ws.recv()
            except Exception as exc:
                print(
                    json.dumps(
                        {
                            "ok": False,
                            "error": str(exc)
                        }
                    )
                )
                return

            print(response)


async def single(command):
    async with websockets.connect(URI) as ws:

        try:
            await ws.recv()
        except Exception:
            pass

        await ws.send(command)

        response = await ws.recv()

        print(response)


def main():

    if len(sys.argv) > 1:

        command = " ".join(
            sys.argv[1:]
        )

        asyncio.run(
            single(command)
        )

    else:
        asyncio.run(
            interactive()
        )


if __name__ == "__main__":
    main()
PY

chmod 755 /opt/wsocket/bin/wsctl
chmod 755 /opt/wsocket/bin/wsctl.py

ln -sf /opt/wsocket/bin/wsctl /usr/local/bin/wsctl

python3 \
    /opt/wsocket/bin/backend.py \
    >/opt/wsocket/logs/backend.log \
    2>&1 &

sleep 2

if ! kill -0 "$!" 2>/dev/null; then
    echo "[Entrypoint] WebSocket backend failed"
    cat /opt/wsocket/logs/backend.log 2>/dev/null || true
    exit 1
fi

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

passwd -l root >/dev/null 2>&1 || true

unset SSH_PASSWORD SHELL_PASSWORD PASSWORD USER_PASSWORD
unset SSH_USER SHELL_USER USER_NAME USERNAME USER
unset FLAG CHALLENGE_FLAG DYNAMIC_FLAG

exec /usr/sbin/sshd -D -e