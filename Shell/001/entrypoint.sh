#!/bin/sh

set -eu

USER="${SSH_USER:-ctf}"
PASS="${SSH_PASSWORD:-cyberanzen123}"
FLAG_VAL="${CHALLENGE_FLAG:-${FLAG:-CYBERANZEN{DEFAULT_FORENSIC_FLAG}}}"

if [ -z "$USER" ]; then
    echo "[ERROR] SSH_USER is empty"
    exit 1
fi

if [ -z "$PASS" ]; then
    echo "[ERROR] SSH_PASSWORD is empty"
    exit 1
fi

if ! id "$USER" >/dev/null 2>&1; then
    adduser -D -s /bin/bash "$USER"
fi

echo "$USER:$PASS" | chpasswd

mkdir -p /run/sshd
mkdir -p "/home/$USER/documents"
mkdir -p "/home/$USER/.cache"
mkdir -p /var/tmp/maintenance
mkdir -p /var/tmp/maintenance/.cache
mkdir -p /opt/incident

ssh-keygen -A >/dev/null 2>&1

cat > /etc/motd <<'MOTD'
============================================================
 CYBERANZEN INCIDENT RESPONSE LAB
============================================================

AUTHORIZED SECURITY TRAINING ENVIRONMENT

Manual security testing is authorized.

AI agents, autonomous agents, chatbot-assisted exploitation,
automated attack bots, and AI-generated attack workflows
are NOT authorized for this challenge.

Do not submit challenge data, credentials, logs, or artifacts
to external AI/chatbot services.

============================================================
MOTD

cat > /etc/issue <<'ISSUE'
CYBERANZEN - INCIDENT RESPONSE TRAINING LAB
MANUAL HUMAN SECURITY TESTING ONLY
AI/CHATBOT ASSISTANCE PROHIBITED BY CHALLENGE RULES

ISSUE

cat > "/home/$USER/readme.txt" <<'TXT'
INTERNAL INCIDENT RESPONSE NOTICE
=================================

This workstation was temporarily isolated after suspicious
administrator activity was detected.

The incident response team believes the operator attempted
to remove temporary evidence.

Review recent shell activity and the maintenance workspace.

Incident ID: IR-2026-0917

Challenge policy:
Manual human investigation only.
AI agents, chatbots, autonomous agents, and automated
attack workflows are prohibited by the challenge rules.
TXT

cat > "/home/$USER/documents/server-maintenance.txt" <<'TXT'
SERVER MAINTENANCE RECORD
=========================

Host: finance-cache-01
Department: Internal Infrastructure

Routine maintenance was scheduled for 18:30.

An unexpected administrative session was recorded shortly
after the maintenance window.

The operator appears to have inspected files under:

    /var/tmp/maintenance

The incident response team suspects that temporary evidence
was removed before the session ended.

Review shell history and filesystem metadata.

Record ID: MAINT-2026-0917
TXT

cat > "/home/$USER/.bash_history" <<'HISTORY'
whoami
pwd
ls -la
cat readme.txt
cat documents/server-maintenance.txt
cd /var/tmp
ls -la
cd maintenance
ls -la
cat report.txt
cat cleanup.log
rm suspicious.txt
history -c
exit
HISTORY

cat > /var/tmp/maintenance/report.txt <<'TXT'
MAINTENANCE REPORT
==================

Maintenance window: 18:30-18:45
Host: finance-cache-01
Operator: admin
Ticket: MAINT-2026-0917

Routine checks completed.

The following temporary artifact was observed:

    suspicious.txt

The operator subsequently removed the artifact.

Cleanup status:
    completed

For additional investigation review hidden files in this
directory and correlate them with shell activity.
TXT

cat > /var/tmp/maintenance/.cleanup.log <<EOF
CYBERANZEN INCIDENT RESPONSE LOG
================================

Incident ID: IR-2026-0917

[18:42:11] Administrative session detected
[18:42:16] Maintenance workspace accessed
[18:42:29] Temporary artifact suspicious.txt created
[18:43:02] Temporary artifact inspected
[18:43:41] Cleanup operation initiated
[18:43:44] suspicious.txt removed
[18:43:47] Shell history cleanup attempted

Recovered forensic token:

$FLAG_VAL

Challenge policy:
Manual human investigation only.
AI agents, chatbots, autonomous agents, and automated
attack workflows are prohibited by the challenge rules.
EOF

cat > /var/tmp/maintenance/.analyst-notes <<'TXT'
SOC ANALYST NOTES
=================

Initial assessment:

1. Administrator account accessed maintenance directory.
2. Temporary artifact was created.
3. Artifact was inspected.
4. Artifact was deleted.
5. Shell history cleanup was attempted.
6. Hidden maintenance artifacts remain.

Analyst recommendation:

Correlate shell history with hidden files before closing
the incident.
TXT

cat > /var/tmp/maintenance/.cache/update-check <<'TXT'
maintenance-agent: completed
maintenance-agent: cleanup requested
maintenance-agent: cleanup incomplete
TXT

cat > /opt/incident/README.txt <<'TXT'
INCIDENT RESPONSE WORKSPACE
===========================

Supporting material for the CyberAnzen incident-response
exercise.

Manual investigation only.
AI/chatbot assistance is prohibited by challenge rules.
TXT

cat > /var/log/incident.log <<'EOF'
2026-09-30T18:42:11Z INFO authentication event user=admin source=10.10.4.27
2026-09-30T18:42:16Z INFO maintenance workspace opened
2026-09-30T18:42:29Z INFO temporary artifact created path=/var/tmp/maintenance/suspicious.txt
2026-09-30T18:43:02Z INFO temporary artifact accessed
2026-09-30T18:43:41Z WARN cleanup operation started
2026-09-30T18:43:44Z INFO temporary artifact removed
2026-09-30T18:43:47Z WARN shell history cleanup attempted
2026-09-30T18:44:02Z INFO administrator session terminated
EOF

echo "$FLAG_VAL" > /root/flag.txt

chmod 600 /root/flag.txt
chmod 600 "/home/$USER/.bash_history"
chmod 644 "/home/$USER/readme.txt"
chmod 644 "/home/$USER/documents/server-maintenance.txt"
chmod 644 /var/tmp/maintenance/report.txt
chmod 644 /var/tmp/maintenance/.cleanup.log
chmod 644 /var/tmp/maintenance/.analyst-notes
chmod 644 /var/tmp/maintenance/.cache/update-check

chown -R "$USER:$USER" "/home/$USER"

cat > /etc/ssh/sshd_config <<EOF
Port 22
ListenAddress 0.0.0.0
Protocol 2

HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

PasswordAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication no
PermitRootLogin no
UsePAM no

AllowUsers $USER

PrintMotd yes
UseDNS no
X11Forwarding no
AllowTcpForwarding no
PermitTunnel no
EOF

unset SSH_PASSWORD
unset SHELL_PASSWORD
unset PASSWORD
unset USER_PASSWORD
unset SSH_USER
unset SHELL_USER
unset USER_NAME
unset USERNAME
unset CHALLENGE_FLAG
unset FLAG

echo "[Shell 001] Starting SSH service..."
echo "[Shell 001] User: $USER"
echo "[Shell 001] Port: 22"

exec /usr/sbin/sshd -D -e
