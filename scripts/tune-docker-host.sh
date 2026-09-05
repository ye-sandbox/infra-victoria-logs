#!/usr/bin/env bash
# ==============================================================================
# Docker Host Log Tuning — Mode Non-Blocking for HDD Protection
# ==============================================================================
# Este script verifica ou configura o daemon do Docker (/etc/docker/daemon.json)
# para operar com driver de log em modo não-bloqueante (mode: non-blocking).
#
# Benefício:
# - Desacopla a execução dos containers da latência do disco mecânico (HD).
# - Se o HD entrar em I/O Wait alto, os containers não congelam aguardando escrita.
#
# Uso:
#   sudo ./scripts/tune-docker-host.sh --check      (Verifica status atual)
#   sudo ./scripts/tune-docker-host.sh --dry-run    (Mostra o que seria alterado)
#   sudo ./scripts/tune-docker-host.sh --apply      (Aplica alteração com backup)
# ==============================================================================

set -euo pipefail

TARGET_FILE="${DAEMON_JSON_PATH:-/etc/docker/daemon.json}"
ACTION="${1:---check}"

# Cores para saída amigável
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
  cat <<EOF
Uso: $0 [OPÇÃO]

Opções:
  --check     Verifica se o Docker daemon já está otimizado (não altera nada)
  --dry-run   Exibe a prévia do JSON gerado sem modificar nenhum arquivo
  --apply     Aplica a otimização em ${TARGET_FILE} (cria backup automático)
  -h, --help  Exibe esta mensagem de ajuda

Exemplo:
  sudo $0 --apply
EOF
}

check_status() {
  echo -e "${BLUE}🔍 Verificando configuração em:${NC} ${TARGET_FILE}"
  
  if [[ ! -f "${TARGET_FILE}" ]]; then
    echo -e "${YELLOW}⚠️  O arquivo ${TARGET_FILE} não existe.${NC} O Docker está usando defaults padrão (blocking)."
    echo -e "   Para aplicar as otimizações para HD, execute: ${GREEN}sudo $0 --apply${NC}"
    return 1
  fi

  python3 -c "
import sys, json

try:
    with open('${TARGET_FILE}', 'r') as f:
        data = json.load(f)
except Exception as e:
    print('${RED}❌ Erro ao ler JSON:${NC}', e)
    sys.exit(2)

log_opts = data.get('log-opts', {})
mode = log_opts.get('mode')
buf = log_opts.get('max-buffer-size')
driver = data.get('log-driver', 'json-file (default)')

print(f'  • Log Driver: {driver}')
print(f'  • Mode: {mode if mode else \"blocking (default síncrono)\"}')
print(f'  • Buffer: {buf if buf else \"não configurado\"}')

if mode == 'non-blocking':
    print('\n${GREEN}✅ EXCELENTE:${NC} O Docker Daemon já está configurado em modo non-blocking!')
    sys.exit(0)
else:
    print('\n${YELLOW}⚠️  ATENÇÃO:${NC} O Docker está em modo síncrono (blocking).')
    print('   Em HDs mecânicos com I/O wait, isso pode atrasar a execução dos containers.')
    print('   Execute: ${GREEN}sudo $0 --apply${NC} para otimizar.')
    sys.exit(1)
"
}

generate_optimized_json() {
  python3 -c "
import sys, json

target = '${TARGET_FILE}'
data = {}
try:
    with open(target, 'r') as f:
        data = json.load(f)
except FileNotFoundError:
    pass
except Exception as e:
    sys.stderr.write(f'Erro ao carregar JSON existente: {e}\n')
    sys.exit(1)

if 'log-driver' not in data:
    data['log-driver'] = 'json-file'

if 'log-opts' not in data or not isinstance(data['log-opts'], dict):
    data['log-opts'] = {}

opts = data['log-opts']
if 'max-size' not in opts:
    opts['max-size'] = '10m'
if 'max-file' not in opts:
    opts['max-file'] = '3'

opts['mode'] = 'non-blocking'
opts['max-buffer-size'] = '4m'

print(json.dumps(data, indent=2, sort_keys=True))
"
}

apply_changes() {
  if [[ "$(id -u)" -ne 0 && "${TARGET_FILE}" == "/etc/docker/daemon.json" ]]; then
    echo -e "${RED}❌ Permissão negada.${NC} Esta operação exige privilégios de superusuário (root)."
    echo -e "Execute: ${GREEN}sudo $0 --apply${NC}"
    exit 1
  fi

  local TARGET_DIR
  TARGET_DIR="$(dirname "${TARGET_FILE}")"
  mkdir -p "${TARGET_DIR}"

  if [[ -f "${TARGET_FILE}" ]]; then
    local BACKUP_FILE="${TARGET_FILE}.bak.$(date '+%Y%m%d_%H%M%S')"
    echo -e "${BLUE}📦 Criando backup de segurança:${NC} ${BACKUP_FILE}"
    cp "${TARGET_FILE}" "${BACKUP_FILE}"
  fi

  echo -e "${BLUE}⚙️  Gerando e aplicando nova configuração em:${NC} ${TARGET_FILE}"
  local NEW_CONTENT
  NEW_CONTENT="$(generate_optimized_json)"

  # Gravar de forma atômica
  local TEMP_FILE="${TARGET_FILE}.tmp.$$"
  echo "${NEW_CONTENT}" > "${TEMP_FILE}"
  mv "${TEMP_FILE}" "${TARGET_FILE}"

  echo -e "${GREEN}✅ Configuração aplicada com sucesso!${NC}"
  echo ""
  echo "Conteúdo atualizado:"
  cat "${TARGET_FILE}"
  echo ""
  echo -e "${YELLOW}🔔 Próximo passo obrigatório:${NC}"
  echo "Recarregue o daemon do Docker para aplicar as configurações sem derrubar containers:"
  echo -e "   ${GREEN}sudo systemctl reload docker${NC}"
  echo ""
  echo "(Ou reinicie o serviço se preferir: sudo systemctl restart docker)"
}

case "${ACTION}" in
  --check)
    check_status
    ;;
  --dry-run)
    echo -e "${BLUE}📄 Prévia da configuração recomendada para:${NC} ${TARGET_FILE}"
    generate_optimized_json
    ;;
  --apply)
    apply_changes
    ;;
  -h|--help)
    show_help
    ;;
  *)
    echo -e "${RED}Opção inválida:${NC} ${ACTION}"
    show_help
    exit 1
    ;;
esac
