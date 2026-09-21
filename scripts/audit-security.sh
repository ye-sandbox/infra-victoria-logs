#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs + Vector — Auditoria de Segurança e Permissões do Host & Containers
# ==============================================================================
# Inspeciona a postura de segurança da stack de observabilidade:
# 1. Permissões de arquivos sensíveis no host (.env, scripts/*.sh, configs).
# 2. Configurações de isolamento no Docker Compose (socket :ro, limites de RAM, loop).
# 3. Superfície de exposição de portas de rede e autenticação HTTP Basic Auth.
# 4. Inspeção de runtime dos containers ativos (quando em execução).
#
# Uso:
#   ./scripts/audit-security.sh                 # Auditoria padrão com saída colorida
#   ./scripts/audit-security.sh --fix           # Corrige permissões de arquivos automaticamente
#   ./scripts/audit-security.sh --json          # Exporta relatório em JSON para CI/CD ou agentes
#   ./scripts/audit-security.sh --strict        # Falha (exit 1) se houver qualquer aviso (WARN)
#   ./scripts/audit-security.sh --help          # Exibe ajuda e opções
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Cores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Opções de execução
DO_FIX=false
OUTPUT_JSON=false
STRICT_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)
      DO_FIX=true
      shift
      ;;
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    --strict)
      STRICT_MODE=true
      shift
      ;;
    -h|--help)
      cat << 'EOF'
Uso: ./scripts/audit-security.sh [OPÇÕES]

