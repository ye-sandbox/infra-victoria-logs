#!/usr/bin/env bash
# ==============================================================================
# Host Disk & I/O Scheduler Tuning Assistant for Mechanical HDDs
# ==============================================================================
# Este script inspeciona discos físicos no host Proxmox/Linux e diagnostica:
# 1. I/O Scheduler (recomenda 'mq-deadline' ou 'bfq' para HDs rotacionais).
# 2. Opções de montagem de filesystem (avalia 'noatime' vs 'relatime').
# 3. Políticas de APM e Spindown (evita ciclos de parada/aceleração de motor).
#
# Uso:
#   sudo ./scripts/tune-disk-host.sh --check           (Diagnóstico completo)
#   sudo ./scripts/tune-disk-host.sh --generate-udev   (Persiste mq-deadline para HDs)
#   sudo ./scripts/tune-disk-host.sh --remount-noatime / (Remount temporário com noatime)
# ==============================================================================

set -euo pipefail

ACTION="${1:---check}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_help() {
  cat <<EOF
Uso: $0 [OPÇÃO]

Opções:
  --check               Realiza inspeção e diagnóstico dos discos e montagens (não altera nada)
  --generate-udev       Cria regra udev persistente para forçar mq-deadline em todos os HDs mecânicos
  --remount-noatime DIR Executa remount do diretório especificado adicionando a flag noatime
  -h, --help            Exibe esta mensagem de ajuda

Exemplos:
  sudo $0 --check
  sudo $0 --generate-udev
  sudo $0 --remount-noatime /
EOF
}

check_disks() {
  echo -e "${BLUE}==============================================================================${NC}"
  echo -e "${BLUE}🔍 DIAGNÓSTICO DE DISCOS E I/O SCHEDULER DO HOST${NC}"
  echo -e "${BLUE}==============================================================================${NC}"

  local FOUND_DISKS=0

  for dev_path in /sys/block/sd* /sys/block/vd* /sys/block/nvme*n1; do
    if [[ ! -d "${dev_path}" ]]; then continue; fi

    local DEV_NAME
    DEV_NAME="$(basename "${dev_path}")"
    FOUND_DISKS=$(( FOUND_DISKS + 1 ))

    local ROTATIONAL="0"
    if [[ -f "${dev_path}/queue/rotational" ]]; then
      ROTATIONAL="$(cat "${dev_path}/queue/rotational" 2>/dev/null || echo "0")"
    fi

    local MODEL="Desconhecido"
    if [[ -f "${dev_path}/device/model" ]]; then
      MODEL="$(cat "${dev_path}/device/model" 2>/dev/null | xargs || echo "Desconhecido")"
    fi

    local SIZE_GB="0"
    if [[ -f "${dev_path}/size" ]]; then
      local BLOCKS
      BLOCKS="$(cat "${dev_path}/size" 2>/dev/null || echo "0")"
      SIZE_GB=$(( BLOCKS * 512 / 1024 / 1024 / 1024 ))
    fi

    local SCHEDULER="não suportado"
    if [[ -f "${dev_path}/queue/scheduler" ]]; then
      SCHEDULER="$(cat "${dev_path}/queue/scheduler" 2>/dev/null || echo "não suportado")"
    fi

    echo -e "\n📌 Dispositivo: ${CYAN}/dev/${DEV_NAME}${NC} (${MODEL}, ~${SIZE_GB} GB)"

    if [[ "${ROTATIONAL}" == "1" ]]; then
      echo -e "   • Tipo de Mídia: ${YELLOW}HD Mecânico Rotacional${NC} (Agulha móvel)"

      # Analisar Scheduler
      echo -e "   • Schedulers disponíveis: ${SCHEDULER}"
      if [[ "${SCHEDULER}" == *"[mq-deadline]"* || "${SCHEDULER}" == *"[bfq]"* ]]; then
        echo -e "   • Avaliação de I/O: ${GREEN}✅ EXCELENTE${NC} — Algoritmo de elevador ativo para HD."
      elif [[ "${SCHEDULER}" == *"[none]"* ]]; then
        echo -e "   • Avaliação de I/O: ${RED}⚠️  INEFICIENTE${NC} — O scheduler está em [none] (padrão NVMe)."
        echo -e "     Em HD mecânico, 'none' provoca head thrashing. Recomenda-se: ${GREEN}mq-deadline${NC} ou ${GREEN}bfq${NC}."
        echo -e "     Para corrigir de forma persistente, execute: ${GREEN}sudo $0 --generate-udev${NC}"
      else
        echo -e "   • Avaliação de I/O: Scheduler atual: ${SCHEDULER}"
      fi
    else
      echo -e "   • Tipo de Mídia: ${GREEN}SSD / NVMe${NC} (Estado Sólido)"
      echo -e "   • Schedulers disponíveis: ${SCHEDULER}"
    fi
  done

  if [[ "${FOUND_DISKS}" -eq 0 ]]; then
    echo -e "${YELLOW}Nenhum dispositivo de bloco compatível encontrado em /sys/block/.${NC}"
  fi

  echo -e "\n${BLUE}==============================================================================${NC}"
  echo -e "${BLUE}📁 DIAGNÓSTICO DE OPÇÕES DE MONTAGEM (noatime / relatime)${NC}"
  echo -e "${BLUE}==============================================================================${NC}"

  if [[ -f /proc/mounts ]]; then
    local ATIME_WARNING=0
    while IFS= read -r line; do
      local FS_SPEC FS_FILE FS_VFSTYPE FS_MNTOPTS
      FS_SPEC="$(echo "${line}" | awk '{print $1}')"
      FS_FILE="$(echo "${line}" | awk '{print $2}')"
      FS_VFSTYPE="$(echo "${line}" | awk '{print $3}')"
      FS_MNTOPTS="$(echo "${line}" | awk '{print $4}')"

      # Filtrar sistemas de arquivos de dados relevantes
      if [[ "${FS_VFSTYPE}" =~ ^(ext4|xfs|btrfs|zfs)$ && "${FS_SPEC}" =~ ^/dev/ ]]; then
        printf "  • Ponto de montagem: %-15s (fs: %-5s, dev: %s)\n" "${FS_FILE}" "${FS_VFSTYPE}" "${FS_SPEC}"
        printf "    Opções ativas: %s\n" "${FS_MNTOPTS}"

        if [[ "${FS_MNTOPTS}" == *"noatime"* ]]; then
          echo -e "    Status atime: ${GREEN}✅ OTIMIZADO (noatime ativo)${NC} — Buscas não geram escritas de metadados."
        else
          ATIME_WARNING=1
          echo -e "    Status atime: ${YELLOW}⚠️  RELATIME/ATIME ATIVO${NC} — Toda leitura grava metadados no HD."
          echo -e "    Recomendação: Adicione ${GREEN}noatime,nodiratime${NC} no /etc/fstab para esta partição."
          echo -e "    Para aplicar temporariamente agora: ${GREEN}sudo mount -o remount,noatime ${FS_FILE}${NC}"
        fi
        echo ""
      fi
    done < /proc/mounts

    if [[ "${ATIME_WARNING}" -eq 0 ]]; then
      echo -e "${GREEN}✅ Todos os pontos de montagem monitorados já utilizam noatime!${NC}"
    fi
  fi

  echo -e "${BLUE}==============================================================================${NC}"
  echo -e "${BLUE}⚡ DIAGNÓSTICO DE APM / SPINDOWN (hdparm)${NC}"
  echo -e "${BLUE}==============================================================================${NC}"
  if command -v hdparm >/dev/null 2>&1; then
    echo -e "  • hdparm instalado: ${GREEN}Sim${NC}"
    echo -e "  • Dica para HDs com logs contínuos:"
    echo -e "    Desative o spindown e conserve o motor rodando estavelmente:"
    echo -e "    ${GREEN}sudo hdparm -B 254 /dev/sdX${NC}  (Desativa APM agressivo)"
    echo -e "    ${GREEN}sudo hdparm -S 0 /dev/sdX${NC}    (Desativa timeout de spindown)"
  else
    echo -e "  • hdparm instalado: ${YELLOW}Não${NC} (opcional: 'sudo apt install hdparm')"
    echo -e "    Recomendação: Evite configurar 'spindown' no Proxmox para o disco de logs,"
    echo -e "    pois o fluxo contínuo força ciclos desgastantes de liga/desliga da agulha."
  fi
  echo -e "${BLUE}==============================================================================${NC}\n"
}

