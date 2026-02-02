FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip wireguard-tools iproute2 iptables ca-certificates \
    qemu-utils cloud-image-utils \
    python3-libvirt \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY app.py vm_manager.py .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

ENV DATA_DIR=/data
EXPOSE 8000
ENTRYPOINT ["./entrypoint.sh"]