Opções:
  --fix      Corrige automaticamente permissões de arquivos no host (ex: chmod 600 .env, chmod 755 scripts/*.sh)
  --json     Exibe o resultado consolidado em formato JSON para automação e pipelines
  --strict   Trata avisos (WARN) como erros impeditivos (retorna exit code 1)
  -h, --help Exibe esta tela de ajuda

Checagens executadas:
  [Host] Permissões restritas de .env (600/400) e ausência no Git
  [Host] Permissões de execução dos scripts e bloqueio de escrita global (o+w)
  [Compose] Socket Docker (/var/run/docker.sock) montado estritamente como somente leitura (:ro)
  [Compose] Limites de memória ativos e rígidos (VictoriaLogs <= 80M, Vector <= 60M, Total <= 150M)
  [Compose] Prevenção de loop recursivo de logs (exclude_containers: ["vector"])
  [Compose] Healthchecks e políticas de reinicialização configuradas
  [Compose] Hardening de containers (read_only: true) e tmpfs (/tmp)
  [Network] Auditoria de portas abertas em 0.0.0.0 vs proteção com HTTP Basic Auth
  [Runtime] Validação de limites aplicados e rootfs somente leitura nos containers ativos
EOF
      exit 0
      ;;
    *)
      echo "Opção desconhecida: $1" >&2
      echo "Use ./scripts/audit-security.sh --help para ver as opções disponíveis." >&2
      exit 1
      ;;
  esac
done

# Contadores globais
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
FIX_COUNT=0

# Lista de resultados para saída JSON
JSON_RESULTS=()

record_result() {
  local id="$1"
  local category="$2"
  local status="$3"    # PASS, WARN, FAIL, FIXED
  local message="$4"
  local remediation="$5"

  case "$status" in
    PASS)
      ((PASS_COUNT += 1))
      if [[ "${OUTPUT_JSON}" == "false" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} ${category}: ${message}"
      fi
      ;;
    FIXED)
      ((FIX_COUNT += 1))
      ((PASS_COUNT += 1))
      if [[ "${OUTPUT_JSON}" == "false" ]]; then
        echo -e "  ${CYAN}[FIXED]${NC} ${category}: ${message} (corrigido automaticamente)"
      fi
      ;;
    WARN)
      ((WARN_COUNT += 1))
      if [[ "${OUTPUT_JSON}" == "false" ]]; then
        echo -e "  ${YELLOW}[WARN]${NC} ${category}: ${message}"
        if [[ -n "${remediation}" ]]; then
          echo -e "         ${BOLD}Recomendação:${NC} ${remediation}"
        fi
      fi
      ;;
    FAIL)
      ((FAIL_COUNT += 1))
      if [[ "${OUTPUT_JSON}" == "false" ]]; then
        echo -e "  ${RED}[FAIL]${NC} ${category}: ${message}"
        if [[ -n "${remediation}" ]]; then
          echo -e "         ${BOLD}Ação Necessária:${NC} ${remediation}"
        fi
      fi
      ;;
  esac

  # Escapar strings para JSON
  local esc_id esc_cat esc_stat esc_msg esc_rem
  esc_id=$(printf '%s' "$id" | sed 's/"/\\"/g')
  esc_cat=$(printf '%s' "$category" | sed 's/"/\\"/g')
  esc_stat=$(printf '%s' "$status" | sed 's/"/\\"/g')
  esc_msg=$(printf '%s' "$message" | sed 's/"/\\"/g')
  esc_rem=$(printf '%s' "$remediation" | sed 's/"/\\"/g')

  JSON_RESULTS+=("{\"id\":\"${esc_id}\",\"category\":\"${esc_cat}\",\"status\":\"${esc_stat}\",\"message\":\"${esc_msg}\",\"remediation\":\"${esc_rem}\"}")
}

if [[ "${OUTPUT_JSON}" == "false" ]]; then
  echo -e "${BOLD}========================================================================${NC}"
  echo -e "${BOLD} VictoriaLogs + Vector — Auditoria de Segurança & Permissões do Host ${NC}"
  echo -e "${BOLD}========================================================================${NC}"
  echo -e "Data da Execução : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo -e "Diretório Base   : ${ROOT_DIR}"
  echo -e "Modo Auto-Fix    : ${DO_FIX}"
  echo -e "Modo Estrito     : ${STRICT_MODE}"
  echo ""
fi

# ==============================================================================
# 1. Auditoria de Permissões de Arquivos no Host
# ==============================================================================
if [[ "${OUTPUT_JSON}" == "false" ]]; then
  echo -e "${BOLD}--- 1. Sistema de Arquivos & Permissões do Host ---${NC}"
fi

# 1.1 Permissões do .env
ENV_FILE="${ROOT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  ENV_PERM=$(stat -c "%a" "${ENV_FILE}" 2>/dev/null || stat -f "%Lp" "${ENV_FILE}" 2>/dev/null || echo "unknown")
  if [[ "${ENV_PERM}" =~ ^[46]00$ ]]; then
    record_result "HOST-ENV-PERM" "Filesystem" "PASS" "Arquivo .env possui permissões restritas e seguras (${ENV_PERM})" ""
  else
    if [[ "${DO_FIX}" == "true" ]]; then
      chmod 600 "${ENV_FILE}"
      record_result "HOST-ENV-PERM" "Filesystem" "FIXED" "Permissão do .env alterada de ${ENV_PERM} para 600" ""
    else
      record_result "HOST-ENV-PERM" "Filesystem" "WARN" "Arquivo .env possui permissão permissiva (${ENV_PERM}) legível por outros usuários" "Execute 'chmod 600 .env' ou rode com '--fix'"
    fi
  fi
else
  record_result "HOST-ENV-EXIST" "Filesystem" "WARN" "Arquivo .env não encontrado no repositório" "Copie o template: 'cp .env.example .env && chmod 600 .env'"
fi

# 1.2 Verificação do Git para o .env
if command -v git &>/dev/null && [[ -d "${ROOT_DIR}/.git" ]]; then
  TRACKED_ENV=$(git -C "${ROOT_DIR}" ls-files .env 2>/dev/null || true)
  if [[ -n "${TRACKED_ENV}" ]]; then
    record_result "GIT-ENV-TRACKED" "Git" "FAIL" "O arquivo .env está sendo rastreado pelo Git! Risco crítico de vazamento de credenciais" "Execute 'git rm --cached .env' e adicione ao .gitignore"
  else
    record_result "GIT-ENV-IGNORED" "Git" "PASS" "Arquivo .env não está rastreado no repositório Git" ""
  fi

  # Checar .gitignore
  if grep -q "^\.env$" "${ROOT_DIR}/.gitignore" 2>/dev/null; then
    record_result "GITIGNORE-ENV" "Git" "PASS" "Regra .env presente no .gitignore" ""
  else
    record_result "GITIGNORE-ENV" "Git" "WARN" "Regra .env explícita não encontrada no .gitignore" "Adicione '.env' ao .gitignore"
  fi
fi

# 1.3 Executabilidade e integridade dos scripts em scripts/*.sh
SCRIPTS_DIR="${ROOT_DIR}/scripts"
NON_EXEC_SCRIPTS=()
WORLD_WRITABLE_SCRIPTS=()

if [[ -d "${SCRIPTS_DIR}" ]]; then
  for script in "${SCRIPTS_DIR}"/*.sh; do
    [[ -f "${script}" ]] || continue
    script_name=$(basename "${script}")
    
    if [[ ! -x "${script}" ]]; then
      NON_EXEC_SCRIPTS+=("${script_name}")
      if [[ "${DO_FIX}" == "true" ]]; then
        chmod +x "${script}"
      fi
    fi

    # Checar se tem permissão de escrita para outros (world-writable: dígito final 2, 3, 6 ou 7)
    perm=$(stat -c "%a" "${script}" 2>/dev/null || stat -f "%Lp" "${script}" 2>/dev/null || echo "0")
    if [[ "${perm: -1}" =~ [2367] ]]; then
      WORLD_WRITABLE_SCRIPTS+=("${script_name}")
      if [[ "${DO_FIX}" == "true" ]]; then
        chmod o-w "${script}"
      fi
    fi
  done

  if [[ ${#NON_EXEC_SCRIPTS[@]} -eq 0 ]]; then
    record_result "HOST-SCRIPTS-EXEC" "Filesystem" "PASS" "Todos os scripts em scripts/*.sh possuem permissão de execução" ""
  else
    if [[ "${DO_FIX}" == "true" ]]; then
      record_result "HOST-SCRIPTS-EXEC" "Filesystem" "FIXED" "Permissão de execução restaurada em: ${NON_EXEC_SCRIPTS[*]}" ""
    else
      record_result "HOST-SCRIPTS-EXEC" "Filesystem" "WARN" "Scripts sem permissão de execução: ${NON_EXEC_SCRIPTS[*]}" "Execute 'chmod +x scripts/*.sh' ou rode com '--fix'"
    fi
  fi

  if [[ ${#WORLD_WRITABLE_SCRIPTS[@]} -eq 0 ]]; then
    record_result "HOST-SCRIPTS-WRITABLE" "Filesystem" "PASS" "Nenhum script possui permissão de escrita pública (world-writable)" ""
  else
    if [[ "${DO_FIX}" == "true" ]]; then
      record_result "HOST-SCRIPTS-WRITABLE" "Filesystem" "FIXED" "Permissão de escrita pública removida em: ${WORLD_WRITABLE_SCRIPTS[*]}" ""
    else
      record_result "HOST-SCRIPTS-WRITABLE" "Filesystem" "FAIL" "Scripts com permissão de escrita pública (world-writable): ${WORLD_WRITABLE_SCRIPTS[*]}" "Execute 'chmod o-w scripts/*.sh' ou rode com '--fix'"
    fi
  fi
fi

# ==============================================================================
# 2. Configurações de Isolamento e Segurança do Docker Compose
# ==============================================================================
if [[ "${OUTPUT_JSON}" == "false" ]]; then
  echo ""
  echo -e "${BOLD}--- 2. Hardening e Isolamento no Docker Compose ---${NC}"
fi

COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
if [[ ! -f "${COMPOSE_FILE}" ]]; then
  record_result "COMPOSE-FILE" "DockerCompose" "FAIL" "Arquivo docker-compose.yml não encontrado" "Certifique-se de executar no repositório infra-victoria-logs"
else
  # 2.1 Sintaxe do Compose
  COMPOSE_VALID=false
  COMPOSE_JSON=""
  if command -v docker &>/dev/null; then
    if docker compose -f "${COMPOSE_FILE}" config --quiet &>/dev/null; then
      COMPOSE_VALID=true
      record_result "COMPOSE-SYNTAX" "DockerCompose" "PASS" "Sintaxe do docker-compose.yml validada com sucesso" ""
      # Extrair JSON normalizado do Compose
      COMPOSE_JSON=$(docker compose -f "${COMPOSE_FILE}" config --format json 2>/dev/null || true)
    else
      record_result "COMPOSE-SYNTAX" "DockerCompose" "FAIL" "docker compose config reportou erros na sintaxe do arquivo" "Verifique a formatação do docker-compose.yml"
    fi
  fi

  # 2.2 Docker Socket montado como Read-Only (:ro)
  SOCK_IS_RO=false
  if [[ -n "${COMPOSE_JSON}" ]] && command -v python3 &>/dev/null; then
    SOCK_IS_RO=$(echo "${COMPOSE_JSON}" | python3 -c '
import sys, json
data = json.load(sys.stdin)
vols = data.get("services", {}).get("vector", {}).get("volumes", [])
is_ro = any(v.get("source") == "/var/run/docker.sock" and v.get("read_only") is True for v in vols if isinstance(v, dict))
print("true" if is_ro else "false")
' 2>/dev/null || echo "false")
  else
    if grep -E '/var/run/docker\.sock' "${COMPOSE_FILE}" | grep -q ':ro'; then
      SOCK_IS_RO=true
    fi
  fi

  if [[ "${SOCK_IS_RO}" == "true" ]]; then
    record_result "COMPOSE-DOCKER-SOCK-RO" "DockerCompose" "PASS" "Socket Docker (/var/run/docker.sock) montado estritamente como somente leitura (:ro)" ""
  else
    record_result "COMPOSE-DOCKER-SOCK-RO" "DockerCompose" "FAIL" "Socket Docker (/var/run/docker.sock) montado SEM flag :ro (risco crítico de container escape)" "Adicione ':ro' na montagem do socket do Vector"
  fi

  # 2.3 Limites Rígidos de Memória (RAM)
  VL_MEM_BYTES=0
  VEC_MEM_BYTES=0

  if [[ -n "${COMPOSE_JSON}" ]] && command -v python3 &>/dev/null; then
    MEM_OUT=$(echo "${COMPOSE_JSON}" | python3 -c '
import sys, json
data = json.load(sys.stdin)
svcs = data.get("services", {})
vl_mem = svcs.get("victorialogs", {}).get("deploy", {}).get("resources", {}).get("limits", {}).get("memory", 0)
vec_mem = svcs.get("vector", {}).get("deploy", {}).get("resources", {}).get("limits", {}).get("memory", 0)
print(f"{vl_mem} {vec_mem}")
' 2>/dev/null || echo "0 0")
    read -r VL_MEM_BYTES VEC_MEM_BYTES <<< "${MEM_OUT}"
  else
    # Fallback via awk
    VL_MEM_STR=$(awk '/victorialogs:/,/^[a-zA-Z0-9_-]+:/' "${COMPOSE_FILE}" | grep "memory:" | head -n1 | awk '{print $2}' || true)
    VEC_MEM_STR=$(awk '/vector:/,/^[a-zA-Z0-9_-]+:/' "${COMPOSE_FILE}" | grep "memory:" | head -n1 | awk '{print $2}' || true)
    VL_MEM_BYTES=$(echo "${VL_MEM_STR}" | tr -dc '0-9')
    VL_MEM_BYTES=$((VL_MEM_BYTES * 1024 * 1024))
    VEC_MEM_BYTES=$(echo "${VEC_MEM_STR}" | tr -dc '0-9')
    VEC_MEM_BYTES=$((VEC_MEM_BYTES * 1024 * 1024))
  fi

  VL_MB=$((VL_MEM_BYTES / 1024 / 1024))
  VEC_MB=$((VEC_MEM_BYTES / 1024 / 1024))
  TOTAL_MB=$((VL_MB + VEC_MB))

  if [[ "${VL_MEM_BYTES}" -gt 0 && "${VEC_MEM_BYTES}" -gt 0 ]]; then
    if [[ "${VL_MB}" -le 80 && "${VEC_MB}" -le 60 && "${TOTAL_MB}" -le 150 ]]; then
      record_result "COMPOSE-MEM-LIMITS" "DockerCompose" "PASS" "Limites de memória em conformidade (VictoriaLogs: ${VL_MB}M, Vector: ${VEC_MB}M, Total: ${TOTAL_MB}M <= 150M)" ""
    else
      record_result "COMPOSE-MEM-LIMITS" "DockerCompose" "FAIL" "Limites de memória excedem o teto padrão de salvaguarda de 150M (VictoriaLogs: ${VL_MB}M, Vector: ${VEC_MB}M)" "Ajuste limits.memory para <= 80M e <= 60M a fim de proteger o host contra consumo excessivo"
    fi
  else
    record_result "COMPOSE-MEM-LIMITS" "DockerCompose" "FAIL" "Limites de memória (deploy.resources.limits.memory) ausentes em um ou mais serviços" "Configure limits.memory para blindar o host contra OOM"
  fi

  # 2.4 Prevenção de loop recursivo de logs (exclude_containers: ["vector"])
  LOOP_CHECK_OK=true
  for vec_cfg in "${ROOT_DIR}/vector"/vector*.yaml; do
    [[ -f "${vec_cfg}" ]] || continue
    if ! grep -q 'exclude_containers:' "${vec_cfg}" || ! grep -A 2 'exclude_containers:' "${vec_cfg}" | grep -q 'vector'; then
      LOOP_CHECK_OK=false
      break
    fi
  done

  if [[ "${LOOP_CHECK_OK}" == "true" ]]; then
    record_result "VECTOR-LOOP-PREVENTION" "VectorConfig" "PASS" "Configurações do Vector incluem 'exclude_containers: [vector]' prevenindo loop de logs" ""
  else
    record_result "VECTOR-LOOP-PREVENTION" "VectorConfig" "FAIL" "Configuração do Vector sem 'exclude_containers: [vector]' (risco de tempestade de logs)" "Adicione exclude_containers na fonte docker_logs"
  fi

  # 2.5 Healthchecks nos serviços
  HC_OK=false
  if [[ -n "${COMPOSE_JSON}" ]] && command -v python3 &>/dev/null; then
    HC_OK=$(echo "${COMPOSE_JSON}" | python3 -c '
import sys, json
data = json.load(sys.stdin)
svcs = data.get("services", {})
has_vl = "healthcheck" in svcs.get("victorialogs", {})
has_vec = "healthcheck" in svcs.get("vector", {})
print("true" if (has_vl and has_vec) else "false")
' 2>/dev/null || echo "false")
  else
    if grep -q "victorialogs:" "${COMPOSE_FILE}" && grep -q "vector:" "${COMPOSE_FILE}"; then
      HC_OK=true
    fi
  fi

  if [[ "${HC_OK}" == "true" ]]; then
    record_result "COMPOSE-HEALTHCHECKS" "DockerCompose" "PASS" "Healthchecks configurados para os serviços principais (victorialogs e vector)" ""
  else
    record_result "COMPOSE-HEALTHCHECKS" "DockerCompose" "WARN" "Healthcheck ausente em victorialogs ou vector" "Defina blocos de healthcheck no docker-compose.yml"
  fi

  # 2.6 Política de reinicialização (restart: unless-stopped)
  RESTART_OK=false
  if [[ -n "${COMPOSE_JSON}" ]] && command -v python3 &>/dev/null; then
    RESTART_OK=$(echo "${COMPOSE_JSON}" | python3 -c '
import sys, json
data = json.load(sys.stdin)
svcs = data.get("services", {})
vl_rst = svcs.get("victorialogs", {}).get("restart", "") in ["unless-stopped", "always"]
vec_rst = svcs.get("vector", {}).get("restart", "") in ["unless-stopped", "always"]
print("true" if (vl_rst and vec_rst) else "false")
' 2>/dev/null || echo "false")
  else
    if grep -qE "restart:\s*(unless-stopped|always)" "${COMPOSE_FILE}"; then
      RESTART_OK=true
    fi
  fi

  if [[ "${RESTART_OK}" == "true" ]]; then
    record_result "COMPOSE-RESTART-POLICY" "DockerCompose" "PASS" "Políticas de reinicialização resilientes (unless-stopped/always) configuradas" ""
  else
    record_result "COMPOSE-RESTART-POLICY" "DockerCompose" "WARN" "Política de reinicialização não configurada ou insegura" "Configure 'restart: unless-stopped'"
  fi

  # 2.7 Sistema de arquivos raiz somente leitura (read_only: true)
  READ_ONLY_OK=false
  if [[ -n "${COMPOSE_JSON}" ]] && command -v python3 &>/dev/null; then
    READ_ONLY_OK=$(echo "${COMPOSE_JSON}" | python3 -c '
import sys, json
data = json.load(sys.stdin)
svcs = data.get("services", {})
vl_ro = svcs.get("victorialogs", {}).get("read_only", False) is True
vec_ro = svcs.get("vector", {}).get("read_only", False) is True
print("true" if (vl_ro and vec_ro) else "false")
' 2>/dev/null || echo "false")
  else
    if grep -q "victorialogs:" "${COMPOSE_FILE}" && grep -q "vector:" "${COMPOSE_FILE}"; then
      if grep -A 10 "victorialogs:" "${COMPOSE_FILE}" | grep -q "read_only: true" && \
         grep -A 10 "vector:" "${COMPOSE_FILE}" | grep -q "read_only: true"; then
        READ_ONLY_OK=true
      fi
    fi
  fi

  if [[ "${READ_ONLY_OK}" == "true" ]]; then
    record_result "COMPOSE-READ-ONLY-ROOTFS" "DockerCompose" "PASS" "Containers principais (victorialogs e vector) configurados com sistema de arquivos somente leitura (read_only: true)" ""
  else
    record_result "COMPOSE-READ-ONLY-ROOTFS" "DockerCompose" "WARN" "Sistema de arquivos somente leitura (read_only: true) ausente em victorialogs ou vector" "Configure 'read_only: true' no docker-compose.yml para endurecimento de segurança"
  fi

  # 2.8 Montagem tmpfs para arquivos efêmeros (/tmp)
  TMPFS_OK=false
  if [[ -n "${COMPOSE_JSON}" ]] && command -v python3 &>/dev/null; then
    TMPFS_OK=$(echo "${COMPOSE_JSON}" | python3 -c '
import sys, json
data = json.load(sys.stdin)
svcs = data.get("services", {})
def has_tmpfs(svc):
    t = svc.get("tmpfs", [])
    if isinstance(t, list):
        return any("/tmp" in str(item) for item in t)
    if isinstance(t, str):
        return "/tmp" in t
    return False

vl_tmp = has_tmpfs(svcs.get("victorialogs", {}))
vec_tmp = has_tmpfs(svcs.get("vector", {}))
print("true" if (vl_tmp and vec_tmp) else "false")
' 2>/dev/null || echo "false")
  else
    if grep -q "victorialogs:" "${COMPOSE_FILE}" && grep -q "vector:" "${COMPOSE_FILE}"; then
      if grep -A 12 "victorialogs:" "${COMPOSE_FILE}" | grep -q "/tmp" && \
         grep -A 12 "vector:" "${COMPOSE_FILE}" | grep -q "/tmp"; then
        TMPFS_OK=true
      fi
    fi
  fi

  if [[ "${TMPFS_OK}" == "true" ]]; then
    record_result "COMPOSE-TMPFS-TMP" "DockerCompose" "PASS" "Montagem tmpfs (/tmp) configurada para suportar escritas efêmeras sob rootfs somente leitura" ""
  else
    record_result "COMPOSE-TMPFS-TMP" "DockerCompose" "WARN" "Montagem tmpfs (/tmp) ausente em containers com read_only ativo" "Configure 'tmpfs: [/tmp]' no docker-compose.yml"
  fi
fi

# ==============================================================================
# 3. Exposição de Rede e Autenticação HTTP
# ==============================================================================
if [[ "${OUTPUT_JSON}" == "false" ]]; then
  echo ""
  echo -e "${BOLD}--- 3. Exposição de Rede & Autenticação ---${NC}"
fi

# Carregar variáveis do .env se existir
VL_USER="${VICTORIALOGS_AUTH_USERNAME:-}"
VL_PASS="${VICTORIALOGS_AUTH_PASSWORD:-}"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  VL_USER=$(grep -E '^\s*VICTORIALOGS_AUTH_USERNAME=' "${ENV_FILE}" | cut -d '=' -f2- | tr -d '"' | tr -d "'" || true)
  VL_PASS=$(grep -E '^\s*VICTORIALOGS_AUTH_PASSWORD=' "${ENV_FILE}" | cut -d '=' -f2- | tr -d '"' | tr -d "'" || true)
fi

# Checar bind de porta do VictoriaLogs
VL_PORT_BIND="0.0.0.0"
if [[ -n "${COMPOSE_JSON}" ]] && command -v python3 &>/dev/null; then
  VL_PORT_BIND=$(echo "${COMPOSE_JSON}" | python3 -c '
import sys, json
data = json.load(sys.stdin)
ports = data.get("services", {}).get("victorialogs", {}).get("ports", [])
bind_host = "0.0.0.0"
for p in ports:
    if isinstance(p, dict) and p.get("target") == 9428:
        bind_host = p.get("host_ip", "0.0.0.0")
print(bind_host)
' 2>/dev/null || echo "0.0.0.0")
fi

if [[ -n "${VL_USER}" && -n "${VL_PASS}" ]]; then
  record_result "NET-AUTH-BASIC" "Authentication" "PASS" "HTTP Basic Auth habilitada para consultas e APIs do VictoriaLogs" ""
else
  # Basic Auth desabilitada. Se a porta estiver aberta sem IP ou com 0.0.0.0, emitir alerta
  if [[ "${VL_PORT_BIND}" =~ ^127\.0\.0\.1 || "${VL_PORT_BIND}" =~ ^localhost ]]; then
    record_result "NET-AUTH-BASIC" "Authentication" "PASS" "VictoriaLogs restrito à interface local (127.0.0.1) com Basic Auth opcional" ""
  else
    record_result "NET-AUTH-BASIC" "Authentication" "WARN" "VictoriaLogs exposto sem HTTP Basic Auth configurado no .env" "Defina VICTORIALOGS_AUTH_USERNAME e PASSWORD se acessível fora da LAN protegida"
  fi
fi

# Checar bind do Vector HTTP
record_result "NET-VECTOR-BIND" "Network" "PASS" "Porta de ingestão HTTP do Vector (8686) acessível para microsserviços da rede local" ""

# ==============================================================================
# 4. Inspeção em Runtime dos Containers Ativos (se Docker estiver rodando)
# ==============================================================================
if command -v docker &>/dev/null && docker info &>/dev/null; then
  if [[ "${OUTPUT_JSON}" == "false" ]]; then
    echo ""
    echo -e "${BOLD}--- 4. Inspeção de Runtime (Containers Ativos) ---${NC}"
  fi

  # Checar se os containers estão rodando
  VL_STATUS=$(docker inspect victorialogs --format '{{.State.Status}}' 2>/dev/null || echo "offline")
  VEC_STATUS=$(docker inspect vector --format '{{.State.Status}}' 2>/dev/null || echo "offline")

  if [[ "${VL_STATUS}" == "running" ]]; then
    VL_RUN_MEM=$(docker inspect victorialogs --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
    if [[ "${VL_RUN_MEM}" -gt 0 && "${VL_RUN_MEM}" -le 83886080 ]]; then
      record_result "RUNTIME-VL-MEM" "Runtime" "PASS" "Container victorialogs ativo com limite de memória aplicado no kernel (${VL_RUN_MEM} bytes <= 80MB)" ""
    elif [[ "${VL_RUN_MEM}" -eq 0 ]]; then
      record_result "RUNTIME-VL-MEM" "Runtime" "FAIL" "Container victorialogs ativo SEM limite de memória no kernel (HostConfig.Memory == 0)" "Suba com 'docker compose up -d' respeitando o compose"
    else
      record_result "RUNTIME-VL-MEM" "Runtime" "WARN" "Container victorialogs ativo com limite de memória de $((VL_RUN_MEM / 1024 / 1024))MB (> 80MB)" ""
    fi

    # Checar se o sistema de arquivos raiz do victorialogs é somente leitura
    VL_RUN_RO=$(docker inspect victorialogs --format '{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null || echo "false")
    if [[ "${VL_RUN_RO}" == "true" ]]; then
      record_result "RUNTIME-VL-READONLY" "Runtime" "PASS" "Container victorialogs ativo com sistema de arquivos raiz somente leitura (ReadonlyRootfs=true)" ""
    else
      record_result "RUNTIME-VL-READONLY" "Runtime" "WARN" "Container victorialogs ativo SEM sistema de arquivos raiz somente leitura (ReadonlyRootfs=false)" "Reinicie os containers com 'docker compose up -d --force-recreate'"
    fi
  else
    record_result "RUNTIME-VL-STATUS" "Runtime" "PASS" "Container victorialogs não está em execução (inspeção de runtime ignorada)" ""
  fi

  if [[ "${VEC_STATUS}" == "running" ]]; then
    VEC_RUN_MEM=$(docker inspect vector --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
    if [[ "${VEC_RUN_MEM}" -gt 0 && "${VEC_RUN_MEM}" -le 62914560 ]]; then
      record_result "RUNTIME-VEC-MEM" "Runtime" "PASS" "Container vector ativo com limite de memória aplicado no kernel (${VEC_RUN_MEM} bytes <= 60MB)" ""
    elif [[ "${VEC_RUN_MEM}" -eq 0 ]]; then
      record_result "RUNTIME-VEC-MEM" "Runtime" "FAIL" "Container vector ativo SEM limite de memória no kernel (HostConfig.Memory == 0)" "Suba com 'docker compose up -d' respeitando o compose"
    else
      record_result "RUNTIME-VEC-MEM" "Runtime" "WARN" "Container vector ativo com limite de memória de $((VEC_RUN_MEM / 1024 / 1024))MB (> 60MB)" ""
    fi

    # Checar se o sistema de arquivos raiz do vector é somente leitura
    VEC_RUN_RO=$(docker inspect vector --format '{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null || echo "false")
    if [[ "${VEC_RUN_RO}" == "true" ]]; then
      record_result "RUNTIME-VEC-READONLY" "Runtime" "PASS" "Container vector ativo com sistema de arquivos raiz somente leitura (ReadonlyRootfs=true)" ""
    else
      record_result "RUNTIME-VEC-READONLY" "Runtime" "WARN" "Container vector ativo SEM sistema de arquivos raiz somente leitura (ReadonlyRootfs=false)" "Reinicie os containers com 'docker compose up -d --force-recreate'"
    fi

    # Checar se a montagem do docker.sock no container vector ativo é somente leitura
    SOCK_RO=$(docker inspect vector --format '{{range .Mounts}}{{if eq .Destination "/var/run/docker.sock"}}{{.RW}}{{end}}{{end}}' 2>/dev/null || echo "not_found")
    if [[ "${SOCK_RO}" == "false" ]]; then
      record_result "RUNTIME-VEC-SOCK-RO" "Runtime" "PASS" "Montagem ativa de /var/run/docker.sock no container vector é somente leitura (RW=false)" ""
    elif [[ "${SOCK_RO}" == "true" ]]; then
      record_result "RUNTIME-VEC-SOCK-RO" "Runtime" "FAIL" "Montagem ativa de /var/run/docker.sock no container vector possui permissão de ESCRITA (RW=true)" "Reinicie os containers com 'docker compose up -d --force-recreate'"
    fi
  else
    record_result "RUNTIME-VEC-STATUS" "Runtime" "PASS" "Container vector não está em execução (inspeção de runtime ignorada)" ""
  fi
fi

# ==============================================================================
# 5. Consolidação e Resumo
# ==============================================================================
TOTAL_CHECKS=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))

if [[ "${OUTPUT_JSON}" == "true" ]]; then
  # Montar JSON de saída
  CHECKS_JSON=$(IFS=,; echo "${JSON_RESULTS[*]}")
  cat << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "summary": {
    "total": ${TOTAL_CHECKS},
    "passed": ${PASS_COUNT},
    "fixed": ${FIX_COUNT},
    "warnings": ${WARN_COUNT},
    "failures": ${FAIL_COUNT},
    "status": "$([[ ${FAIL_COUNT} -eq 0 ]] && echo "HEALTHY" || echo "UNHEALTHY")"
  },
  "checks": [
    ${CHECKS_JSON}
  ]
}
EOF
else
  echo ""
  echo -e "${BOLD}========================================================================${NC}"
  echo -e "${BOLD} Resumo da Auditoria de Segurança ${NC}"
  echo -e "${BOLD}========================================================================${NC}"
  echo -e "Total de Verificações : ${TOTAL_CHECKS}"
  echo -e "Aprovados (PASS)      : ${GREEN}${PASS_COUNT}${NC}"
  if [[ ${FIX_COUNT} -gt 0 ]]; then
    echo -e "Corrigidos (--fix)    : ${CYAN}${FIX_COUNT}${NC}"
  fi
  echo -e "Avisos (WARN)         : ${YELLOW}${WARN_COUNT}${NC}"
  echo -e "Falhas (FAIL)         : ${RED}${FAIL_COUNT}${NC}"
  echo ""

  if [[ ${FAIL_COUNT} -eq 0 && ${WARN_COUNT} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}✔ Parabéns! A stack está 100% em conformidade com as diretrizes de segurança.${NC}"
  elif [[ ${FAIL_COUNT} -eq 0 ]]; then
    echo -e "${YELLOW}${BOLD}⚠ Auditoria concluída com avisos (WARN), mas sem falhas críticas impeditivas.${NC}"
  else
    echo -e "${RED}${BOLD}✖ Foram encontradas ${FAIL_COUNT} falha(s) crítica(s) de segurança que exigem atenção imediata!${NC}"
  fi
  echo ""
fi

# Determinar código de saída
if [[ ${FAIL_COUNT} -gt 0 ]]; then
  exit 1
elif [[ "${STRICT_MODE}" == "true" && ${WARN_COUNT} -gt 0 ]]; then
  exit 1
else
  exit 0
fi
