#!/usr/bin/env bash
# ==============================================================================
# Instalador e Gerenciador de Serviços Systemd dos Coletores no Host
# ==============================================================================
# Configura e gerencia as unidades systemd locais para manter os coletores
# de métricas (ship-docker-stats.sh) e de eventos (ship-docker-events.sh)
# rodando em background de forma contínua e resiliente.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

STATS_SERVICE="victoria-docker-stats.service"
EVENTS_SERVICE="victoria-docker-events.service"
SYSTEMD_DIR="/etc/systemd/system"

DRY_RUN=false
ACTION=""

usage() {
  cat <<HELP_EOF
Uso: $(basename "$0") [COMANDO] [OPÇÕES]

Comandos:
  -i, --install       Cria, habilita e inicia os serviços systemd dos coletores
  -u, --uninstall     Para, desabilita e remove as unidades dos coletores
  -s, --status        Exibe o status atual das unidades systemd dos coletores
  -h, --help          Exibe esta ajuda e encerra

Opções:
  -d, --dry-run       Apenas exibe as unidades e comandos sem alterar o sistema
HELP_EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--install)
      ACTION="install"
      shift
      ;;
    -u|--uninstall)
      ACTION="uninstall"
      shift
      ;;
    -s|--status)
      ACTION="status"
      shift
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Opção desconhecida: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "${ACTION}" ]]; then
  usage
fi

check_root() {
  if [[ "$DRY_RUN" == false && "$EUID" -ne 0 ]]; then
    echo "❌ Erro: Este comando requer privilégios de superusuário (sudo)." >&2
    echo "Execute: sudo $0 --${ACTION}" >&2
    exit 1
  fi
}

render_stats_unit() {
  cat <<UNIT_EOF
[Unit]
Description=VictoriaLogs Docker Stats Metric Collector
Documentation=https://github.com/ye-sandbox/infra-victoria-logs
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=simple
WorkingDirectory=${ROOT_DIR}
ExecStart=/bin/bash ${ROOT_DIR}/scripts/ship-docker-stats.sh --loop 60
Restart=always
RestartSec=10s
KillMode=process
TimeoutStopSec=10s

# Hardening / Proteções de Recursos
MemoryMax=40M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
UNIT_EOF
}

render_events_unit() {
  cat <<UNIT_EOF
[Unit]
Description=VictoriaLogs Docker Daemon Events Collector
Documentation=https://github.com/ye-sandbox/infra-victoria-logs
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=simple
WorkingDirectory=${ROOT_DIR}
ExecStart=/bin/bash ${ROOT_DIR}/scripts/ship-docker-events.sh
Restart=always
RestartSec=5s
KillMode=process
TimeoutStopSec=5s

# Hardening / Proteções de Recursos
MemoryMax=40M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
UNIT_EOF
}

case "${ACTION}" in
  install)
    check_root
    echo "================================================================================"
    echo "📦 Instalando unidades systemd dos coletores de observabilidade..."
    echo "================================================================================"

    if [[ "$DRY_RUN" == true ]]; then
      echo -e "\n--- [DRY-RUN] ${SYSTEMD_DIR}/${STATS_SERVICE} ---"
      render_stats_unit
      echo -e "\n--- [DRY-RUN] ${SYSTEMD_DIR}/${EVENTS_SERVICE} ---"
      render_events_unit
      echo -e "\nComandos que seriam executados:"
      echo "  systemctl daemon-reload"
      echo "  systemctl enable --now ${STATS_SERVICE}"
      echo "  systemctl enable --now ${EVENTS_SERVICE}"
    else
      render_stats_unit > "${SYSTEMD_DIR}/${STATS_SERVICE}"
      render_events_unit > "${SYSTEMD_DIR}/${EVENTS_SERVICE}"
      systemctl daemon-reload
      systemctl enable --now "${STATS_SERVICE}"
      systemctl enable --now "${EVENTS_SERVICE}"
      echo "✅ Unidades instaladas e iniciadas com sucesso:"
      echo "   • ${STATS_SERVICE}"
      echo "   • ${EVENTS_SERVICE}"
    fi
    ;;

  uninstall)
    check_root
    echo "================================================================================"
    echo "🗑️  Removendo unidades systemd dos coletores..."
    echo "================================================================================"

    if [[ "$DRY_RUN" == true ]]; then
      echo "Comandos que seriam executados:"
      echo "  systemctl disable --now ${STATS_SERVICE} || true"
      echo "  systemctl disable --now ${EVENTS_SERVICE} || true"
      echo "  rm -f ${SYSTEMD_DIR}/${STATS_SERVICE} ${SYSTEMD_DIR}/${EVENTS_SERVICE}"
      echo "  systemctl daemon-reload"
    else
      systemctl disable --now "${STATS_SERVICE}" 2>/dev/null || true
      systemctl disable --now "${EVENTS_SERVICE}" 2>/dev/null || true
      rm -f "${SYSTEMD_DIR}/${STATS_SERVICE}" "${SYSTEMD_DIR}/${EVENTS_SERVICE}"
      systemctl daemon-reload
      echo "✅ Unidades removidas com sucesso."
    fi
    ;;

  status)
    echo "================================================================================"
    echo "📊 Status dos Coletores de Observabilidade no Host"
    echo "================================================================================"
    if command -v systemctl &>/dev/null; then
      echo -e "\n1️⃣  [Docker Stats]:"
      systemctl status "${STATS_SERVICE}" --no-pager 2>&1 || true
      echo -e "\n2️⃣  [Docker Events]:"
      systemctl status "${EVENTS_SERVICE}" --no-pager 2>&1 || true
    else
      echo "⚠️ 'systemctl' não está disponível neste ambiente."
    fi
    ;;
esac
