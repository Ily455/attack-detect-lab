FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# Base tools + attack surface utilities
RUN apt-get update && apt-get install -y \
    openssh-server \
    curl wget vim \
    cron sudo \
    gawk findutils \
    rsyslog \
    net-tools iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# PowerShell (ARM64 — installed from GitHub releases, not MS package repo)
RUN curl -L https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/powershell-7.4.6-linux-arm64.tar.gz \
    -o /tmp/pwsh.tar.gz \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar zxf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7 \
    && chmod +x /opt/microsoft/powershell/7/pwsh \
    && ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh \
    && rm /tmp/pwsh.tar.gz

# Filebeat
RUN curl -L https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.14.3-arm64.deb \
    -o /tmp/filebeat.deb \
    && dpkg -i /tmp/filebeat.deb \
    && rm /tmp/filebeat.deb

# SSH user for Atomic Red Team to connect as
RUN useradd -m -s /bin/bash attacker \
    && echo 'attacker:attacker' | chpasswd \
    && usermod -aG sudo attacker \
    && echo 'attacker ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# SSH config + PowerShell subsystem for PSRemoting
RUN mkdir -p /var/run/sshd \
    && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config \
    && echo "Subsystem powershell $(which pwsh) -sshs -NoLogo" >> /etc/ssh/sshd_config

COPY setup/target-filebeat.yml /etc/filebeat/filebeat.yml
COPY target/powershell.config.json /opt/microsoft/powershell/7/powershell.config.json
COPY target/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
