#!/usr/bin/env bash
set -euo pipefail

SSH_KEY=~/.ssh/attack-detect-vm
SSH_KEY_ROOT=~/.ssh/attack-detect-vm-root
VM_USER="ubuntu"
VM_ROOT="root"
VM_IP="192.168.64.2"
REMOTE_USER="remote"
REMOTE_PORT="2223"

echo "=== [1/4] Configuring VM prerequisites ==="

# NOPASSWD and enable root SSH
ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "echo 'ubuntu' | sudo -S bash -c '
  echo \"ubuntu ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/ubuntu
  echo \"PermitRootLogin yes\" >> /etc/ssh/sshd_config
  systemctl restart ssh
'"

# Generate root SSH key on Mac and install on VM
[ -f "$SSH_KEY_ROOT" ] || ssh-keygen -t ed25519 -f "$SSH_KEY_ROOT" -N "" -q
ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "echo 'ubuntu' | sudo -S bash -c '
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  echo $(cat ${SSH_KEY_ROOT}.pub) >> /root/.ssh/authorized_keys
  sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
'"

# SSH key for root@VM → remote container + SSH config
ssh -i "$SSH_KEY_ROOT" "$VM_ROOT@$VM_IP" "
  ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_remote -N '' -q 2>/dev/null || true
  echo 'Host victim-host
    HostName 192.168.64.1
    Port $REMOTE_PORT
    User $REMOTE_USER
    StrictHostKeyChecking no
    IdentityFile /root/.ssh/id_ed25519_remote' > /root/.ssh/config
  chmod 600 /root/.ssh/config
  mkdir -p /tmp/adversary-rsync /tmp/victim-files
  echo test > /tmp/adversary-rsync/payload.txt
  echo test > /tmp/adversary-scp
  chmod 777 /tmp/victim-files
"

echo "=== [2/4] Configuring remote container ==="

# Get VM root's public key and add to remote container
VM_PUBKEY=$(ssh -i "$SSH_KEY_ROOT" "$VM_ROOT@$VM_IP" "cat /root/.ssh/id_ed25519_remote.pub")
docker exec remote bash -c "
  mkdir -p /home/remote/.ssh
  echo '$VM_PUBKEY' >> /home/remote/.ssh/authorized_keys
  sort -u /home/remote/.ssh/authorized_keys -o /home/remote/.ssh/authorized_keys
  chmod 700 /home/remote/.ssh
  chmod 600 /home/remote/.ssh/authorized_keys
  chown -R remote:remote /home/remote/.ssh
  mkdir -p /home/remote/incoming
  echo test > /tmp/adversary-scp
  echo test > /tmp/adversary-sftp
  echo test > /home/remote/incoming/payload.txt
  chmod 644 /tmp/adversary-scp /tmp/adversary-sftp /home/remote/incoming/payload.txt
"

echo "=== [3/4] Testing PSRemoting as root ==="
pwsh -c "
  Import-Module ~/AtomicRedTeam/invoke-atomicredteam/Invoke-AtomicRedTeam.psd1
  \$s = New-PSSession -HostName $VM_IP -Port 22 -UserName $VM_ROOT -SSHTransport -KeyFilePath ~/.ssh/attack-detect-vm-root
  if (\$s.State -eq 'Opened') { Write-Host 'PSRemoting OK' } else { Write-Error 'PSRemoting FAILED'; exit 1 }
  Remove-PSSession \$s
"

echo "=== [4/4] Running all 6 techniques ==="
for TECHNIQUE in T1059.004 T1053.003 T1136.001 T1087.001 T1083 T1105; do
  echo "--- $TECHNIQUE ---"
  ./run-test.sh "$TECHNIQUE"
done

echo ""
echo "=== DONE — Check Kibana: http://localhost:5601 ==="
echo "=== Security → Alerts (last 1 hour) ==="
