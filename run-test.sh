#!/usr/bin/env bash
set -euo pipefail

TECHNIQUE="${1:-}"
VM_USER="ubuntu"
VM_IP="192.168.64.2"
REMOTE_HOST="192.168.64.1"
REMOTE_PORT="2223"
REMOTE_USER="remote"
REMOTE_PASS="remote"

if [[ -z "$TECHNIQUE" ]]; then
  echo "Usage: $0 <TECHNIQUE_ID>  (e.g. T1059.004)"
  exit 1
fi

echo "[*] Running $TECHNIQUE on target VM ($VM_IP)"

if [[ "$TECHNIQUE" == "T1105" ]]; then
  # Start fake whois server on VM port 8443 for test 14
  ssh "$VM_USER@$VM_IP" "sudo bash -c 'pkill -f \"python3.*8443\" 2>/dev/null; python3 -c \"
import socket, threading
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((\\\"\\\", 8443))
s.listen()
def h(c): c.send(b\\\"whois response\\\"); c.close()
while True:
    c, _ = s.accept()
    threading.Thread(target=h, args=(c,)).start()
\" &>/dev/null &'" || true

  ssh "$VM_USER@$VM_IP" "sudo pwsh -c \"
    Import-Module invoke-atomicredteam
    \\\$args = @{
      remote_host = 'victim-host'
      username = '$REMOTE_USER'
      remote_path = '/home/remote/incoming/'
      remote_file = '/tmp/adversary-scp'
      local_path = '/tmp/victim-files/'
      local_file = '/tmp/adversary-scp'
    }
    Invoke-AtomicTest T1105 -InputArgs \\\$args
  \""

  # Stop fake whois server
  ssh "$VM_USER@$VM_IP" "sudo pkill -f 'python3.*8443' 2>/dev/null || true"
else
  ssh "$VM_USER@$VM_IP" "sudo pwsh -c \"
    Import-Module invoke-atomicredteam
    Invoke-AtomicTest $TECHNIQUE
  \""
fi

echo "[*] Waiting for events to settle..."
sleep 5

echo "[*] Running cleanup"
ssh "$VM_USER@$VM_IP" "sudo pwsh -c \"
  Import-Module invoke-atomicredteam
  Invoke-AtomicTest $TECHNIQUE -Cleanup
\""

echo "[+] Done. Check Kibana: http://localhost:5601"
