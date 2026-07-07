FROM harbor.gpu.ecmasai.com:543/library/maca-native:3.7.2.1-kylinv11-amd64
COPY find /usr/bin/find
RUN chmod 0755 /usr/bin/find && (/usr/bin/find --version >/dev/null 2>&1 || /usr/bin/find /opt -maxdepth 1 -type d >/dev/null)
