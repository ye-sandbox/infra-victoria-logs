#!/usr/bin/env bash
# ==============================================================================
# Host Disk & I/O Scheduler Tuning Assistant (Physical & Virtual Environments)
# ==============================================================================
# Este script inspeciona discos no host Proxmox/Linux/VM e diagnostica:
# 1. Detecção de ambiente (Bare-metal físico vs Máquina Virtual / Hipervisor).
# 2. I/O Scheduler:
#    - Discos Virtuais (VMs/Guests): recomenda 'none' (evita duplo agendamento).
#    - HDs Rotacionais Físicos: recomenda 'mq-deadline' ou 'bfq' (anti-thrashing).
#    - SSDs/NVMes Físicos: recomenda 'none' / padrão do kernel.
# 3. Opções de montagem de filesystem (prioriza 'noatime' vs 'relatime').
# 4. Políticas de APM e Spindown (hdparm) para HDs físicos (omitido em VMs).
#
# Uso:
#   sudo ./scripts/tune-disk-host.sh --check           (Diagnóstico completo)
#   sudo ./scripts/tune-disk-host.sh --generate-udev   (Persiste scheduler ideal via udev)
#   sudo ./scripts/tune-disk-host.sh --remount-noatime / (Remount temporário com noatime)
# ==============================================================================

set -euo pipefail

ACTION="${1:---check}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

IS_SYSTEM_VIRTUAL=0
VIRT_TYPE="none"

detect_virtualization() {
  IS_SYSTEM_VIRTUAL=0
  VIRT_TYPE="none"

  # 1. Checagem primária: systemd-detect-virt
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    local DETECTED
    DETECTED="$(systemd-detect-virt 2>/dev/null || echo "none")"
    if [[ "${DETECTED}" != "none" && -n "${DETECTED}" ]]; then
      IS_SYSTEM_VIRTUAL=1
      VIRT_TYPE="${DETECTED}"
      return 0
    fi
  fi

  # 2. Checagem secundária: DMI / sysfs (product, vendor, bios)
  local DMI_PRODUCT="" DMI_SYS_VENDOR="" DMI_BIOS_VENDOR="" DMI_BOARD=""
  [[ -f /sys/class/dmi/id/product_name ]] && DMI_PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
  [[ -f /sys/class/dmi/id/sys_vendor ]] && DMI_SYS_VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  [[ -f /sys/class/dmi/id/bios_vendor ]] && DMI_BIOS_VENDOR="$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null || true)"
  [[ -f /sys/class/dmi/id/board_vendor ]] && DMI_BOARD="$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || true)"

  local DMI_COMBINED="${DMI_PRODUCT} ${DMI_SYS_VENDOR} ${DMI_BIOS_VENDOR} ${DMI_BOARD}"
  if echo "${DMI_COMBINED}" | grep -Eiq 'QEMU|KVM|VirtualBox|VMware|Bochs|OpenStack|Xen|Microsoft Corporation|Virtual Machine'; then
    IS_SYSTEM_VIRTUAL=1
    if echo "${DMI_COMBINED}" | grep -Eiq 'QEMU|KVM'; then
      VIRT_TYPE="kvm/qemu"
    elif echo "${DMI_COMBINED}" | grep -Eiq 'VirtualBox'; then
      VIRT_TYPE="virtualbox"
    elif echo "${DMI_COMBINED}" | grep -Eiq 'VMware'; then
      VIRT_TYPE="vmware"
    elif echo "${DMI_COMBINED}" | grep -Eiq 'Xen'; then
      VIRT_TYPE="xen"
    elif echo "${DMI_COMBINED}" | grep -Eiq 'Microsoft'; then
      VIRT_TYPE="hyper-v"
    else
      VIRT_TYPE="vm-generic"
    fi
    return 0
  fi

  return 0
}

is_virtual_device() {
  local dev_name="$1"
  local dev_path="$2"
  local model="$3"

  # Prefixos nativos de virtualização VirtIO / Xen
  if [[ "${dev_name}" =~ ^vd[a-z] || "${dev_name}" =~ ^xvd[a-z] ]]; then
    return 0
  fi

  # Vendor ou modelo com indicador de emulação virtual
  local VENDOR=""
  if [[ -f "${dev_path}/device/vendor" ]]; then
    VENDOR="$(cat "${dev_path}/device/vendor" 2>/dev/null | xargs || true)"
  fi

  local CHECK_STR="${model} ${VENDOR}"
  if echo "${CHECK_STR}" | grep -Eiq 'QEMU|VBOX|VMware|Virtual|VIRTIO|XEN'; then
    return 0
  fi

  # Se o sistema todo for virtualizado e for um disco sd*
  if [[ "${IS_SYSTEM_VIRTUAL}" -eq 1 ]]; then
    if [[ "${dev_name}" =~ ^sd[a-z] ]]; then
      return 0
    fi
  fi

  return 1
}

