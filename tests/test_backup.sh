#!/usr/bin/env bash
# ==============================================================================
# Test Suite: VictoriaLogs Backup & Off-Site Replication (Regra 3-2-1)
# ==============================================================================
# Valida comportamento de flags, simulação --dry-run, detecção de ferramentas
# remotas (s3, rclone, rsync) e política de rotação de retenção.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_SCRIPT="${ROOT_DIR}/scripts/backup.sh"

PASSED=0
FAILED=0

assert_contains() {
  local output="$1"
  local expected="$2"
  local test_name="$3"
  if echo "${output}" | grep -qF -e "${expected}"; then
    echo "  ✅ [PASS] ${test_name}"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ [FAIL] ${test_name}"
    echo "     Esperado: '${expected}'"
    echo "     Recebido: '${output}'"
    FAILED=$((FAILED + 1))
  fi
}

assert_exit_code() {
  local cmd="$1"
  local expected_code="$2"
  local test_name="$3"
  set +e
  eval "${cmd}" > /dev/null 2>&1
  local actual_code=$?
  set -e
  if [[ "${actual_code}" -eq "${expected_code}" ]]; then
    echo "  ✅ [PASS] ${test_name} (exit code: ${actual_code})"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ [FAIL] ${test_name} (esperado: ${expected_code}, recebido: ${actual_code})"
    FAILED=$((FAILED + 1))
  fi
}

echo "================================================================================"
echo "🧪 [Test Suite] Iniciando testes automatizados do backup.sh (Regra 3-2-1)..."
echo "================================================================================"

# 1. Validação de Flags Básicas
echo ""
echo "▶️ Testando flags de ajuda e argumentos inválidos..."
assert_exit_code "bash '${BACKUP_SCRIPT}' --help" 0 "backup.sh --help retorna 0"
HELP_OUT=$(bash "${BACKUP_SCRIPT}" --help)
assert_contains "${HELP_OUT}" "--dry-run" "Ajuda lista flag --dry-run"
assert_contains "${HELP_OUT}" "--remote-dest" "Ajuda lista flag --remote-dest"
assert_contains "${HELP_OUT}" "--remote-tool" "Ajuda lista flag --remote-tool"
assert_exit_code "bash '${BACKUP_SCRIPT}' --opcao-inexistente" 1 "Opção inválida retorna código 1"

# 2. Modo Dry-Run sem Destino Remoto
echo ""
echo "▶️ Testando modo --dry-run sem sincronização remota..."
DRY_OUT=$(bash "${BACKUP_SCRIPT}" --dry-run)
assert_contains "${DRY_OUT}" "[DRY-RUN]" "Execução contém marcadores [DRY-RUN]"
assert_contains "${DRY_OUT}" "Sincronização remota (Regra 3-2-1) desativada" "Informa que sincronização remota está desativada"

# 3. Detecção e Simulação de Destino S3
echo ""
echo "▶️ Testando auto-detecção de destino S3..."
S3_OUT=$(bash "${BACKUP_SCRIPT}" --dry-run --remote-dest "s3://meu-bucket/backups")
assert_contains "${S3_OUT}" "Sincronizando cópia off-site via 's3'" "Auto-detecta ferramenta 's3' para prefixo s3://"
assert_contains "${S3_OUT}" "aws s3 cp" "Gera comando de simulação aws s3 cp"
assert_contains "${S3_OUT}" "Verificando retenção remota em 's3://meu-bucket/backups'" "Aciona auditoria de retenção remota S3"

# 4. Detecção e Simulação de Destino rclone
echo ""
echo "▶️ Testando auto-detecção de destino rclone..."
RCLONE_OUT=$(bash "${BACKUP_SCRIPT}" --dry-run --remote-dest "rclone:meu-gdrive:backups")
assert_contains "${RCLONE_OUT}" "Sincronizando cópia off-site via 'rclone'" "Auto-detecta ferramenta 'rclone' para prefixo rclone:"
assert_contains "${RCLONE_OUT}" "rclone copy" "Gera comando de simulação rclone copy"
assert_contains "${RCLONE_OUT}" "Verificando retenção remota em 'meu-gdrive:backups'" "Aciona auditoria de retenção remota rclone"

# 5. Detecção e Simulação de Destino rsync SSH
echo ""
echo "▶️ Testando auto-detecção de destino rsync SSH..."
RSYNC_OUT=$(bash "${BACKUP_SCRIPT}" --dry-run --remote-dest "admin@nas.homelab:/mnt/backups")
assert_contains "${RSYNC_OUT}" "Sincronizando cópia off-site via 'rsync'" "Auto-detecta ferramenta 'rsync' para user@host:"
assert_contains "${RSYNC_OUT}" "rsync -avz" "Gera comando de simulação rsync"
assert_contains "${RSYNC_OUT}" "Verificando retenção remota em 'admin@nas.homelab:/mnt/backups'" "Aciona auditoria de retenção remota rsync"

# 6. Sobrescrita Explícita de Ferramenta (--remote-tool)
echo ""
echo "▶️ Testando sobrescrita explícita de ferramenta..."
OVERRIDE_OUT=$(bash "${BACKUP_SCRIPT}" --dry-run --remote-dest "s3://meu-bucket/backups" --remote-tool rclone)
assert_contains "${OVERRIDE_OUT}" "Sincronizando cópia off-site via 'rclone'" "Respeita flag --remote-tool rclone mesmo com s3://"

# 7. Auditoria de Rotação Remota em Diretório Local/Montado
echo ""
echo "▶️ Testando cálculo de retenção remota em diretório com excedente..."
TMP_REMOTE=$(mktemp -d)
trap 'rm -rf "${TMP_REMOTE}"' EXIT

touch "${TMP_REMOTE}/vlogs_snapshot_20261010_010000.tar.gz"
touch "${TMP_REMOTE}/vlogs_snapshot_20261011_010000.tar.gz"
touch "${TMP_REMOTE}/vlogs_snapshot_20261012_010000.tar.gz"
touch "${TMP_REMOTE}/vlogs_snapshot_20261013_010000.tar.gz"

ROTATE_OUT=$(bash "${BACKUP_SCRIPT}" --dry-run --remote-dest "${TMP_REMOTE}" --remote-tool rsync --retention-copies 2)
assert_contains "${ROTATE_OUT}" "Removendo 2 cópia(s) remota(s) excedente(s)" "Calcula exatamente 2 cópias excedentes para expurgo"
assert_contains "${ROTATE_OUT}" "vlogs_snapshot_20261010_010000.tar.gz" "Identifica o arquivo mais antigo para remoção"
assert_contains "${ROTATE_OUT}" "vlogs_snapshot_20261011_010000.tar.gz" "Identifica o segundo arquivo mais antigo para remoção"

echo ""
echo "================================================================================"
echo "📊 Resumo da Execução de Testes:"
echo "   Passaram: ${PASSED}"
echo "   Falharam: ${FAILED}"
echo "================================================================================"

if [[ "${FAILED}" -gt 0 ]]; then
  echo "❌ Alguns testes falharam!"
  exit 1
fi

echo "🎉 Todos os testes passaram com sucesso!"
exit 0
