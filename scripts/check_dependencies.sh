#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(
  imagemagick
  ros-noetic-amcl
  ros-noetic-gmapping
  ros-noetic-hector-mapping
  ros-noetic-map-server
  ros-noetic-rqt-robot-steering
  ros-noetic-tf
  ros-noetic-rosbag
)

missing=()
for package in "${PACKAGES[@]}"; do
  if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "ok installed"; then
    missing+=("$package")
  fi
done

if ! command -v rospack >/dev/null 2>&1 || ! rospack find lar_gazebo >/dev/null 2>&1; then
  echo "ERRO: o pacote local lar_gazebo nao foi encontrado. Compile e carregue o workspace." >&2
  exit 1
fi

if ((${#missing[@]} == 0)); then
  echo "Todas as dependencias ROS da atividade estao instaladas."
  exit 0
fi

echo "Dependencias ausentes: ${missing[*]}" >&2
if [[ "${1:-}" != "--install" ]]; then
  echo "Execute novamente com --install para instala-las explicitamente." >&2
  exit 1
fi

echo "Instalando dependencias com apt..."
sudo apt-get update
sudo apt-get install -y "${missing[@]}"
echo "Dependencias instaladas. Recompile o workspace antes de continuar."