show_help() {
  cat <<EOF
Uso: $0 [OPÇÃO]

Opções:
  --check               Realiza inspeção e diagnóstico dos discos e montagens (não altera nada)
  --generate-udev       Cria regra udev persistente para o scheduler ideal (none em VMs, mq-deadline em HDs físicos)
  --remount-noatime DIR Executa remount do diretório especificado adicionando a flag noatime
  -h, --help            Exibe esta mensagem de ajuda

Exemplos:
  sudo $0 --check
  sudo $0 --generate-udev
  sudo $0 --remount-noatime /
EOF
}

check_disks() {
  detect_virtualization

  echo -e "${BLUE}==============================================================================${NC}"
  echo -e "${BLUE}🔍 DIAGNÓSTICO DE DISCOS E I/O SCHEDULER DO HOST${NC}"
  echo -e "${BLUE}==============================================================================${NC}"

  if [[ "${IS_SYSTEM_VIRTUAL}" -eq 1 ]]; then
    echo -e "🖥️  Ambiente Detectado : ${CYAN}${BOLD}Máquina Virtual / Guest (${VIRT_TYPE})${NC}"
    echo -e "ℹ️  Nota de Arquitetura: Em VMs, o agendamento de I/O em hardware físico é delegado ao hipervisor."
  else
    echo -e "🖥️  Ambiente Detectado : ${GREEN}${BOLD}Host Físico Bare-Metal${NC}"
  fi
  echo -e "${BLUE}------------------------------------------------------------------------------${NC}"

  local FOUND_DISKS=0
  local PHYSICAL_ROTATIONAL_COUNT=0
  local VIRTUAL_DISKS_COUNT=0

  local SCRIPT_NAME="${0##*/}"
  if [[ "${SCRIPT_NAME}" =~ ^(bash|sh|zsh)$ ]]; then
    SCRIPT_NAME="./scripts/tune-disk-host.sh"
  else
    SCRIPT_NAME="$0"
  fi

  for dev_path in /sys/block/sd* /sys/block/vd* /sys/block/nvme*n1 /sys/block/xvd*; do
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
    local ACTIVE_SCHED="não suportado"
    if [[ -f "${dev_path}/queue/scheduler" ]]; then
      SCHEDULER="$(cat "${dev_path}/queue/scheduler" 2>/dev/null || echo "não suportado")"
      if [[ "${SCHEDULER}" =~ \[([^]]+)\] ]]; then
        ACTIVE_SCHED="${BASH_REMATCH[1]}"
      fi
    fi

    local IS_VIRT_DEV=0
    if is_virtual_device "${DEV_NAME}" "${dev_path}" "${MODEL}"; then
      IS_VIRT_DEV=1
      VIRTUAL_DISKS_COUNT=$(( VIRTUAL_DISKS_COUNT + 1 ))
    fi

    echo -e "\n📌 Dispositivo: ${CYAN}/dev/${DEV_NAME}${NC} (${MODEL}, ~${SIZE_GB} GB)"

    if [[ "${IS_VIRT_DEV}" -eq 1 ]]; then
      echo -e "   • Tipo de Mídia: ${CYAN}🖥️  Disco Virtualizado${NC} (Controladora emulada/paravirtualizada)"
      echo -e "   • Nota: O tipo de mídia física subjacente (NVMe/SSD/HDD) é gerenciado pelo hipervisor host."
      echo -e "   • Schedulers disponíveis: ${SCHEDULER}"

      if [[ "${SCHEDULER}" == *"[none]"* ]]; then
        echo -e "   • Avaliação de I/O: ${GREEN}✅ EXCELENTE${NC} — Scheduler [none] (passthrough/NOOP) ativo."
        echo -e "     Evita sobrecarga de duplo agendamento de I/O entre o guest e o hipervisor físico."
      elif [[ "${SCHEDULER}" == *"[mq-deadline]"* || "${SCHEDULER}" == *"[bfq]"* ]]; then
        echo -e "   • Avaliação de I/O: ${YELLOW}ℹ️  SCHEDULER COMPLEXO EM VM${NC} — Está ativo [${ACTIVE_SCHED}]."
        echo -e "     Em discos virtuais, recomenda-se ${GREEN}[none]${NC} para delegar o escalonamento ao hipervisor."
        echo -e "     Para aplicar de forma persistente no guest, execute: ${GREEN}sudo ${SCRIPT_NAME} --generate-udev${NC}"
      else
        echo -e "   • Avaliação de I/O: Scheduler atual: [${ACTIVE_SCHED}]"
      fi

    elif [[ "${ROTATIONAL}" == "1" ]]; then
      PHYSICAL_ROTATIONAL_COUNT=$(( PHYSICAL_ROTATIONAL_COUNT + 1 ))
      echo -e "   • Tipo de Mídia: ${YELLOW}💾 HD Mecânico Rotacional Físico${NC} (Agulha móvel)"
      echo -e "   • Schedulers disponíveis: ${SCHEDULER}"

      if [[ "${SCHEDULER}" == *"[mq-deadline]"* || "${SCHEDULER}" == *"[bfq]"* ]]; then
        echo -e "   • Avaliação de I/O: ${GREEN}✅ EXCELENTE${NC} — Algoritmo de elevador [${ACTIVE_SCHED}] ativo para HD físico."
      elif [[ "${SCHEDULER}" == *"[none]"* ]]; then
        echo -e "   • Avaliação de I/O: ${RED}⚠️  INEFICIENTE${NC} — O scheduler está em [none] (padrão NVMe)."
        echo -e "     Em HD mecânico físico, 'none' provoca head thrashing. Recomenda-se: ${GREEN}mq-deadline${NC} ou ${GREEN}bfq${NC}."
        echo -e "     Para corrigir de forma persistente, execute: ${GREEN}sudo ${SCRIPT_NAME} --generate-udev${NC}"
      else
        echo -e "   • Avaliação de I/O: Scheduler atual: [${ACTIVE_SCHED}]"
      fi

    else
      echo -e "   • Tipo de Mídia: ${GREEN}⚡ SSD / NVMe Físico${NC} (Estado Sólido)"
      echo -e "   • Schedulers disponíveis: ${SCHEDULER}"
      if [[ "${SCHEDULER}" == *"[none]"* ]]; then
        echo -e "   • Avaliação de I/O: ${GREEN}✅ EXCELENTE${NC} — Scheduler [none] adequado para SSD/NVMe."
      else
        echo -e "   • Avaliação de I/O: Scheduler atual: [${ACTIVE_SCHED}]"
      fi
    fi
  done

  if [[ "${FOUND_DISKS}" -eq 0 ]]; then
    echo -e "${YELLOW}Nenhum dispositivo de bloco compatível encontrado em /sys/block/.${NC}"
  fi

  echo -e "
