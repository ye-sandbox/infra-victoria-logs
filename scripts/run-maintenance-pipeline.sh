#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs & Vector — Pipeline Automatizado de Manutenção Periódica
# ==============================================================================
# Orquestra as rotinas essenciais de confiabilidade e governança da stack:
# 1. Checagem prévia de disco e taxa de ingestão (scripts/check-disk-growth.sh)
# 2. Snapshot consistente com rotação atômica (scripts/backup.sh)
# 3. Smoke test ponta a ponta de ingestão e LogsQL (scripts/test-pipeline.sh)
# 4. Emissão de log de auditoria estruturado para o pipeline do Vector
#
# Uso:
#   ./scripts/run-maintenance-pipeline.sh [--dry-run]
#   ./scripts/run-maintenance-pipeline.sh --install-cron
#   ./scripts/run-maintenance-pipeline.sh --uninstall-cron
#   ./scripts/run-maintenance-pipeline.sh --status-cron
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

VECTOR_HTTP_PORT="${VECTOR_HTTP_PORT:-8686}"
VECTOR_URL="http://127.0.0.1:${VECTOR_HTTP_PORT}/logs"

DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --install-cron)
      CRON_CMD="0 3 * * * ${ROOT_DIR}/scripts/run-maintenance-pipeline.sh >/dev/null 2>&1"
      (crontab -l 2>/dev/null | grep -Fv "run-maintenance-pipeline.sh" || true; echo "${CRON_CMD}") | crontab -
      echo "✅ Pipeline de manutenção registrado no crontab com sucesso (execução diária às 03:00 UTC):"
      echo "   ${CRON_CMD}"
      exit 0
      ;;
    --uninstall-cron)
      crontab -l 2>/dev/null | grep -Fv "run-maintenance-pipeline.sh" | crontab - || true
      echo "✅ Agendamento de run-maintenance-pipeline.sh removido do crontab."
      exit 0
      ;;
    --status-cron)
      echo "📋 Agendamentos de manutenção no crontab atual:"
      crontab -l 2>/dev/null | grep "run-maintenance-pipeline.sh" || echo "   (Nenhum agendamento encontrado)"
      exit 0
      ;;
    -h|--help)
      echo "Uso: $0 [OPÇÕES]"
      echo "  --dry-run          Simula as etapas sem executar backups ou testes reais"
      echo "  --install-cron     Agenda no crontab para rodar diariamente às 03:00 UTC"
      echo "  --uninstall-cron   Remove agendamento do crontab"
      echo "  --status-cron      Exibe agendamento ativo no crontab"
      exit 0
      ;;
    *)
      echo "Opção desconhecida: $1"
      exit 1
      ;;
  esac
done

START_TIME=$(date +%s)
echo "================================================================================"
echo "🛡️ [Maintenance Pipeline] Iniciando rotina periódica de manutenção..."
echo "⏰ Horário de início: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "================================================================================"

STATUS_DISK="OK"
STATUS_BACKUP="OK"
STATUS_SMOKE="OK"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "🔍 [DRY-RUN] Simulação de pipeline de manutenção:"
  echo " 1. Checagem de espaço e partições: [SIMULADO]"
  echo " 2. Snapshot atômico de dados:      [SIMULADO]"
  echo " 3. Smoke test ponta a ponta:       [SIMULADO]"
  echo "================================================================================"
  exit 0
fi

# ------------------------------------------------------------------------------
# ETAPA 1: Checagem de Disco e Ingestão
# ------------------------------------------------------------------------------
echo ""
echo "▶️ [Etapa 1/3] Verificando integridade de disco e taxa de ingestão..."
if ! "${ROOT_DIR}/scripts/check-disk-growth.sh"; then
  echo "⚠️ Atenção: A checagem de disco acusou alerta ou atingiu limiar crítico."
  STATUS_DISK="WARNING"
else
  echo "✅ Etapa 1 concluída com sucesso."
fi

# ------------------------------------------------------------------------------
# ETAPA 2: Snapshot Atômico com Rotação
# ------------------------------------------------------------------------------
echo ""
echo "▶️ [Etapa 2/3] Executando snapshot atômico consistente com rotação..."
if ! "${ROOT_DIR}/scripts/backup.sh"; then
  echo "❌ Erro ao executar snapshot do VictoriaLogs!"
  STATUS_BACKUP="FAILED"
else
  echo "✅ Etapa 2 concluída com sucesso."
fi

# ------------------------------------------------------------------------------
# ETAPA 3: Smoke Test de Ingestão e Busca LogsQL
# ------------------------------------------------------------------------------
echo ""
echo "▶️ [Etapa 3/3] Validando fluxo de ingestão e consultas LogsQL..."
if ! "${ROOT_DIR}/scripts/test-pipeline.sh"; then
  echo "❌ Erro no smoke test de ponta a ponta!"
  STATUS_SMOKE="FAILED"
else
  echo "✅ Etapa 3 concluída com sucesso."
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

OVERALL_STATUS="SUCCESS"
if [[ "${STATUS_BACKUP}" == "FAILED" || "${STATUS_SMOKE}" == "FAILED" ]]; then
  OVERALL_STATUS="ERROR"
elif [[ "${STATUS_DISK}" == "WARNING" ]]; then
  OVERALL_STATUS="WARNING"
fi

echo ""
echo "================================================================================"
echo "🏁 [Maintenance Pipeline] Concluído em ${DURATION}s | Status Geral: ${OVERALL_STATUS}"
echo "   - Disco & Ingestão: ${STATUS_DISK}"
echo "   - Snapshot Backup:  ${STATUS_BACKUP}"
echo "   - Smoke Test Logs:  ${STATUS_SMOKE}"
echo "================================================================================"

# Emitir log estruturado consolidado para o Vector
TELEMETRY_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'service': 'maintenance-pipeline',
    'app': 'infra-victoria-logs',
    'env': 'production',
    'level': 'info' if '${OVERALL_STATUS}' == 'SUCCESS' else ('warn' if '${OVERALL_STATUS}' == 'WARNING' else 'error'),
    'message': f'Pipeline de manutencao finalizado com status { \"${OVERALL_STATUS}\" } em { ${DURATION} }s',
    'duration_ms': ${DURATION} * 1000,
    'status_disk': '${STATUS_DISK}',
    'status_backup': '${STATUS_BACKUP}',
    'status_smoke_test': '${STATUS_SMOKE}'
}))
")

curl -s -X POST "${VECTOR_URL}" \
  -H "Content-Type: application/json" \
  -d "${TELEMETRY_PAYLOAD}" >/dev/null 2>&1 || true

exit 0
