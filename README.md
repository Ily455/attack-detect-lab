# attack-detect-lab

Local cybersecurity lab for simulating MITRE ATT&CK techniques and detecting them with Elastic SIEM. The Mac acts as the attacker — it runs Atomic Red Team and sends commands to a Linux VM via PSRemoting. The VM is the victim — it executes the techniques, logs every syscall via auditd, and ships events to the SIEM. Everything is local, no cloud.

---

## Table of Contents

- [Architecture](#architecture)
- [Stack](#stack)
- [Directory Structure](#directory-structure)
- [Mac Prerequisites](#mac-prerequisites)
- [VM Setup from Scratch](#vm-setup-from-scratch)
- [Lab Setup](#lab-setup)
- [What setup-and-run.sh Does](#what-setup-and-runsh-does)
- [Running Individual Tests](#running-individual-tests)
- [Techniques](#techniques)
- [Detection Rules](#detection-rules)
- [Cleanup](#cleanup)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  macOS Host (M3) — ATTACKER                                         │
│                                                                     │
│  Atomic Red Team + run-test.sh                                      │
│    └── PSRemoting (SSH) ──────────────────────────────────────┐     │
│                                                               │     │
│  ┌────────────────────────────────────────────────────────┐   │     │
│  │  Docker (bridge: elastic)                              │   ↓     │
│  │  elasticsearch:9200   kibana:5601   remote:2223        │  UTM VM │
│  └────────────────────────────────────────────────────────┘  (192.168.64.2)
│         ▲                                                     │     │
│         └───── Filebeat ships logs ───────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────┘
                                              Ubuntu 22.04 ARM64
                                              auditd · Filebeat · pwsh SSH
```

- **Mac (attacker)** — runs Atomic Red Team and `run-test.sh`. Sends commands to the VM via PowerShell SSH remoting. Never installs attack tools on the victim.
- **VM (victim)** — executes the techniques received via PSRemoting, records every `execve` syscall with auditd, ships logs to Elasticsearch via Filebeat.
- **Docker (SIEM)** — Elasticsearch stores and indexes logs. Kibana provides the Security UI and detection rules. Remote container acts as a staging server for T1105 file transfer tests.

---

## Stack

| Component | Where | Role | Version |
|---|---|---|---|
| Atomic Red Team | Mac | MITRE ATT&CK technique simulator | latest |
| PowerShell | Mac | PSRemoting transport + Atomic runtime | 7.4.6 |
| Elasticsearch | Docker | Log storage and indexing | 8.14.3 |
| Kibana | Docker | SIEM UI, detection rules | 8.14.3 |
| Remote container | Docker | SSH + rsync staging server (T1105) | Ubuntu 22.04 |
| Target VM | UTM | Ubuntu 22.04 ARM64 — attack surface | ARM64 |
| auditd | VM | Records every execve syscall | system |
| Filebeat | VM | Ships auditd logs to Elasticsearch | 8.14.3 |

Elastic images run as `linux/arm64` — native M3 execution, no emulation.

---

## Directory Structure

```
attack-detect-lab/
├── docker-compose.yml        # Elasticsearch + Kibana + remote container
├── run-test.sh               # Run a single technique via PSRemoting
├── setup-and-run.sh          # One-shot: configure VM + run all 6 techniques
├── README.md
├── remote/
│   └── Dockerfile            # Minimal SSH + rsync container for T1105
├── setup/
│   └── target-filebeat.yml   # Filebeat config — deploy this on the VM
├── detections/
│   ├── T1059.004_unix_shell.yml
│   ├── T1053.003_cron_persistence.yml
│   ├── T1136.001_create_local_account.yml
│   ├── T1087.001_local_account_discovery.yml
│   ├── T1083_file_directory_discovery.yml
│   ├── T1105_ingress_tool_transfer.yml
│   └── kibana-rules.ndjson   # All 6 rules — importable directly into Kibana
└── writeups/
    ├── T1059.004_unix_shell.md
    ├── T1053.003_cron_persistence.md
    ├── T1136.001_create_local_account.md
    ├── T1087.001_local_account_discovery.md
    ├── T1083_file_directory_discovery.md
    └── T1105_ingress_tool_transfer.md
```

---

## Mac Prerequisites

### 1. Docker Desktop

Download and install from [docker.com](https://www.docker.com/products/docker-desktop/). Required for Elasticsearch, Kibana, and the remote container.

### 2. UTM

Download from [mac.getutm.app](https://mac.getutm.app/). Used to run the Ubuntu target VM.

### 3. PowerShell

```bash
brew install --cask powershell
```

Verify: `pwsh --version`

### 4. Atomic Red Team (on Mac)

```bash
pwsh -c "
  IEX (IWR 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicredteam.ps1' -UseBasicParsing)
  Install-AtomicRedTeam -getAtomics -Force
"
```

This installs Atomic to `~/AtomicRedTeam/`. Verify:

```bash
ls ~/AtomicRedTeam/invoke-atomicredteam/Invoke-AtomicRedTeam.psd1
```

### 5. Ubuntu SSH key

Generate the key that `setup-and-run.sh` will use to bootstrap the VM:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/attack-detect-vm -N ""
ssh-copy-id -i ~/.ssh/attack-detect-vm.pub ubuntu@192.168.64.2
```

The second command requires the VM to be running and reachable (see VM Setup below).

---

## VM Setup from Scratch

Create an **Ubuntu 22.04 ARM64** VM in UTM. The default UTM bridge network gives the VM IP `192.168.64.2` and the Mac IP `192.168.64.1` — these addresses are hardcoded in the scripts.

Boot the VM and run the following commands inside it (via UTM console or SSH with password).

### 1. Install required packages

```bash
sudo apt update && sudo apt install -y \
  auditd \
  rsync \
  openssh-server \
  curl wget
```

### 2. Install PowerShell (ARM64 — must use tarball, no apt package for ARM64)

```bash
PWSH_VERSION="7.4.6"
curl -L "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-arm64.tar.gz" \
  -o /tmp/pwsh.tar.gz
sudo mkdir -p /opt/microsoft/powershell/7
sudo tar zxf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7
sudo chmod +x /opt/microsoft/powershell/7/pwsh
sudo ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh
```

Verify: `pwsh --version`

### 3. Configure PowerShell SSH subsystem

```bash
echo "Subsystem powershell /usr/bin/pwsh -sshs -NoLogo" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart ssh
```

This is what allows PSRemoting to work — without it, `New-PSSession` will fail.

### 4. Configure auditd

Deploy the audit rules from this repo:

```bash
# From the Mac — copy the rules file to the VM
scp -i ~/.ssh/attack-detect-vm target/audit.rules ubuntu@192.168.64.2:/tmp/audit.rules
```

Then on the VM:

```bash
sudo cp /tmp/audit.rules /etc/audit/rules.d/attack-detect.rules
sudo systemctl enable auditd --now
sudo auditctl -R /etc/audit/rules.d/attack-detect.rules
```

Verify auditd is capturing execve:

```bash
sudo ausearch -k exec_commands | tail -5
```

### 5. Install and configure Filebeat

```bash
# Download Filebeat ARM64
curl -L "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.14.3-linux-arm64.tar.gz" \
  -o /tmp/filebeat.tar.gz
sudo tar zxf /tmp/filebeat.tar.gz -C /opt/
sudo mv /opt/filebeat-8.14.3-linux-arm64 /opt/filebeat
sudo ln -sf /opt/filebeat/filebeat /usr/local/bin/filebeat
```

Deploy the config from this repo:

```bash
# From the Mac
scp -i ~/.ssh/attack-detect-vm setup/target-filebeat.yml ubuntu@192.168.64.2:/tmp/filebeat.yml
```

On the VM:

```bash
sudo cp /tmp/filebeat.yml /opt/filebeat/filebeat.yml
```

Create a systemd service so Filebeat starts automatically:

```bash
sudo bash -c 'cat > /etc/systemd/system/filebeat.service << EOF
[Unit]
Description=Filebeat
After=network.target

[Service]
ExecStart=/opt/filebeat/filebeat -e -c /opt/filebeat/filebeat.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF'
sudo systemctl enable filebeat
```

Filebeat will start automatically once the lab is up (it connects to `192.168.64.1:9200` — the Mac's bridge IP). Start it manually only after Docker is running:

```bash
sudo systemctl start filebeat
```

### 6. Install SSH key for ubuntu user

On the Mac, after the VM is configured:

```bash
ssh-copy-id -i ~/.ssh/attack-detect-vm.pub ubuntu@192.168.64.2
```

### 7. Take a snapshot

In UTM, take a snapshot named `baseline-clean`. This is your restore point — you can always come back to a known good state.

---

## Lab Setup

Every time you start a fresh lab session:

### 1. Start Docker services

```bash
cd ~/Desktop/Projects/attack-detect-lab
docker compose up -d
```

Wait ~60 seconds for Elasticsearch to be healthy, then Kibana starts.

**Kibana:** [http://localhost:5601](http://localhost:5601) — `elastic` / `changeme`

### 2. Start the VM in UTM

Boot the Ubuntu VM. Filebeat starts automatically and begins shipping logs to `192.168.64.1:9200`.

### 3. Import detection rules

```bash
curl -X POST "http://localhost:5601/api/detection_engine/rules/_import?overwrite=true" \
  -u elastic:changeme \
  -H "kbn-xsrf: true" \
  -F "file=@detections/kibana-rules.ndjson"
```

### 4. Run setup-and-run.sh

```bash
./setup-and-run.sh 2>&1 | tee /tmp/lab-run.txt
```

This configures PSRemoting root access and runs all 6 techniques in sequence. See below for details.

---

## What setup-and-run.sh Does

`setup-and-run.sh` is a one-shot script that configures the VM for PSRemoting as root, sets up the T1105 staging environment, and runs all 6 techniques. Run it once per session after starting Docker and the VM.

**Step 1 — Configure VM for root PSRemoting**
- Grants ubuntu passwordless sudo (needed to bootstrap root access)
- Enables root SSH login in sshd_config
- Generates `~/.ssh/attack-detect-vm-root` on the Mac (ed25519 key)
- Installs that key in `/root/.ssh/authorized_keys` on the VM

**Step 2 — Configure the remote container (T1105)**
- Generates an SSH key on the VM (`/root/.ssh/id_ed25519_remote`)
- Adds that key to the remote container's `authorized_keys`
- Writes an SSH config on the VM aliasing `victim-host → 192.168.64.1:2223`
- Creates test payload files in `/tmp/` on both VM and container

**Step 3 — Test PSRemoting**
- Opens a PSSession from the Mac to the VM as root
- Confirms the session is open — fails fast if something is wrong

**Step 4 — Run all 6 techniques**
- Calls `./run-test.sh` for each technique in sequence
- Each run: execute → wait 5s → cleanup

After the script completes, check Kibana → Security → Alerts (last 1 hour).

---

## Running Individual Tests

```bash
./run-test.sh <TECHNIQUE_ID>
```

Example:

```bash
./run-test.sh T1059.004
```

The script opens a PSSession from the Mac to the VM as root, runs `Invoke-AtomicTest` with that session (commands execute on the VM), waits 5 seconds for events to settle, then runs cleanup. Logs appear in Kibana under `attack-detect-logs-*` within seconds.

For T1105, the script also starts a temporary whois server on the VM (for test 14) and passes the remote container coordinates as InputArgs.

**Prerequisites before running individual tests:**
`setup-and-run.sh` must have been run at least once in the current session — it generates `~/.ssh/attack-detect-vm-root` and configures root access on the VM.

---

## Techniques

| # | ID | Name | Tests passed | Tactic |
|---|---|---|---|---|
| 1 | T1059.004 | Unix Shell | 15/17 | Execution |
| 2 | T1053.003 | Cron Job Persistence | 4/4 | Persistence |
| 3 | T1136.001 | Create Local Account | 2/5 | Persistence |
| 4 | T1087.001 | Local Account Discovery | 4/4 | Discovery |
| 5 | T1083 | File and Directory Discovery | 3/3 | Discovery |
| 6 | T1105 | Ingress Tool Transfer | 7/9 | Command & Control |

Test failures are due to platform mismatch (FreeBSD-specific tests) or missing tools (kubectl) — not lab configuration issues.

---

## Detection Rules

Sigma rules in `detections/` — one per technique. All 6 are also packaged in `kibana-rules.ndjson` for direct import into Kibana Security (see Lab Setup step 3).

Each rule targets the `attack-detect-logs-*` index and matches auditd `EXECVE` events from the VM.

Writeups in `writeups/` document the evidence, KQL queries, and detection logic for each technique.

---

## Cleanup

Stop Docker services (removes volumes and data):

```bash
docker compose down -v
```

Stop the UTM VM from the UTM interface. The VM state is preserved — restore to `baseline-clean` snapshot for a full reset.
