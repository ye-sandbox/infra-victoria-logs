#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs — Verificação de Crescimento em Disco e Alerta Periódico
# ==============================================================================
# Inspeciona periodicamente a taxa de ingestão diária de dados nas partições
# e a porcentagem de espaço livre no disco do host.
#
# Em caso de anomalia (estouro de volume diário ou disco quase cheio):
# - Emite log de alerta estruturado para o coletor Vector (porta 8686).
# - Opcionalmente notifica webhook externo (se configurado).
#
# Uso:
#   ./scripts/check-disk-growth.sh [--threshold-daily-mb <N>] [--min-free-disk-percent <N>] [--dry-run]
#   ./scripts/check-disk-growth.sh --install-cron
#   ./scripts/check-disk-growth.sh --uninstall-cron
#   ./scripts/check-disk-growth.sh --status-cron
# ==============================================================================

set -euo pipefail

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
HOST="${VICTORIALOGS_HOST:-127.0.0.1}"
VL_URL="${VICTORIALOGS_URL:-http://${HOST}:${VICTORIALOGS_PORT}}"
VECTOR_HTTP_PORT="${VECTOR_HTTP_PORT:-8686}"
VECTOR_URL="http://127.0.0.1:${VECTOR_HTTP_PORT}/logs"

# Limiares de alerta padrão
THRESHOLD_DAILY_MB="${DISK_ALERT_THRESHOLD_DAILY_MB:-1000}"   # Alerta se último dia > 1000 MB (1 GB)
MIN_FREE_PERCENT="${DISK_ALERT_MIN_FREE_PERCENT:-10}"         # Alerta se disco livre < 10%
DRY_RUN=false
WEBHOOK_URL="${DISK_ALERT_WEBHOOK_URL:-}"

# Parse de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold-daily-mb)
      THRESHOLD_DAILY_MB="$2"
      shift 2
      ;;
    --min-free-disk-percent)
      MIN_FREE_PERCENT="$2"
      shift 2
      ;;
    --webhook)
      WEBHOOK_URL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --install-cron)
      CRON_CMD="0 6 * * * ${ROOT_DIR}/scripts/check-disk-growth.sh >/dev/null 2>&1"
      (crontab -l 2>/dev/null | grep -Fv "check-disk-growth.sh" || true; echo "${CRON_CMD}") | crontab -
      echo "✅ Agendamento adicionado ao crontab com sucesso (execução diária às 06:00 UTC):"
      echo "   ${CRON_CMD}"
      exit 0
      ;;
    --uninstall-cron)
      crontab -l 2>/dev/null | grep -Fv "check-disk-growth.sh" | crontab - || true
      echo "✅ Agendamento de check-disk-growth.sh removido do crontab."
      exit 0
      ;;
    --status-cron)
      echo "📋 Agendamentos relacionados a check-disk-growth.sh no crontab atual:"
      crontab -l 2>/dev/null | grep "check-disk-growth.sh" || echo "   (Nenhum agendamento encontrado)"
      exit 0
      ;;
    -h|--help)
      echo "Uso: $0 [OPÇÕES]"
      echo "  --threshold-daily-mb N      Limiar de volume diário em MB para alerta (padrão: 1000 MB)"
      echo "  --min-free-disk-percent N   Porcentagem mínima de espaço livre no disco (padrão: 10%)"
      echo "  --webhook URL               URL de webhook para alerta em caso de violação"
      echo "  --dry-run                   Executa a checagem sem enviar logs de alerta"
      echo "  --install-cron              Registra no crontab para rodar diariamente às 06:00"
      echo "  --uninstall-cron            Remove agendamento do crontab"
      echo "  --status-cron               Exibe agendamento ativo no crontab"
      exit 0
      ;;
    *)
      echo "Opção desconhecida: $1"
      exit 1
      ;;
  esac
done

echo "================================================================================"
echo "🔍 [VictoriaLogs Storage Health] Checagem de Taxa de Ingestão e Disco"
echo "================================================================================"

# 1. Verificar Espaço em Disco no Host
DISK_USAGE_RAW=$(df -h / | tail -1)
DISK_USED_PCT=$(echo "${DISK_USAGE_RAW}" | awk '{print $5}' | tr -d '%')
DISK_FREE_PCT=$((100 - DISK_USED_PCT))
DISK_AVAIL=$(echo "${DISK_USAGE_RAW}" | awk '{print $4}')
DISK_TOTAL=$(echo "${DISK_USAGE_RAW}" | awk '{print $2}')

echo "💾 Disco do Host: ${DISK_TOTAL} total | ${DISK_AVAIL} disponível | ${DISK_FREE_PCT}% livre (Usado: ${DISK_USED_PCT}%)"

