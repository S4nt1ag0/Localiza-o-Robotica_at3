#!/usr/bin/env bash
set -euo pipefail

if ! command -v rospack >/dev/null 2>&1; then
  echo "ERRO: ambiente ROS nao carregado. Execute: source ~/catkin_ws/devel/setup.bash" >&2
  exit 1
fi

LAR_DIR=$(rospack find lar_gazebo) || {
  echo "ERRO: pacote lar_gazebo nao encontrado." >&2
  exit 1
}

# O arquivo define HUSKY_LMS1XX_ENABLED=1, necessario para /front/scan.
source "$LAR_DIR/husky_accessories.sh"
export HUSKY_LMS1XX_ENABLED=1

echo "Iniciando LaR com laser /front/scan e sem SLAM online..."
exec roslaunch lar_gazebo lar_husky.launch hector_slam:=false "$@"
