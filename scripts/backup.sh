#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs Atomic Backup Script via Native Snapshot API (Regra 3-2-1)
# ==============================================================================
# Executa snapshot consistente sem parar o banco e sem risco de corrupção
# no HD/SSD, compacta em .tar.gz, rotaciona cópias antigas e opcionalmente
# sincroniza com armazenamento off-site (rclone, rsync/SSH ou S3).
#
# Uso:
#   ./scripts/backup.sh [OPÇÕES]
#
# Opções:
#   --dry-run               Simula o snapshot e sincronização sem gravar ou apagar arquivos
#   --remote-dest DEST      Destino remoto (ex: s3://bucket/path, user@host:/path, rclone:dest)
#   --remote-tool TOOL      Ferramenta de transferência (auto, rclone, rsync, s3)
#   --retention-copies N    Quantidade de cópias a manter (padrão: 7)
#   --dir DIR               Diretório de backups locais (padrão: ./backups)
#   -h, --help              Exibe esta ajuda
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
VICTORIALOGS_HOST="${VICTORIALOGS_HOST:-127.0.0.1}"
VL_BASE_URL="http://${VICTORIALOGS_HOST}:${VICTORIALOGS_PORT}"

BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups}"
RETENTION_COPIES="${BACKUP_RETENTION_COPIES:-7}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/vlogs_snapshot_${TIMESTAMP}.tar.gz"

BACKUP_REMOTE_DEST="${BACKUP_REMOTE_DEST:-}"
BACKUP_REMOTE_TOOL="${BACKUP_REMOTE_TOOL:-auto}"
BACKUP_REMOTE_EXTRA_OPTS="${BACKUP_REMOTE_EXTRA_OPTS:-}"
BACKUP_REMOTE_RETENTION_ENABLED="${BACKUP_REMOTE_RETENTION_ENABLED:-true}"

DRY_RUN=false

# Parse de argumentos CLI
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --remote-dest)
      BACKUP_REMOTE_DEST="$2"
      shift 2
      ;;
    --remote-tool)
      BACKUP_REMOTE_TOOL="$2"
      shift 2
      ;;
    --retention-copies)
      RETENTION_COPIES="$2"
      shift 2
      ;;
    --dir)
      BACKUP_DIR="$2"
      BACKUP_FILE="${BACKUP_DIR}/vlogs_snapshot_${TIMESTAMP}.tar.gz"
      shift 2
      ;;
    -h|--help)
      echo "Uso: $0 [OPÇÕES]"
      echo ""
      echo "Opções:"
      echo "  --dry-run               Simula o snapshot e sincronização sem gravar ou apagar arquivos"
      echo "  --remote-dest DEST      Destino remoto (ex: s3://bucket/path, user@host:/path, rclone:dest)"
      echo "  --remote-tool TOOL      Ferramenta de transferência (auto, rclone, rsync, s3)"
      echo "  --retention-copies N    Quantidade de cópias a manter (padrão: 7)"
      echo "  --dir DIR               Diretório de backups locais (padrão: ./backups)"
      echo "  -h, --help              Exibe esta ajuda"
      exit 0
      ;;
    *)
      echo "❌ Opção desconhecida: $1"
      echo "Use '$0 --help' para ver as opções disponíveis."
      exit 1
      ;;
  esac
done

mkdir -p "${BACKUP_DIR}"

# Configurar autenticação para curl se configurada
CURL_AUTH_OPTS=()
if [[ -n "${VICTORIALOGS_AUTH_USERNAME:-}" ]]; then
  CURL_AUTH_OPTS=(-u "${VICTORIALOGS_AUTH_USERNAME}:${VICTORIALOGS_AUTH_PASSWORD:-}")
fi

