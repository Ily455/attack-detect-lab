#!/usr/bin/env bash
set -euo pipefail

TECHNIQUE="${1:-}"
VM_USER="root"
VM_IP="192.168.64.2"
VM_SSH_KEY=~/.ssh/attack-detect-vm-root
REMOTE_HOST="192.168.64.1"
REMOTE_USER="remote"

if [[ -z "$TECHNIQUE" ]]; then
  echo "Usage: $0 <TECHNIQUE_ID>  (e.g. T1059.004)"
  exit 1
fi

echo "[*] Running $TECHNIQUE on target VM ($VM_IP) via PSRemoting"

if [[ "$TECHNIQUE" == "T1105" ]]; then
  # Start fake whois server on VM for test 14
  ssh -i "$VM_SSH_KEY" "$VM_USER@$VM_IP" "sudo bash -c 'pkill -f \"python3.*8443\" 2>/dev/null; python3 -c \"
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

  pwsh -c "
    Import-Module ~/AtomicRedTeam/invoke-atomicredteam/Invoke-AtomicRedTeam.psd1
    \$s = New-PSSession -HostName $VM_IP -Port 22 -UserName $VM_USER -SSHTransport -KeyFilePath ~/.ssh/attack-detect-vm-root
    \$args = @{
      remote_host = 'victim-host'
      username    = '$REMOTE_USER'
      remote_path = '/home/remote/incoming/'
      remote_file = '/tmp/adversary-scp'
      local_path  = '/tmp/victim-files/'
      local_file  = '/tmp/adversary-scp'
    }
    Invoke-AtomicTest $TECHNIQUE -Session \$s -InputArgs \$args
    Write-Host '[*] Waiting for events to settle...'
    Start-Sleep 5
    Invoke-AtomicTest $TECHNIQUE -Session \$s -Cleanup -InputArgs \$args
    Remove-PSSession \$s
  "

  ssh -i "$VM_SSH_KEY" "$VM_USER@$VM_IP" "sudo pkill -f 'python3.*8443' 2>/dev/null || true"

else
  pwsh -c "
    Import-Module ~/AtomicRedTeam/invoke-atomicredteam/Invoke-AtomicRedTeam.psd1
    \$s = New-PSSession -HostName $VM_IP -Port 22 -UserName $VM_USER -SSHTransport -KeyFilePath ~/.ssh/attack-detect-vm-root
    Invoke-AtomicTest $TECHNIQUE -Session \$s
    Write-Host '[*] Waiting for events to settle...'
    Start-Sleep 5
    Invoke-AtomicTest $TECHNIQUE -Session \$s -Cleanup
    Remove-PSSession \$s
  "
fi

echo "[+] Done. Check Kibana: http://localhost:5601"
