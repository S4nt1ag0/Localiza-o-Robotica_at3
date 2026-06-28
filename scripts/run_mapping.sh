#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || "${1:-}" != "hector" && "${1:-}" != "gmapping" ]]; then
  echo "Uso: $0 {hector|gmapping} [arquivo.bag] [diretorio_saida]" >&2
  exit 2
fi

METHOD=$1
PACKAGE=localiza_o_robotica_at3
PACKAGE_DIR=$(rospack find "$PACKAGE") || {
  echo "ERRO: pacote $PACKAGE nao encontrado. Compile e carregue o workspace." >&2
  exit 1
}
BAG="${2:-$PACKAGE_DIR/bags/lar_mapping.bag}"
OUTPUT_DIR="${3:-$PACKAGE_DIR/maps/$METHOD}"
MAP_PREFIX="$OUTPUT_DIR/lar_${METHOD}"
LAUNCH_PID=""

cleanup() {
  if [[ -n "$LAUNCH_PID" ]] && kill -0 "$LAUNCH_PID" 2>/dev/null; then
    kill -INT "$LAUNCH_PID" 2>/dev/null || true
    wait "$LAUNCH_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if [[ ! -r "$BAG" ]]; then
  echo "ERRO: bag inexistente ou ilegivel: $BAG" >&2
  exit 1
fi

if rosnode list >/dev/null 2>&1; then
  echo "ERRO: existe um ROS master ativo. Encerre Gazebo/roscore antes do replay offline." >&2
  exit 1
fi

case "$METHOD" in
  hector)
    REQUIRED_PACKAGE=hector_mapping
    REQUIRED_NODE=/hector_mapping
    LAUNCH_FILE=hector_offline.launch
    ;;
  gmapping)
    REQUIRED_PACKAGE=gmapping
    REQUIRED_NODE=/slam_gmapping
    LAUNCH_FILE=gmapping_offline.launch
    ;;
esac

for dependency in "$REQUIRED_PACKAGE" map_server; do
  if ! rospack find "$dependency" >/dev/null 2>&1; then
    echo "ERRO: pacote ROS ausente: $dependency" >&2
    echo "Execute: rosrun $PACKAGE check_dependencies.sh --install" >&2
    exit 1
  fi
done

if ! command -v convert >/dev/null 2>&1; then
  echo "ERRO: ImageMagick ausente (comando convert)." >&2
  echo "Execute: rosrun $PACKAGE check_dependencies.sh --install" >&2
  exit 1
fi

BAG_INFO=$(rosbag info --yaml "$BAG") || {
  echo "ERRO: a bag nao pode ser lida: $BAG" >&2
  exit 1
}
required_topics=(/clock /front/scan /tf /tf_static)
if [[ "$METHOD" == "gmapping" ]]; then
  required_topics+=(/odometry/filtered)
fi
for topic in "${required_topics[@]}"; do
  if ! grep -Eq "^[[:space:]]*-[[:space:]]+topic:[[:space:]]+${topic}[[:space:]]*$" <<<"$BAG_INFO"; then
    echo "ERRO: topico obrigatorio ausente na bag: $topic" >&2
    exit 1
  fi
done
if grep -Eq "^[[:space:]]*-[[:space:]]+topic:[[:space:]]+/map[[:space:]]*$" <<<"$BAG_INFO"; then
  echo "ERRO: a bag contem /map e pode ter sido gravada com SLAM online." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
echo "Iniciando $METHOD com tempo simulado..."
roslaunch "$PACKAGE" "$LAUNCH_FILE" >"$OUTPUT_DIR/${METHOD}.log" 2>&1 &
LAUNCH_PID=$!

ready=false
for _ in $(seq 1 30); do
  if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
    echo "ERRO: o launch do $METHOD encerrou. Consulte $OUTPUT_DIR/${METHOD}.log" >&2
    exit 1
  fi
  if rosnode list 2>/dev/null | grep -qx "$REQUIRED_NODE"; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "ERRO: $REQUIRED_NODE nao iniciou em 30 s." >&2
  exit 1
fi

echo "Reproduzindo integralmente: $BAG"
rosbag play --clock --quiet "$BAG"

service_ready=false
for _ in $(seq 1 20); do
  if rosservice list 2>/dev/null | grep -qx /dynamic_map; then
    service_ready=true
    break
  fi
  sleep 1
done
if [[ "$service_ready" != true ]]; then
  echo "ERRO: servico /dynamic_map indisponivel apos o replay." >&2
  exit 1
fi

echo "Salvando mapa em: $MAP_PREFIX.{pgm,yaml}"
rosrun map_server map_saver -f "$MAP_PREFIX" map:=/map
if [[ ! -s "${MAP_PREFIX}.pgm" || ! -s "${MAP_PREFIX}.yaml" ]]; then
  echo "ERRO: map_server nao gerou os arquivos esperados." >&2
  exit 1
fi

echo "Convertendo mapa para PNG..."
convert -limit thread 1 "${MAP_PREFIX}.pgm" "${MAP_PREFIX}.png"
if [[ ! -s "${MAP_PREFIX}.png" ]]; then
  echo "ERRO: ImageMagick nao gerou ${MAP_PREFIX}.png" >&2
  exit 1
fi

echo "Mapa $METHOD gerado com sucesso:"
echo "  ROS:    ${MAP_PREFIX}.yaml"
echo "  Imagem: ${MAP_PREFIX}.png"
