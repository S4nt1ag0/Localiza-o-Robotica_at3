#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || "${1:-}" != "hector" && "${1:-}" != "gmapping" ]]; then
  echo "Uso: $0 {hector|gmapping} [bag_localizacao] [bag_resultado] [x_inicial] [y_inicial] [yaw_inicial]" >&2
  exit 2
fi

METHOD=$1
PACKAGE=localiza_o_robotica_at3
PACKAGE_DIR=$(rospack find "$PACKAGE") || {
  echo "ERRO: pacote $PACKAGE nao encontrado. Compile e carregue o workspace." >&2
  exit 1
}
INPUT_BAG="${2:-$PACKAGE_DIR/bags/lar_localization.bag}"
RESULT_BAG="${3:-$PACKAGE_DIR/results/localization/amcl_${METHOD}.bag}"
INITIAL_X="${4:-0.0}"
INITIAL_Y="${5:-0.0}"
INITIAL_YAW="${6:-0.0}"
read -r INITIAL_QZ INITIAL_QW < <(
  python3 -c "import math; yaw=float('$INITIAL_YAW'); print(math.sin(yaw/2.0), math.cos(yaw/2.0))"
)
MAP_FILE="$PACKAGE_DIR/maps/$METHOD/lar_${METHOD}.yaml"
RESULT_DIR=$(dirname "$RESULT_BAG")
LAUNCH_PID=""
RECORDER_PID=""
PLAY_PID=""