${BLUE}==============================================================================${NC}"
  echo -e "${BLUE}📁 DIAGNÓSTICO DE OPÇÕES DE MONTAGEM (noatime / relatime)${NC}"
  echo -e "${BLUE}==============================================================================${NC}"
  echo -e "ℹ️  Otimização crítica tanto para bare-metal quanto para VMs (elimina writes de atime em logs)."

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
        printf "  • Ponto de montagem: %-15s (fs: %-5s, dev: %s)
" "${FS_FILE}" "${FS_VFSTYPE}" "${FS_SPEC}"
        printf "    Opções ativas: %s
" "${FS_MNTOPTS}"

        if [[ "${FS_MNTOPTS}" == *"noatime"* ]]; then
          echo -e "    Status atime: ${GREEN}✅ OTIMIZADO (noatime ativo)${NC} — Buscas e consultas não geram escritas de metadados."
        else
          ATIME_WARNING=1
          echo -e "    Status atime: ${YELLOW}⚠️  RELATIME/ATIME ATIVO${NC} — Toda leitura grava metadados no armazenamento."
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

  if [[ "${IS_SYSTEM_VIRTUAL}" -eq 1 || "${PHYSICAL_ROTATIONAL_COUNT}" -eq 0 ]]; then
    echo -e "  • Diagnóstico omitido: ${CYAN}Ambiente Virtualizado ou Sem HD Mecânico Físico${NC}"
    echo -e "    Discos virtuais/emulados não possuem motores mecânicos nem respondem a comandos ioctl de APM/Spindown."
    echo -e "    O gerenciamento de energia e rotação de discos físicos subjacentes deve ser feito no host Proxmox/hipervisor."
  else
    if command -v hdparm >/dev/null 2>&1; then
      echo -e "  • hdparm instalado: ${GREEN}Sim${NC}"
      echo -e "  • Dica para HDs físicos rotacionais com fluxo de logs contínuo:"
      echo -e "    Desative o spindown e conserve o motor rodando estavelmente:"
      echo -e "    ${GREEN}sudo hdparm -B 254 /dev/sdX${NC}  (Desativa APM agressivo)"
      echo -e "    ${GREEN}sudo hdparm -S 0 /dev/sdX${NC}    (Desativa timeout de spindown)"
    else
      echo -e "  • hdparm instalado: ${YELLOW}Não${NC} (opcional: 'sudo apt install hdparm')"
      echo -e "    Recomendação: Evite configurar 'spindown' no host para o disco de logs,"
      echo -e "    pois o fluxo contínuo força ciclos desgastantes de liga/desliga da agulha mecânica."
    fi
  fi
  echo -e "${BLUE}==============================================================================${NC}