detect_remote_tool() {
  local dest="$1"
  local tool="${2:-auto}"

  if [[ "${tool}" != "auto" && -n "${tool}" ]]; then
    echo "${tool}"
    return 0
  fi

  if [[ "${dest}" =~ ^s3:// ]]; then
    if command -v aws >/dev/null 2>&1; then
      echo "s3"
    elif command -v rclone >/dev/null 2>&1; then
      echo "rclone"
    else
      echo "s3"
    fi
  elif [[ "${dest}" =~ ^rclone: ]] || [[ "${dest}" =~ ^[a-zA-Z0-9_-]+:[^/].* ]]; then
    echo "rclone"
  elif [[ "${dest}" =~ @ ]] || [[ "${dest}" =~ : ]] || [[ "${dest}" =~ ^/ ]] || [[ "${dest}" =~ ^\. ]]; then
    echo "rsync"
  else
    echo "rclone"
  fi
}

remote_rotate_rclone() {
  local target_dest="$1"
  local copies="$2"
  local is_dry="$3"

  echo "♻️  [rclone] Verificando retenção remota em '${target_dest}' (mantendo ${copies} cópias)..."
  if ! command -v rclone >/dev/null 2>&1; then
    if [[ "${is_dry}" == "true" ]]; then
      echo "   ⚠️  [DRY-RUN] rclone não instalado no host; simulação de rotação remota concluída."
      return 0
    fi
    echo "❌ ERRO: rclone não encontrado no PATH para rotação remota."
    return 1
  fi

  local remote_files
  remote_files=$(rclone lsf "${target_dest}" --include "vlogs_snapshot_*.tar.gz" 2>/dev/null | grep -E "^vlogs_snapshot_.*\.tar\.gz$" | sort || true)

  if [[ -z "${remote_files}" ]]; then
    echo "   ℹ️  Nenhum backup encontrado no destino remoto para rotação."
    return 0
  fi

  local count
  count=$(echo "${remote_files}" | grep -c "vlogs_snapshot_" || true)
  if (( count > copies )); then
    local excess=$(( count - copies ))
    echo "   🗑️  Removendo ${excess} cópia(s) remota(s) excedente(s)..."
    echo "${remote_files}" | head -n "${excess}" | while read -r old_file; do
      [[ -z "${old_file}" ]] && continue
      echo "      - ${old_file}"
      if [[ "${is_dry}" == "true" ]]; then
        echo "        [DRY-RUN] rclone deletefile '${target_dest}/${old_file}'"
      else
        rclone deletefile "${target_dest}/${old_file}" 2>/dev/null || true
      fi
    done
  else
    echo "   ✅ Retenção remota em dia (${count}/${copies} cópias existentes)."
  fi
}

remote_rotate_rsync() {
  local target_dest="$1"
  local copies="$2"
  local is_dry="$3"

  echo "♻️  [rsync] Verificando retenção remota em '${target_dest}' (mantendo ${copies} cópias)..."
  local remote_files=""
  if [[ "${target_dest}" =~ ^/ ]] || [[ "${target_dest}" =~ ^\. ]]; then
    if [[ ! -d "${target_dest}" ]]; then
      echo "   ℹ️  Diretório remoto/montado não existe ainda: ${target_dest}"
      return 0
    fi
    remote_files=$(find "${target_dest}" -maxdepth 1 -name "vlogs_snapshot_*.tar.gz" -exec basename {} \; 2>/dev/null | sort || true)
  elif [[ "${target_dest}" =~ : ]]; then
    if ! command -v ssh >/dev/null 2>&1; then
      if [[ "${is_dry}" == "true" ]]; then
        echo "   ⚠️  [DRY-RUN] ssh não instalado; simulação de rotação SSH concluída."
        return 0
      fi
      echo "❌ ERRO: ssh não encontrado no PATH para rotação remota via SSH."
      return 1
    fi
    local ssh_host="${target_dest%%:*}"
    local remote_path="${target_dest#*:}"
    remote_files=$(ssh -o BatchMode=yes "${ssh_host}" "find '${remote_path}' -maxdepth 1 -name 'vlogs_snapshot_*.tar.gz' -exec basename {} \;" 2>/dev/null | sort || true)
  fi

  if [[ -z "${remote_files}" ]]; then
    echo "   ℹ️  Nenhum backup encontrado no destino remoto para rotação."
    return 0
  fi

  local count
  count=$(echo "${remote_files}" | grep -c "vlogs_snapshot_" || true)
  if (( count > copies )); then
    local excess=$(( count - copies ))
    echo "   🗑️  Removendo ${excess} cópia(s) remota(s) excedente(s)..."
    echo "${remote_files}" | head -n "${excess}" | while read -r old_file; do
      [[ -z "${old_file}" ]] && continue
      echo "      - ${old_file}"
      if [[ "${is_dry}" == "true" ]]; then
        echo "        [DRY-RUN] Expurgo de ${old_file} no destino rsync"
      else
        if [[ "${target_dest}" =~ ^/ ]] || [[ "${target_dest}" =~ ^\. ]]; then
          rm -f "${target_dest}/${old_file}"
        else
          local ssh_host="${target_dest%%:*}"
          local remote_path="${target_dest#*:}"
          ssh -o BatchMode=yes "${ssh_host}" "rm -f '${remote_path}/${old_file}'" 2>/dev/null || true
        fi
      fi
    done
  else
    echo "   ✅ Retenção remota em dia (${count}/${copies} cópias existentes)."
  fi
}

remote_rotate_s3() {
  local target_dest="$1"
  local copies="$2"
  local is_dry="$3"

  echo "♻️  [s3] Verificando retenção remota em '${target_dest}' (mantendo ${copies} cópias)..."
  if ! command -v aws >/dev/null 2>&1; then
    if [[ "${is_dry}" == "true" ]]; then
      echo "   ⚠️  [DRY-RUN] aws CLI não instalado; simulação de rotação S3 concluída."
      return 0
    fi
    echo "❌ ERRO: aws CLI não encontrado no PATH para rotação remota S3."
    return 1
  fi

  local remote_files
  # shellcheck disable=SC2086
  remote_files=$(aws s3 ls "${target_dest}/" ${BACKUP_REMOTE_EXTRA_OPTS} 2>/dev/null | awk '{print $4}' | grep -E "^vlogs_snapshot_.*\.tar\.gz$" | sort || true)

  if [[ -z "${remote_files}" ]]; then
    echo "   ℹ️  Nenhum backup encontrado no destino S3 para rotação."
    return 0
  fi

  local count
  count=$(echo "${remote_files}" | grep -c "vlogs_snapshot_" || true)
  if (( count > copies )); then
    local excess=$(( count - copies ))
    echo "   🗑️  Removendo ${excess} cópia(s) remota(s) excedente(s)..."
    echo "${remote_files}" | head -n "${excess}" | while read -r old_file; do
      [[ -z "${old_file}" ]] && continue
      echo "      - ${old_file}"
      if [[ "${is_dry}" == "true" ]]; then
        echo "        [DRY-RUN] aws s3 rm '${target_dest}/${old_file}'"
      else
        # shellcheck disable=SC2086
        aws s3 rm "${target_dest}/${old_file}" ${BACKUP_REMOTE_EXTRA_OPTS} 2>/dev/null || true
      fi
    done
  else
    echo "   ✅ Retenção remota em dia (${count}/${copies} cópias existentes)."
  fi
}

sync_to_remote() {
  local file="$1"
  local dest="$2"
  local tool="$3"
  local is_dry="$4"

  echo ""
  echo "🌐 [Regra 3-2-1] Sincronizando cópia off-site via '${tool}'..."
  echo "   Destino: ${dest}"

  case "${tool}" in
    rclone)
      if ! command -v rclone >/dev/null 2>&1; then
        if [[ "${is_dry}" == "true" ]]; then
          echo "   ⚠️  [DRY-RUN] 'rclone' não está instalado no PATH do sistema."
        else
          echo "❌ ERRO: 'rclone' não está instalado no PATH do sistema."
          return 1
        fi
      fi
      local target_dest="${dest#rclone:}"
      if [[ "${is_dry}" == "true" ]]; then
        echo "   🔍 [DRY-RUN] rclone copy '${file}' '${target_dest}/' ${BACKUP_REMOTE_EXTRA_OPTS}"
      else
        # shellcheck disable=SC2086
        rclone copy "${file}" "${target_dest}/" ${BACKUP_REMOTE_EXTRA_OPTS}
      fi
      if [[ "${BACKUP_REMOTE_RETENTION_ENABLED}" == "true" ]]; then
        remote_rotate_rclone "${target_dest}" "${RETENTION_COPIES}" "${is_dry}"
      fi
      ;;
    rsync)
      if ! command -v rsync >/dev/null 2>&1; then
        if [[ "${is_dry}" == "true" ]]; then
          echo "   ⚠️  [DRY-RUN] 'rsync' não está instalado no PATH do sistema."
        else
          echo "❌ ERRO: 'rsync' não está instalado no PATH do sistema."
          return 1
        fi
      fi
      if [[ "${is_dry}" == "true" ]]; then
        echo "   🔍 [DRY-RUN] rsync -avz ${BACKUP_REMOTE_EXTRA_OPTS} '${file}' '${dest}/'"
      else
        # shellcheck disable=SC2086
        rsync -avz ${BACKUP_REMOTE_EXTRA_OPTS} "${file}" "${dest}/"
      fi
      if [[ "${BACKUP_REMOTE_RETENTION_ENABLED}" == "true" ]]; then
        remote_rotate_rsync "${dest}" "${RETENTION_COPIES}" "${is_dry}"
      fi
      ;;
    s3)
      if ! command -v aws >/dev/null 2>&1; then
        if [[ "${is_dry}" == "true" ]]; then
          echo "   ⚠️  [DRY-RUN] 'aws' CLI não está instalado no PATH do sistema."
        else
          echo "❌ ERRO: 'aws' CLI não está instalado no PATH do sistema."
          return 1
        fi
      fi
      if [[ "${is_dry}" == "true" ]]; then
        echo "   🔍 [DRY-RUN] aws s3 cp '${file}' '${dest}/' ${BACKUP_REMOTE_EXTRA_OPTS}"
      else
        # shellcheck disable=SC2086
        aws s3 cp "${file}" "${dest}/" ${BACKUP_REMOTE_EXTRA_OPTS}
      fi
      if [[ "${BACKUP_REMOTE_RETENTION_ENABLED}" == "true" ]]; then
        remote_rotate_s3 "${dest}" "${RETENTION_COPIES}" "${is_dry}"
      fi
      ;;
    *)
      echo "❌ ERRO: Ferramenta remota desconhecida: '${tool}'. Suportados: rclone, rsync, s3, auto."
      return 1
      ;;
  esac
  echo "✅ Cópia off-site sincronizada com sucesso para ${dest}"
}