# 2. Inspecionar Última Partição do VictoriaLogs
USAGE_RAW=$(docker run --rm \
  --name "victorialogs-disk-inspector-$$" \
  --label "app=infra-victoria-logs" \
  --label "component=maintenance" \
  -v victorialogs_data:/data:ro \
  alpine sh -c "du -m -d 1 /data/partitions 2>/dev/null" || true)

CHECK_RESULT=$(python3 -c "
import sys, json

usage_text = '''${USAGE_RAW}'''
latest_mb = 0.0
total_mb = 0.0
partitions = []

for line in usage_text.strip().split('\n'):
    parts = line.split()
    if len(parts) == 2:
        sz_mb = float(parts[0])
        p_name = parts[1].rstrip('/').split('/')[-1]
        if p_name == 'partitions':
            total_mb = sz_mb
        else:
            partitions.append((p_name, sz_mb))

partitions.sort(key=lambda x: x[0])
if partitions:
    latest_mb = partitions[-1][1]
    latest_name = partitions[-1][0]
else:
    latest_name = 'Nenhuma'

threshold = float(${THRESHOLD_DAILY_MB})
min_free = float(${MIN_FREE_PERCENT})
disk_free = float(${DISK_FREE_PCT})

alerts = []
if latest_mb > threshold:
    alerts.append(f'Taxa de ingestao anomala na particao {latest_name}: {latest_mb:.1f} MB (limiar: {threshold:.0f} MB)')

if disk_free < min_free:
    alerts.append(f'Espaco em disco critico: apenas {disk_free:.0f}% livre (limiar de seguranca: {min_free:.0f}%)')

res = {
    'total_mb': total_mb,
    'latest_name': latest_name,
    'latest_mb': latest_mb,
    'alerts': alerts,
    'has_alert': len(alerts) > 0
}
print(json.dumps(res))
")

LATEST_NAME=$(echo "${CHECK_RESULT}" | python3 -c "import sys, json; print(json.load(sys.stdin)['latest_name'])")
LATEST_MB=$(echo "${CHECK_RESULT}" | python3 -c "import sys, json; print(json.load(sys.stdin)['latest_mb'])")
TOTAL_MB=$(echo "${CHECK_RESULT}" | python3 -c "import sys, json; print(json.load(sys.stdin)['total_mb'])")
HAS_ALERT=$(echo "${CHECK_RESULT}" | python3 -c "import sys, json; print(json.load(sys.stdin)['has_alert'])")

echo "📦 Partição Mais Recente: ${LATEST_NAME} (${LATEST_MB} MB comprimido)"
echo "📊 Tamanho Total das Partições: ${TOTAL_MB} MB"

if [[ "${HAS_ALERT}" == "True" ]]; then
  echo ""
  echo "⚠️ ALERTA DE CAPACIDADE DETECTADO:"
  echo "${CHECK_RESULT}" | python3 -c "
import sys, json
for a in json.load(sys.stdin)['alerts']:
    print(f' 🚨 {a}')
"
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "🔍 [DRY-RUN] Nenhuma notificação emitida."
    exit 0
  fi

  # Envia log estruturado de alerta para o coletor Vector
  ALERT_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'service': 'storage-capacity-monitor',
    'app': 'infra-victoria-logs',
    'env': 'production',
    'level': 'error',
    'message': 'Alerta de capacidade em disco no VictoriaLogs',
    'host_disk_free_percent': ${DISK_FREE_PCT},
    'latest_partition': '${LATEST_NAME}',
    'latest_partition_mb': ${LATEST_MB},
    'total_partitions_mb': ${TOTAL_MB}
}))
")

  echo "📤 Emitindo evento de alerta para o pipeline Vector (${VECTOR_URL})..."
  curl -s -X POST "${VECTOR_URL}" \
    -H "Content-Type: application/json" \
    -d "${ALERT_PAYLOAD}" || true

  # Notifica webhook se presente
  if [[ -n "${WEBHOOK_URL}" ]]; then
    echo "📤 Enviando alerta para webhook..."
    curl -s -X POST "${WEBHOOK_URL}" \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"🚨 Alerta VictoriaLogs: ${LATEST_NAME} consumiu ${LATEST_MB}MB | Disco livre: ${DISK_FREE_PCT}%\"}" || true
  fi

  echo "================================================================================"
  exit 1
else
  echo ""
  echo "✅ Tudo em ordem! Ingestão dentro dos parâmetros normais (< ${THRESHOLD_DAILY_MB} MB/dia)."
  echo "================================================================================"
  exit 0
fi
