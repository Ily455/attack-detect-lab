# T1083 — File and Directory Discovery

## Technique

**MITRE ATT&CK:** [T1083](https://attack.mitre.org/techniques/T1083/)  
**Tactic:** Discovery  
**Platform:** Linux

Adversaries enumerate files and directories to understand the target system — locate sensitive files, identify installed software, find configuration files, and map the filesystem structure. On Linux this is done with standard tools available on virtually every system.

---

## Test Environment

- **Target:** Ubuntu 22.04 ARM64 (UTM VM)
- **Attacker:** macOS M3 triggering via SSH
- **Tool:** Atomic Red Team — `Invoke-AtomicTest T1083`
- **Logging:** auditd with execve syscall rules, shipped via Filebeat to Elasticsearch

---

## Execution

```bash
./run-test.sh T1083
```

3/3 Linux sub-tests succeeded:
1. **T1083-3** — File discovery via `ls /tmp` and related commands
2. **T1083-4** — Directory tree enumeration (tree-style recursive listing)
3. **T1083-8** — Network share discovery via `showmount`

---

## Evidence

auditd captured each discovery command via `execve`:

```
type=EXECVE msg=audit(...): argc=2 a0="find" a1="/"
type=EXECVE msg=audit(...): argc=1 a0="showmount"
```

Test 4 produced a recursive directory listing from the filesystem root — visible as a sequence of rapid `find` or `ls` invocations in the auditd log within the same second.

---

## Detection

### KQL (Kibana)

```
message: "type=EXECVE" AND (message: "a0=\"find\"" OR message: "a0=\"showmount\"" OR message: "a0=\"tree\"")
```

### Sigma Rule

See [`detections/T1083_file_directory_discovery.yml`](../detections/T1083_file_directory_discovery.yml)

---

## Notes

- `find` and `ls` are extremely common — this rule has a high false positive rate in isolation
- The useful signal is behavioral: many `find` invocations within a short window, especially starting from `/` or `/home`, is anomalous
- `showmount -e` querying a remote host for NFS shares is a stronger signal — legitimate use is rare outside of sysadmin contexts
- Combine with session context (which user, from which parent process) to reduce noise
