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

# 2. Criar snapshot via API nativa
echo "📸 Criando snapshot consistente via API nativa..."
SNAPSHOT_RESPONSE=$(curl "${CURL_AUTH_OPTS[@]}" -s -f -X POST "${VL_BASE_URL}/snapshot/create")

# Extrair o nome do snapshot (compatível com ou sem jq)
SNAPSHOT_NAME=$(echo "${SNAPSHOT_RESPONSE}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('snapshot', ''))" 2>/dev/null || true)

if [[ -z "${SNAPSHOT_NAME}" ]]; then
  # Fallback caso python3 falhe
  SNAPSHOT_NAME=$(echo "${SNAPSHOT_RESPONSE}" | grep -o '"snapshot":"[^"]*"' | cut -d'"' -f4)
fi

if [[ -z "${SNAPSHOT_NAME}" ]]; then
  echo "❌ ERRO ao criar snapshot. Resposta da API: ${SNAPSHOT_RESPONSE}"
  exit 1
fi

echo "✅ Snapshot criado com sucesso: ${SNAPSHOT_NAME}"

# 3. Compactar o snapshot diretamente do container
echo "📦 Compactando snapshot para ${BACKUP_FILE}..."
cd "${ROOT_DIR}"
docker compose exec -T victorialogs tar -czf - -C "/victoria-logs-data/snapshots/${SNAPSHOT_NAME}" . > "${BACKUP_FILE}"

# Validar se o arquivo de backup foi gerado e não está vazio
if [[ ! -s "${BACKUP_FILE}" ]]; then
  echo "❌ ERRO: Falha ao gerar o arquivo compactado ${BACKUP_FILE}."
  exit 1
fi

BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
echo "✅ Arquivo gerado com sucesso: ${BACKUP_FILE} (${BACKUP_SIZE})"

# 4. Excluir o snapshot do disco para liberar espaço
echo "🧹 Removendo snapshot temporário do VictoriaLogs..."
curl "${CURL_AUTH_OPTS[@]}" -s -f -X POST "${VL_BASE_URL}/snapshot/delete?snapshot=${SNAPSHOT_NAME}" > /dev/null || true

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
