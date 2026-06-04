FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    rsync \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash remote \
    && echo 'remote:remote' | chpasswd

RUN mkdir -p /var/run/sshd \
    && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config \
    && mkdir -p /home/remote/incoming \
    && chown remote:remote /home/remote/incoming

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
