#!/usr/bin/env bash
# ==============================================================================
# Instalador e Sincronizador Global de SKILLs para Agentes de IA
# ==============================================================================
# Cria links simbólicos atômicos das skills canônicas deste repositório
# para as pastas globais de descoberta de IA (Cursor, Antigravity, etc.).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILLS_DIR="${ROOT_DIR}/skills"

DRY_RUN=false
TARGET_DIRS=()

usage() {
  cat <<HELP_EOF
Uso: $(basename "$0") [OPÇÕES]

Opções:
  --cursor            Instala symlinks em ~/.cursor/skills
  --antigravity       Instala symlinks em ~/.gemini/config/skills e ~/.gemini/antigravity/skills
  --all               Instala em todos os clientes de IA detectados
  --target DIR        Especifica um diretório de destino customizado
  -d, --dry-run       Mostra as ações que seriam executadas sem alterar o disco
  -l, --list          Lista as skills canônicas disponíveis neste repositório
  -h, --help          Exibe esta ajuda e encerra
HELP_EOF
  exit 0
}

list_skills() {
  echo "📚 Skills Canônicas Disponíveis em ${SKILLS_DIR}:"
  for skill_path in "${SKILLS_DIR}"/*; do
    if [[ -d "${skill_path}" && -f "${skill_path}/SKILL.md" ]]; then
      local s_name
      s_name=$(basename "${skill_path}")
      echo "  • ${s_name}"
    fi
  done
  exit 0
}

if [[ $# -eq 0 ]]; then
  # Padrão: instala para Cursor e Antigravity
  TARGET_DIRS+=("${HOME}/.cursor/skills")
  TARGET_DIRS+=("${HOME}/.gemini/config/skills")
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cursor)
      TARGET_DIRS+=("${HOME}/.cursor/skills")
      shift
      ;;
    --antigravity)
      TARGET_DIRS+=("${HOME}/.gemini/config/skills")
      TARGET_DIRS+=("${HOME}/.gemini/antigravity/skills")
      shift
      ;;
    --all)
      TARGET_DIRS+=("${HOME}/.cursor/skills")
      TARGET_DIRS+=("${HOME}/.gemini/config/skills")
      TARGET_DIRS+=("${HOME}/.gemini/antigravity/skills")
      shift
      ;;
    --target)
      if [[ $# -gt 1 ]]; then
        TARGET_DIRS+=("$2")
        shift 2
      else
        echo "Erro: --target requer o caminho de um diretório." >&2
        exit 1
      fi
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -l|--list)
      list_skills
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

if [[ ! -d "${SKILLS_DIR}" ]]; then
  echo "❌ Erro: Diretório de skills não encontrado em ${SKILLS_DIR}" >&2
  exit 1
fi

echo "================================================================================"
echo "🔗 [Agent Skills Installer] Sincronizando SKILLs com ambientes de IA..."
echo "================================================================================"

# Remover diretórios duplicados da lista de destinos
UNIQUE_TARGETS=()
while IFS= read -r dir; do
  [[ -n "$dir" ]] && UNIQUE_TARGETS+=("$dir")
done < <(printf "%s\n" "${TARGET_DIRS[@]}" | sort -u)

for target in "${UNIQUE_TARGETS[@]}"; do
  echo -e "\n🎯 Destino: ${target}"
  
  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "${target}"
  fi

  for skill_path in "${SKILLS_DIR}"/*; do
    if [[ -d "${skill_path}" && -f "${skill_path}/SKILL.md" ]]; then
      skill_name=$(basename "${skill_path}")
      link_dest="${target}/${skill_name}"

      if [[ "$DRY_RUN" == true ]]; then
        echo "   [DRY-RUN] ln -sfn \"${skill_path}\" \"${link_dest}\""
      else
        ln -sfn "${skill_path}" "${link_dest}"
        echo "   ✅ Link criado/atualizado: ${skill_name} -> ${skill_path}"
      fi
    fi
  done
done

echo -e "\n================================================================================"
if [[ "$DRY_RUN" == true ]]; then
  echo "🔍 Modo Dry-run concluído. Nenhuma alteração foi realizada."
else
  echo "🎉 Todas as skills canônicas foram vinculadas com sucesso aos clientes de IA!"
fi
echo "================================================================================"
