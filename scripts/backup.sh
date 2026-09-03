#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs Atomic Backup Script via Native Snapshot API
# ==============================================================================
# Executa snapshot consistente sem parar o banco e sem risco de corrupção
# no HD/SSD, compacta em .tar.gz e rotaciona cópias antigas.
# ==============================================================================

set -euo pipefail

# Diretório raiz do projeto (onde está o docker-compose.yml)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Carregar variáveis do .env se existir
if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "${ROOT_DIR}/.env"
  set +a
fi

VICTORIALOGS_PORT="${VICTORIALOGS_HTTP_PORT:-9428}"
VICTORIALOGS_HOST="127.0.0.1"
VL_BASE_URL="http://${VICTORIALOGS_HOST}:${VICTORIALOGS_PORT}"

BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups}"
RETENTION_COPIES="${BACKUP_RETENTION_COPIES:-7}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/vlogs_snapshot_${TIMESTAMP}.tar.gz"

mkdir -p "${BACKUP_DIR}"

# Configurar autenticação para curl se configurada
CURL_AUTH_OPTS=()
if [[ -n "${VICTORIALOGS_AUTH_USERNAME:-}" ]]; then
  CURL_AUTH_OPTS=(-u "${VICTORIALOGS_AUTH_USERNAME}:${VICTORIALOGS_AUTH_PASSWORD:-}")
fi

echo "================================================================================"
echo "🪵 [VictoriaLogs Backup] Iniciando snapshot atômico..."
echo "================================================================================"

# 1. Verificar se VictoriaLogs está saudável
if ! curl "${CURL_AUTH_OPTS[@]}" -s -f "${VL_BASE_URL}/health" > /dev/null; then
  echo "❌ ERRO: VictoriaLogs não está respondendo em ${VL_BASE_URL}/health."
  echo "Verifique se o container está rodando com 'docker compose ps'."
  exit 1
fi

# 2. Criar snapshot via API nativa do VictoriaLogs
echo "📸 Criando snapshot consistente via API nativa..."
SNAPSHOT_RESPONSE=$(curl "${CURL_AUTH_OPTS[@]}" -s -f "${VL_BASE_URL}/internal/partition/snapshot/create")

# Extrair caminhos dos snapshots (compatível com ou sem python3)
SNAPSHOT_PATHS=$(echo "${SNAPSHOT_RESPONSE}" | python3 -c "import sys, json; [print(p) for p in json.load(sys.stdin)]" 2>/dev/null || echo "${SNAPSHOT_RESPONSE}" | grep -o '"/[^"]*"' | tr -d '"')

if [[ -z "${SNAPSHOT_PATHS}" ]]; then
  echo "⚠️  Nenhum snapshot retornado pela API (pode não haver dados persistidos ainda)."
  exit 0
fi

echo "✅ Snapshot(s) criado(s) com sucesso:"
echo "${SNAPSHOT_PATHS}"

# 3. Compactar snapshots usando docker cp (compatível com imagem scratch do VictoriaLogs)
echo "📦 Compactando snapshots para ${BACKUP_FILE}..."
TMP_BACKUP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_BACKUP_DIR}"' EXIT

while IFS= read -r snap_path; do
  [[ -z "${snap_path}" ]] && continue
  rel_dir="${snap_path#/victoria-logs-data/}"
  target_dir="${TMP_BACKUP_DIR}/$(dirname "${rel_dir}")"
  mkdir -p "${target_dir}"
  docker cp "victorialogs:${snap_path}" "${target_dir}/"
done <<< "${SNAPSHOT_PATHS}"

tar -czf "${BACKUP_FILE}" -C "${TMP_BACKUP_DIR}" .

# Validar se o arquivo de backup foi gerado e não está vazio
if [[ ! -s "${BACKUP_FILE}" ]]; then
  echo "❌ ERRO: Falha ao gerar o arquivo compactado ${BACKUP_FILE}."
  exit 1
fi

BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
echo "✅ Arquivo gerado com sucesso: ${BACKUP_FILE} (${BACKUP_SIZE})"

# 4. Excluir os snapshots temporários do disco para liberar espaço
echo "🧹 Removendo snapshots temporários do VictoriaLogs..."
while IFS= read -r snap_path; do
  [[ -z "${snap_path}" ]] && continue
  curl "${CURL_AUTH_OPTS[@]}" -s -f "${VL_BASE_URL}/internal/partition/snapshot/delete?path=${snap_path}" > /dev/null || true
done <<< "${SNAPSHOT_PATHS}"

# 5. Rotação de backups antigos (mantém as últimas N cópias)
echo "♻️  Aplicando política de retenção (mantendo as últimas ${RETENTION_COPIES} cópias)..."
TOTAL_BACKUPS=$(find "${BACKUP_DIR}" -maxdepth 1 -name "vlogs_snapshot_*.tar.gz" | wc -l)

if (( TOTAL_BACKUPS > RETENTION_COPIES )); then
  EXCESS=$(( TOTAL_BACKUPS - RETENTION_COPIES ))
  find "${BACKUP_DIR}" -maxdepth 1 -name "vlogs_snapshot_*.tar.gz" | sort | head -n "${EXCESS}" | while read -r old_backup; do
    echo "   🗑️  Removendo cópia antiga: $(basename "${old_backup}")"
    rm -f "${old_backup}"
  done
fi

echo "================================================================================"
echo "🎉 Backup concluído com sucesso em: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================================"
