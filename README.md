# attack-detect-lab

Local cybersecurity lab for simulating MITRE ATT&CK techniques and detecting them with Elastic SIEM. Attack simulation runs on a dedicated Linux VM. The SIEM stack runs in Docker. Everything is local — no cloud, no external infrastructure.

---

## Table of Contents

- [Architecture](#architecture)
- [Stack](#stack)
- [Directory Structure](#directory-structure)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Running a Test](#running-a-test)
- [Techniques](#techniques)
- [Detection Rules](#detection-rules)
- [Cleanup](#cleanup)

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  macOS Host (M3)                                                 │
│                                                                  │
│  run-test.sh                                                     │
│    └── SSH → Linux VM (UTM, 192.168.64.2)                        │
│               ├── Atomic Red Team executes techniques            │
│               ├── auditd records every execve syscall            │
│               └── Filebeat ──► Elasticsearch ◄── Kibana          │
│                                (Docker)         (Docker)         │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  Docker (bridge network: elastic)                        │    │
│  │  elasticsearch:9200   kibana:5601   remote:2223 (SSH)    │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

- **Target VM** — Ubuntu 22.04 ARM64 in UTM. Runs Atomic Red Team, auditd, and Filebeat. This is the machine being attacked and monitored.
- **Remote container** — Minimal Ubuntu container with SSH and rsync. Acts as a staging server for T1105 file transfer tests.
- **SIEM** — Elasticsearch + Kibana in Docker. Receives logs from the VM via Filebeat. Detection rules configured in Kibana Security.

---

## Stack

| Component | Role | Version |
|---|---|---|
| Elasticsearch | Log storage and indexing | 8.14.3 |
| Kibana | SIEM UI, detection rules | 8.14.3 |
| Filebeat | Log shipper (runs on VM) | 8.14.3 |
| Target VM | Ubuntu 22.04 ARM64 — attack surface | UTM on M3 |
| Remote container | SSH + rsync staging server | Ubuntu 22.04 |
| Atomic Red Team | MITRE ATT&CK technique simulator | latest |
| PowerShell | Atomic runtime (on VM) | 7.4.6 |

---

## Directory Structure

```
attack-detect-lab/
├── docker-compose.yml       # Elasticsearch + Kibana + remote container
├── run-test.sh              # Test runner — SSH into VM and execute technique
├── README.md
├── remote/
│   └── Dockerfile           # Minimal SSH + rsync container for T1105
├── target/
│   └── Dockerfile           # (legacy — target is now the UTM VM)
├── setup/
│   └── target-filebeat.yml  # Filebeat config deployed on the VM
├── detections/
│   ├── T1059.004_unix_shell.yml
│   ├── T1053.003_cron_persistence.yml
│   ├── T1136.001_create_local_account.yml
│   ├── T1087.001_local_account_discovery.yml
│   ├── T1083_file_directory_discovery.yml
│   ├── T1105_ingress_tool_transfer.yml
│   └── kibana-rules.ndjson  # All 6 rules — importable directly into Kibana
└── writeups/
    ├── T1059.004_unix_shell.md
    ├── T1053.003_cron_persistence.md
    ├── T1136.001_create_local_account.md
    ├── T1087.001_local_account_discovery.md
    ├── T1083_file_directory_discovery.md
    └── T1105_ingress_tool_transfer.md
```

---

## Prerequisites

- **Docker Desktop** — for Elasticsearch, Kibana, and the remote container
- **UTM** — to run the Ubuntu target VM
- **Ubuntu 22.04 ARM64 VM** in UTM with auditd, Filebeat, PowerShell, and Atomic Red Team installed (see Setup)

---

## Setup

### 1. Start Docker services

```bash
cd ~/Desktop/Projects/attack-detect-lab
docker compose up -d
```

Wait for Elasticsearch to be healthy (~60s), then Kibana starts.

**Kibana:** [http://localhost:5601](http://localhost:5601) — `elastic` / `changeme`

### 2. Start the target VM

Open UTM and start the Ubuntu VM. It boots and Filebeat starts automatically, shipping logs to Elasticsearch at `192.168.64.1:9200`.

### 3. Import detection rules into Kibana

```bash
curl -X POST "http://localhost:5601/api/detection_engine/rules/_import?overwrite=true" \
  -u elastic:changeme \
  -H "kbn-xsrf: true" \
  -F "file=@detections/kibana-rules.ndjson"
```

### 4. Verify connectivity

```bash
ssh ubuntu@192.168.64.2 "echo connected"
```

---

## Running a Test

```bash
./run-test.sh <TECHNIQUE_ID>
```

Example:

```bash
./run-test.sh T1059.004
```

The script SSHes into the VM, runs `Invoke-AtomicTest` as root via PowerShell, waits 5 seconds for events to settle, then runs cleanup. Logs are shipped by Filebeat and appear in Kibana under the `attack-detect-logs-*` data view within seconds.

For T1105, the script automatically configures InputArgs to point rsync/scp/sftp at the remote container (`victim-host → 192.168.64.1:2223`).

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

Test failures are due to platform mismatch (FreeBSD-specific tests), missing tools (kubectl, whois), or out-of-scope requirements — not lab configuration issues.

---

## Detection Rules

Sigma rules in `detections/` — one per technique. All 6 rules are also available as `kibana-rules.ndjson` for direct import into Kibana Security.

Each rule targets the `attack-detect-logs-*` index and matches auditd `EXECVE` events captured from the VM.

---

## Cleanup

Stop Docker services:

```bash
docker compose down -v
```

Remove all Docker data:

```bash
docker system prune -a
```

Stop the UTM VM from the UTM interface. The VM state is preserved — delete it from UTM if a full reset is needed.
