#!/bin/bash
set -e

/usr/sbin/rsyslogd || true
service cron start
service ssh start
mkdir -p /var/log/pwsh_transcripts
chmod 777 /var/log/pwsh_transcripts

filebeat -e --strict.perms=false &

exec tail -f /dev/null