generate_udev_rule() {
  local UDEV_FILE="/etc/udev/rules.d/60-hdd-scheduler.rules"

  if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}❌ Permissão negada.${NC} A criação de regras udev exige root."
    echo -e "Execute: ${GREEN}sudo $0 --generate-udev${NC}"
    exit 1
  fi

  echo -e "${BLUE}⚙️  Configurando regra udev persistente em:${NC} ${UDEV_FILE}"

  mkdir -p "$(dirname "${UDEV_FILE}")"
  cat <<'EOF' > "${UDEV_FILE}"
# Regra udev para Homelab: Forçar scheduler mq-deadline em discos mecânicos (rotational == 1)
# Protege a agulha contra head thrashing em HDs compartilhados com SO/Logs.
ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF

  echo -e "${GREEN}✅ Regra gravada com sucesso!${NC}"
  echo -e "Recarregando regras do kernel..."
  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload
    udevadm trigger --subsystem-match=block || true
    echo -e "${GREEN}✅ Regras udev aplicadas com sucesso!${NC}"
  else
    echo -e "${YELLOW}⚠️  Comando udevadm não encontrado. As regras serão ativadas no próximo boot.${NC}"
  fi

  echo -e "\nExecute ${GREEN}sudo $0 --check${NC} para confirmar o novo scheduler dos discos."
}

remount_noatime() {
  local DIR="${2:-}"
  if [[ -z "${DIR}" ]]; then
    echo -e "${RED}❌ Diretório não informado.${NC}"
    echo -e "Uso: ${GREEN}sudo $0 --remount-noatime /${NC} ou ${GREEN}sudo $0 --remount-noatime /mnt/storage${NC}"
    exit 1
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}❌ Permissão negada.${NC} Remount exige root."
    echo -e "Execute: ${GREEN}sudo $0 --remount-noatime ${DIR}${NC}"
    exit 1
  fi

  echo -e "${BLUE}⚙️  Aplicando remount com noatime em:${NC} ${DIR}"
  mount -o remount,noatime "${DIR}"
  echo -e "${GREEN}✅ Remount concluído com sucesso!${NC}"
  echo -e "${YELLOW}Lembrete:${NC} Para tornar permanente após reiniciar o Proxmox, edite ${CYAN}/etc/fstab${NC}"
  echo "e inclua 'noatime,nodiratime' nas opções da partição."
}

case "${ACTION}" in
  --check)
    check_disks
    ;;
  --generate-udev)
    generate_udev_rule
    ;;
  --remount-noatime)
    remount_noatime "$@"
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