stop_process() {
  local pid=${1:-}
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

cleanup() {
  stop_process "$PLAY_PID"
  stop_process "$RECORDER_PID"
  stop_process "$LAUNCH_PID"
}
trap cleanup EXIT INT TERM

if [[ ! -r "$INPUT_BAG" ]]; then
  echo "ERRO: bag de localizacao inexistente ou ilegivel: $INPUT_BAG" >&2
  exit 1
fi
INPUT_BAG=$(readlink -f "$INPUT_BAG")
if [[ ! -r "$MAP_FILE" ]]; then
  echo "ERRO: mapa $METHOD nao encontrado: $MAP_FILE" >&2
  exit 1
fi
if [[ "$RESULT_BAG" != *.bag ]]; then
  RESULT_BAG="${RESULT_BAG}.bag"
fi
mkdir -p "$(dirname "$RESULT_BAG")"
RESULT_BAG=$(readlink -m "$RESULT_BAG")
RESULT_DIR=$(dirname "$RESULT_BAG")
if [[ "$RESULT_BAG" == "$INPUT_BAG" ]]; then
  echo "ERRO: a bag de resultado nao pode sobrescrever a bag de localizacao." >&2
  exit 1
fi
if [[ -e "$RESULT_BAG" || -e "${RESULT_BAG}.active" ]]; then
  echo "ERRO: resultado ja existe: $RESULT_BAG" >&2
  echo "Escolha outro nome para preservar a execucao anterior." >&2
  exit 1
fi

if rosnode list >/dev/null 2>&1; then
  echo "ERRO: existe um ROS master ativo. Encerre Gazebo/roscore antes do replay offline." >&2
  exit 1
fi
for dependency in amcl map_server; do
  if ! rospack find "$dependency" >/dev/null 2>&1; then
    echo "ERRO: pacote ROS ausente: $dependency" >&2
    echo "Execute: rosrun $PACKAGE check_dependencies.sh --install" >&2
    exit 1
  fi
done

BAG_INFO=$(rosbag info --yaml "$INPUT_BAG") || {
  echo "ERRO: a bag de localizacao nao pode ser lida: $INPUT_BAG" >&2
  exit 1
}
required_topics=(/clock /front/scan /tf /tf_static /odometry/filtered /gazebo_ground_truth/odom)
for topic in "${required_topics[@]}"; do
  if ! grep -Eq "^[[:space:]]*-[[:space:]]+topic:[[:space:]]+${topic}[[:space:]]*$" <<<"$BAG_INFO"; then
    echo "ERRO: topico obrigatorio ausente na bag de localizacao: $topic" >&2
    exit 1
  fi
done
for forbidden_topic in /map /amcl_pose; do
  if grep -Eq "^[[:space:]]*-[[:space:]]+topic:[[:space:]]+${forbidden_topic}[[:space:]]*$" <<<"$BAG_INFO"; then
    echo "ERRO: a bag de entrada contem $forbidden_topic; use uma bag gravada sem localizacao online." >&2
    exit 1
  fi
done

LOG_FILE="$RESULT_DIR/amcl_${METHOD}.log"
RECORDER_LOG="$RESULT_DIR/amcl_${METHOD}_recorder.log"
echo "Carregando mapa $METHOD e iniciando AMCL..."
roslaunch "$PACKAGE" amcl_offline.launch \
  map_file:="$MAP_FILE" \
  initial_pose_x:="$INITIAL_X" \
  initial_pose_y:="$INITIAL_Y" \
  initial_pose_a:="$INITIAL_YAW" \
  >"$LOG_FILE" 2>&1 &
LAUNCH_PID=$!

ready=false
for _ in $(seq 1 30); do
  if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
    echo "ERRO: map_server/AMCL encerrou. Consulte $LOG_FILE" >&2
    exit 1
  fi
  nodes=$(rosnode list 2>/dev/null || true)
  if grep -qx /map_server <<<"$nodes" && grep -qx /amcl <<<"$nodes"; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "ERRO: map_server e AMCL nao iniciaram em 30 s. Consulte $LOG_FILE" >&2
  exit 1
fi

echo "Iniciando gravacao do resultado: $RESULT_BAG"
rosbag record --lz4 -O "$RESULT_BAG" \
  /clock /map /map_metadata /initialpose /amcl_pose /particlecloud \
  /tf /tf_static /odometry/filtered /husky_velocity_controller/odom \
  /gazebo_ground_truth/odom \
  __name:=record_amcl_result >"$RECORDER_LOG" 2>&1 &
RECORDER_PID=$!

recorder_ready=false
for _ in $(seq 1 15); do
  if rosnode list 2>/dev/null | grep -qx /record_amcl_result; then
    recorder_ready=true
    break
  fi
  sleep 1
done
if [[ "$recorder_ready" != true ]]; then
  echo "ERRO: gravador do resultado nao iniciou. Consulte $RECORDER_LOG" >&2
  exit 1
fi

echo "Reproduzindo a bag de localizacao..."
rosbag play --clock --quiet "$INPUT_BAG" &
PLAY_PID=$!

if ! timeout 15 rostopic echo -n 1 /clock >/dev/null 2>&1; then
  echo "ERRO: /clock nao iniciou durante o replay." >&2
  exit 1
fi
sleep 2

echo "Definindo pose inicial do AMCL em ($INITIAL_X, $INITIAL_Y, $INITIAL_YAW)..."
rostopic pub -1 /initialpose geometry_msgs/PoseWithCovarianceStamped \
  "{header: {frame_id: 'map'}, pose: {pose: {position: {x: $INITIAL_X, y: $INITIAL_Y, z: 0.0}, orientation: {x: 0.0, y: 0.0, z: $INITIAL_QZ, w: $INITIAL_QW}}, covariance: [0.25, 0, 0, 0, 0, 0, 0, 0.25, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0685]}}" \
  >/dev/null

wait "$PLAY_PID"
PLAY_PID=""
sleep 2

stop_process "$RECORDER_PID"
RECORDER_PID=""
if [[ ! -s "$RESULT_BAG" ]]; then
  echo "ERRO: a bag de resultado nao foi criada." >&2
  exit 1
fi

RESULT_INFO=$(rosbag info --yaml "$RESULT_BAG")
for topic in /amcl_pose /gazebo_ground_truth/odom; do
  if ! grep -Eq "^[[:space:]]*-[[:space:]]+topic:[[:space:]]+${topic}[[:space:]]*$" <<<"$RESULT_INFO"; then
    echo "ERRO: resultado sem $topic. Consulte $LOG_FILE" >&2
    exit 1
  fi
done

echo "Localizacao AMCL com mapa $METHOD concluida: $RESULT_BAG"
