# T1105 — Ingress Tool Transfer

## Technique

**MITRE ATT&CK:** [T1105](https://attack.mitre.org/techniques/T1105/)  
**Tactic:** Command and Control  
**Platform:** Linux

Adversaries transfer tools or files from an external system into a compromised environment. On Linux, `curl` and `wget` are the most common vectors — they're installed by default on most distributions and attract little attention in isolation.

---

## Test Environment

- **Target:** Ubuntu 22.04 ARM64 (UTM VM)
- **Attacker:** macOS M3 triggering via SSH
- **Tool:** Atomic Red Team — `Invoke-AtomicTest T1105`
- **Logging:** auditd with execve syscall rules, shipped via Filebeat to Elasticsearch

---

## Execution

```bash
./run-test.sh T1105
```

9 sub-tests attempted. 7 succeeded:

- **T1105-1** — rsync remote file copy (push)
- **T1105-2** — rsync remote file copy (pull)
- **T1105-3** — scp remote file copy (push)
- **T1105-4** — scp remote file copy (pull)
- **T1105-5** — sftp remote file copy (push)
- **T1105-6** — sftp remote file copy (pull)
- **T1105-27** — Linux Download File and Run via `curl`

A dedicated `remote` container (Ubuntu + SSH + rsync) was added to the lab to enable the transfer tests. The VM connects to it via SSH config alias `victim-host → 192.168.64.1:2223`, with key-based authentication to allow non-interactive rsync/scp/sftp.

2 tests failed: test 14 (whois binary not installed on target — exit code 127), test 39 (kubectl not installed — out of scope).

---

## Evidence

auditd captured the `curl` invocation:

```
type=EXECVE msg=audit(...): a0="curl" a1="-s" a2="<url>"
```

The key signal here is `curl` or `wget` followed closely by an `execve` of the downloaded file — download and immediate execution is the pattern that distinguishes tool transfer from a simple web request.

---

## Detection

### KQL (Kibana)

```
message: "type=EXECVE" AND (message: "a0=\"curl\"" OR message: "a0=\"wget\"")
```

### Sigma Rule

See [`detections/T1105_ingress_tool_transfer.yml`](../detections/T1105_ingress_tool_transfer.yml)

---

## Notes

- `curl` and `wget` are high-volume false positive sources — the useful signal is the combination: download to `/tmp/` followed by execution of the downloaded file within the same session
- Downloading to `/tmp/` or `/dev/shm/` and executing from there is a strong indicator — legitimate software rarely does this
- In this lab, 8/9 tests required a reachable remote host for rsync/scp/sftp transfers — those techniques are valid but outside the scope of a single-target setup
