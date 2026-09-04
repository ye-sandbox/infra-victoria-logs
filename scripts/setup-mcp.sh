#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs Official MCP Server Installer Script
# ==============================================================================
# Baixa e instala o binário oficial do VictoriaMetrics/mcp-victorialogs
# no diretório do usuário (~/.local/bin) e valida a execução básica.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

INSTALL_DIR="${1:-${ROOT_DIR}/bin}"
mkdir -p "${INSTALL_DIR}"
USER_BIN="${HOME}/.local/bin"
mkdir -p "${USER_BIN}" 2>/dev/null || true

REPO="VictoriaMetrics/mcp-victorialogs"
VERSION="${MCP_VICTORIALOGS_VERSION:-latest}"

echo "================================================================================"
echo "🤖 [VictoriaLogs MCP] Iniciando instalação do MCP Server oficial..."
echo "================================================================================"

# Detectar arquitetura
ARCH=$(uname -m)
case "${ARCH}" in
  x86_64)
    ARCH_TAG="Linux_x86_64"
    ;;
  aarch64|arm64)
    ARCH_TAG="Linux_arm64"
    ;;
  *)
    echo "❌ Arquitetura não suportada automaticamente: ${ARCH}"
    exit 1
    ;;
esac

# Obter tag da versão
if [[ "${VERSION}" == "latest" ]]; then
  echo "🔍 Consultando versão mais recente no GitHub..."
  VERSION_TAG=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  if [[ -z "${VERSION_TAG}" ]]; then
    VERSION_TAG="v1.9.0"
  fi
else
  VERSION_TAG="${VERSION}"
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION_TAG}/mcp-victorialogs_${ARCH_TAG}.tar.gz"
echo "📦 Versão identificada: ${VERSION_TAG} (${ARCH_TAG})"
echo "⬇️  Baixando de: ${DOWNLOAD_URL}..."

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

curl -sL "${DOWNLOAD_URL}" -o "${TMP_DIR}/mcp-victorialogs.tar.gz"
tar -xzf "${TMP_DIR}/mcp-victorialogs.tar.gz" -C "${TMP_DIR}"

TARGET_BIN="${INSTALL_DIR}/mcp-victorialogs"
mv "${TMP_DIR}/mcp-victorialogs" "${TARGET_BIN}"
chmod +x "${TARGET_BIN}"

# Copiar também para ~/.local/bin se acessível
if [[ -d "${USER_BIN}" && -w "${USER_BIN}" ]]; then
  cp -f "${TARGET_BIN}" "${USER_BIN}/mcp-victorialogs"
  chmod +x "${USER_BIN}/mcp-victorialogs"
  echo "✅ Copiado também para o PATH do usuário: ${USER_BIN}/mcp-victorialogs"
fi

echo "✅ Binário principal instalado com sucesso em: ${TARGET_BIN}"

# Validar execução básica
echo "🧪 Testando execução do binário..."
if "${TARGET_BIN}" -help 2>&1 | grep -q "VL_INSTANCE_ENTRYPOINT"; then
  echo "✅ Executável testado e pronto para uso!"
else
  echo "⚠️  O executável respondeu de forma inesperada, mas foi instalado."
fi

echo "================================================================================"
echo "🎉 Instalação concluída!"
echo "Para utilizar em clientes MCP, configure o executável:"
echo "  ${TARGET_BIN}"
echo "com a variável de ambiente:"
echo "  VL_INSTANCE_ENTRYPOINT=http://<IP_DO_VICTORIALOGS>:9428"
echo "================================================================================"
