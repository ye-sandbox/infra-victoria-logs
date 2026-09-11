#!/usr/bin/env bash
# ==============================================================================
# Script de Download / Atualização do MaxMind GeoLite2-City (.mmdb)
# ==============================================================================
# Baixa o banco de dados gratuito GeoLite2 City da MaxMind para uso com o
# perfil de enriquecimento GeoIP do Vector (vector/vector.geoip.yaml).
#
# Uso:
#   ./scripts/download-geolite2.sh [--license-key <CHAVE>] [--output-dir <CAMINHO>]
#
# Se nenhuma chave for fornecida via parâmetro ou variável MAXMIND_LICENSE_KEY,
# o script utiliza o espelho público do GitHub mantido pela comunidade (P3TERX/GeoLite.mmdb).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_DIR="${ROOT_DIR}/vector"
LICENSE_KEY="${MAXMIND_LICENSE_KEY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --license-key|-k)
      LICENSE_KEY="$2"
      shift 2
      ;;
    --output-dir|-o)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --help|-h)
      echo "Uso: $0 [--license-key <CHAVE>] [--output-dir <CAMINHO>]"
      exit 0
      ;;
    *)
      echo "Opção desconhecida: $1"
      exit 1
      ;;
  esac
done

TARGET_FILE="${OUTPUT_DIR}/GeoLite2-City.mmdb"
mkdir -p "${OUTPUT_DIR}"

echo "================================================================================"
echo "🌍 [GeoLite2 Downloader] Atualizando banco de geolocalização MaxMind..."
echo "================================================================================"

if [[ -n "${LICENSE_KEY}" ]]; then
  echo "📥 Baixando diretamente da MaxMind usando sua License Key..."
  DOWNLOAD_URL="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=${LICENSE_KEY}&suffix=tar.gz"
  
  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "${TMP_DIR}"' EXIT
  
  curl -sSL "${DOWNLOAD_URL}" | tar -xz -C "${TMP_DIR}"
  find "${TMP_DIR}" -name "GeoLite2-City.mmdb" -exec cp {} "${TARGET_FILE}" \;
else
  echo "ℹ️ Nenhuma MAXMIND_LICENSE_KEY configurada. Utilizando espelho público automatizado..."
  MIRROR_URL="https://raw.githubusercontent.com/P3TERX/GeoLite.mmdb/download/GeoLite2-City.mmdb"
  curl -sSL "${MIRROR_URL}" -o "${TARGET_FILE}"
fi

FILE_SIZE=$(du -h "${TARGET_FILE}" | cut -f1)
echo "✅ Banco GeoLite2 City salvo com sucesso em: ${TARGET_FILE} (${FILE_SIZE})"
echo ""
echo "🚀 Para utilizar o perfil GeoIP no Docker Compose:"
echo "   1. No seu .env, defina: STORAGE_PROFILE=geoip"
echo "   2. Reinicie a stack: docker compose up -d"
echo "================================================================================"