echo "================================================================================"
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "🪵 [VictoriaLogs Backup] Executando em modo de simulação (--dry-run)..."
else
  echo "🪵 [VictoriaLogs Backup] Iniciando snapshot atômico..."
fi
echo "================================================================================"

# 1. Verificar se VictoriaLogs está saudável
if curl "${CURL_AUTH_OPTS[@]}" -s -f "${VL_BASE_URL}/health" > /dev/null 2>&1; then
  echo "✅ VictoriaLogs respondendo e saudável em ${VL_BASE_URL}/health."
else
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "⚠️  [DRY-RUN] VictoriaLogs não está respondendo em ${VL_BASE_URL}/health (simulação prosseguindo)."
  else
    echo "❌ ERRO: VictoriaLogs não está respondendo em ${VL_BASE_URL}/health."
    echo "Verifique se o container está rodando com 'docker compose ps'."
    exit 1
  fi
fi

# MODO DRY-RUN
if [[ "${DRY_RUN}" == "true" ]]; then
  echo ""
  echo "🔍 [DRY-RUN] Simulação das operações de snapshot e retenção:"
  echo " 1. Snapshot Nativo:  POST ${VL_BASE_URL}/internal/partition/snapshot/create (SIMULADO)"
  echo " 2. Compactação:      docker cp victorialogs:<snapshot> -> ${BACKUP_FILE} (SIMULADO)"
  echo " 3. Limpeza Interna:  GET ${VL_BASE_URL}/internal/partition/snapshot/delete (SIMULADO)"

  # Checagem de rotação local real no diretório
  echo ""
  echo "♻️  [DRY-RUN] Verificando retenção local (${RETENTION_COPIES} cópias) em ${BACKUP_DIR}:"
  TOTAL_BACKUPS=$(find "${BACKUP_DIR}" -maxdepth 1 -name "vlogs_snapshot_*.tar.gz" 2>/dev/null | wc -l)
  echo "   Cópias locais atuais: ${TOTAL_BACKUPS}"
  if (( TOTAL_BACKUPS > RETENTION_COPIES )); then
    EXCESS=$(( TOTAL_BACKUPS - RETENTION_COPIES ))
    echo "   [DRY-RUN] ${EXCESS} cópia(s) antiga(s) seria(m) removida(s):"
    find "${BACKUP_DIR}" -maxdepth 1 -name "vlogs_snapshot_*.tar.gz" | sort | head -n "${EXCESS}" | while read -r old_b; do
      echo "      - $(basename "${old_b}")"
    done
  else
    echo "   [DRY-RUN] Nenhuma remoção necessária (dentro do limite de ${RETENTION_COPIES} cópias)."
  fi

  # Sincronização remota em modo dry-run
  if [[ -n "${BACKUP_REMOTE_DEST}" ]]; then
    ACTIVE_TOOL=$(detect_remote_tool "${BACKUP_REMOTE_DEST}" "${BACKUP_REMOTE_TOOL}")
    sync_to_remote "${BACKUP_FILE}" "${BACKUP_REMOTE_DEST}" "${ACTIVE_TOOL}" "true"
  else
    echo ""
    echo "ℹ️  Sincronização remota (Regra 3-2-1) desativada (BACKUP_REMOTE_DEST não configurado)."
  fi

  echo "================================================================================"
  echo "🎉 [DRY-RUN] Simulação de backup concluída com sucesso!"
  echo "================================================================================"
  exit 0
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

