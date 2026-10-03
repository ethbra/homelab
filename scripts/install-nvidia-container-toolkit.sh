#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: run with sudo" >&2
  exit 1
fi

echo ">>> Adding NVIDIA container toolkit apt repo..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

echo ">>> Installing nvidia-container-toolkit..."
apt-get update -q
apt-get install -y nvidia-container-toolkit

echo ">>> Generating CDI spec for the GPU..."
mkdir -p /etc/cdi
nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

echo ">>> Restarting Docker..."
systemctl restart docker

echo ""
echo "Done. Verify with: docker run --rm --gpus all ubuntu nvidia-smi"
echo "Then try: docker start plex"