"
}

generate_udev_rule() {
  detect_virtualization

  local UDEV_FILE="/etc/udev/rules.d/60-disk-scheduler.rules"
  local LEGACY_UDEV_FILE="/etc/udev/rules.d/60-hdd-scheduler.rules"

  if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}❌ Permissão negada.${NC} A criação de regras udev exige root."
    echo -e "Execute: ${GREEN}sudo $0 --generate-udev${NC}"
    exit 1
  fi

  # Remover arquivo de regra legado que causa conflito por ordenação alfabética
  if [[ -f "${LEGACY_UDEV_FILE}" ]]; then
    echo -e "🧹 Removendo regra udev legada conflitante: ${LEGACY_UDEV_FILE}"
    rm -f "${LEGACY_UDEV_FILE}"
  fi

  echo -e "${BLUE}⚙️  Configurando regra udev persistente em:${NC} ${UDEV_FILE}"
  mkdir -p "$(dirname "${UDEV_FILE}")"

  local TARGET_SCHED="none"
  if [[ "${IS_SYSTEM_VIRTUAL}" -eq 1 ]]; then
    echo -e "🖥️  Ambiente Virtualizado detectado (${VIRT_TYPE}). Aplicando scheduler [none] para evitar duplo agendamento..."
    cat <<'EOF' > "${UDEV_FILE}"
# Regra udev para Guest Virtualizado (VM): Forçar scheduler 'none' (passthrough/NOOP)
# Evita sobrecarga de duplo agendamento de I/O entre o guest e o hipervisor host.
ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]", ATTR{queue/scheduler}="none"
EOF
  else
    TARGET_SCHED="mq-deadline"
    echo -e "🖥️  Ambiente Físico Bare-Metal detectado. Aplicando scheduler [mq-deadline] apenas para HDs mecânicos rotacionais..."
    cat <<'EOF' > "${UDEV_FILE}"
# Regra udev para Homelab Físico: Forçar scheduler mq-deadline apenas em HDs mecânicos rotacionais físicos
# Protege a agulha móvel contra head thrashing em discos compartilhados com SO/Logs.
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF
  fi

  echo -e "${GREEN}✅ Regra gravada com sucesso!${NC}"

  # Aplicar imediatamente no kernel para dispositivos de bloco ativos
  echo -e "Aplicando scheduler [${TARGET_SCHED}] imediatamente nos dispositivos ativos..."
  for dev_dir in /sys/block/*; do
    [[ -e "${dev_dir}" ]] || continue
    local dev_name
    dev_name=$(basename "${dev_dir}")
    [[ "${dev_name}" =~ ^(sd[a-z]|vd[a-z]|xvd[a-z])$ ]] || continue

    local sched_file="${dev_dir}/queue/scheduler"
    if [[ -w "${sched_file}" ]]; then
      local avail_sched
      avail_sched=$(cat "${sched_file}" 2>/dev/null || true)
      if [[ "${IS_SYSTEM_VIRTUAL}" -eq 1 ]]; then
        if [[ "${avail_sched}" == *"none"* ]]; then
          echo "${TARGET_SCHED}" > "${sched_file}" 2>/dev/null && echo -e "  • /dev/${dev_name}: scheduler ativado imediatamente como [${TARGET_SCHED}]"
        fi
      else
        local is_rot=0
        [[ -f "${dev_dir}/queue/rotational" ]] && is_rot=$(cat "${dev_dir}/queue/rotational")
        if [[ "${is_rot}" -eq 1 && "${avail_sched}" == *"mq-deadline"* ]]; then
          echo "${TARGET_SCHED}" > "${sched_file}" 2>/dev/null && echo -e "  • /dev/${dev_name}: scheduler ativado imediatamente como [${TARGET_SCHED}]"
        fi
      fi
    fi
  done

  echo -e "Recarregando regras do kernel..."
  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload
    udevadm trigger --action=change --subsystem-match=block || true
    echo -e "${GREEN}✅ Regras udev recarregadas com sucesso!${NC}"
  else
    echo -e "${YELLOW}⚠️  Comando udevadm não encontrado. As regras serão ativadas no próximo boot.${NC}"
  fi

  echo -e "
Execute ${GREEN}sudo $0 --check${NC} para confirmar o novo scheduler dos discos."
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
  echo -e "${YELLOW}Lembrete:${NC} Para tornar permanente após reiniciar o Proxmox/Linux, edite ${CYAN}/etc/fstab${NC}"
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