# 5. Rotação de backups antigos (mantém as últimas N cópias locais)
echo "♻️  Aplicando política de retenção local (mantendo as últimas ${RETENTION_COPIES} cópias)..."
TOTAL_BACKUPS=$(find "${BACKUP_DIR}" -maxdepth 1 -name "vlogs_snapshot_*.tar.gz" | wc -l)

if (( TOTAL_BACKUPS > RETENTION_COPIES )); then
  EXCESS=$(( TOTAL_BACKUPS - RETENTION_COPIES ))
  find "${BACKUP_DIR}" -maxdepth 1 -name "vlogs_snapshot_*.tar.gz" | sort | head -n "${EXCESS}" | while read -r old_backup; do
    echo "   🗑️  Removendo cópia antiga: $(basename "${old_backup}")"
    rm -f "${old_backup}"
  done
fi

# 6. Sincronização remota off-site (Regra 3-2-1)
if [[ -n "${BACKUP_REMOTE_DEST}" ]]; then
  ACTIVE_TOOL=$(detect_remote_tool "${BACKUP_REMOTE_DEST}" "${BACKUP_REMOTE_TOOL}")
  if ! sync_to_remote "${BACKUP_FILE}" "${BACKUP_REMOTE_DEST}" "${ACTIVE_TOOL}" "false"; then
    echo "❌ ERRO: Falha na sincronização remota off-site!"
    exit 2
  fi
else
  echo "ℹ️  Sincronização remota (Regra 3-2-1) desativada (BACKUP_REMOTE_DEST não configurado)."
fi

echo "================================================================================"
echo "🎉 Backup concluído com sucesso em: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================================"
