#!/usr/bin/env bash
set -euo pipefail

PACKAGE=localiza_o_robotica_at3
PACKAGE_DIR=$(rospack find "$PACKAGE") || {
  echo "ERRO: pacote $PACKAGE nao encontrado. Compile e carregue o workspace." >&2
  exit 1
}
BAG="${1:-$PACKAGE_DIR/bags/lar_mapping.bag}"

if [[ "$BAG" != *.bag ]]; then
  BAG="${BAG}.bag"
fi
mkdir -p "$(dirname "$BAG")"

if [[ -e "$BAG" || -e "${BAG}.active" ]]; then
  echo "ERRO: arquivo ja existe: $BAG" >&2
  echo "Escolha outro nome ou remova o arquivo conscientemente." >&2
  exit 1
fi

echo "Gravando em: $BAG"
echo "Conduza o Husky pelo laboratorio e pressione Ctrl+C quando terminar."
exec roslaunch "$PACKAGE" record_mapping.launch bag:="$BAG"
