# Guia de Hardening e Boas Práticas Operacionais no Proxmox VE
## VictoriaLogs + Vector Homelab Observability Stack

Este guia consolida as diretrizes de segurança, otimização de kernel, contenção de I/O e governança operacional para execução da stack de observabilidade em ambientes **Proxmox Virtual Environment (PVE)** e Mini PCs com recursos restritos.

---

## 1. Topologia de Hospedagem: VM KVM vs Container LXC

A escolha do modelo de virtualização no Proxmox tem impacto direto na segurança e estabilidade da stack:

| Critério | VM KVM (Debian/Ubuntu) — **Recomendado** | Container LXC (Desprivilegiado) |
|---|---|---|
| **Isolamento de Kernel** | Total (kernel guest dedicado). Falhas ou explorações no container Docker não afetam o Proxmox host. | Compartilhado. O container compartilha o mesmo kernel do hipervisor Proxmox. |
| **Acesso ao Docker Socket** | Seguro. `/var/run/docker.sock` pertence à VM; risco contido dentro da VM. | Alto risco. Expor o socket Docker do host para um LXC compromete a segurança do hipervisor. |
| **Tuning de Sysctl / I/O** | 100% configurável dentro da VM sem afetar os nós do cluster. | Exige alterar sysctl globalmente no nó Proxmox host. |
| **Overhead de Recursos** | Mínimo (~150 MB de RAM adicionais para o SO da VM). | Quase zero overhead. |

> [!IMPORTANT]
> **Recomendação de Arquitetura:** Recomendamos utilizar uma **VM KVM enxuta (Debian 12 minimal ou Ubuntu Server)** com **1-2 vCPUs e 1-2 GB de RAM**. Essa abordagem garante isolamento absoluto, suporte nativo ao Docker sem permissões especiais de *nesting* e contenção contra vazamento de sockets.
>
> Caso opte por **LXC**, utilize obrigatoriamente container **desprivilegiado** (*unprivileged*) com `nesting=1,keyctl=1` e nunca monte sockets do sistema raiz do Proxmox diretamente no container.

---

## 2. Hardening e Parâmetros de Kernel (`sysctl`)

Bancos de dados colunares e pipelines de observabilidade de alto desempenho (como VictoriaLogs em Go e Vector em Rust) utilizam mapeamento em memória (`mmap`) e conexões TCP contínuas.

Crie o arquivo de configuração persistente no host (ou na VM):

```bash
sudo tee /etc/sysctl.d/99-observability.conf << 'EOF'
# ==============================================================================
# Tuning do Kernel para VictoriaLogs + Vector (Homelab / Proxmox)
# ==============================================================================

# 1. Mapeamento de Memória (essencial para o VictoriaLogs mmap)
# Previne erros de "out of memory" em chamadas de mmap sob carga
vm.max_map_count = 262144

# 2. Gestão de Memória Virtual e Swappiness
# Evita que o kernel faça swapping agressivo de dados em repouso
vm.swappiness = 10
vm.overcommit_memory = 1

# 3. Descritores de Arquivos e Monitoramento Inotify
# Garante descritores suficientes para arquivos de log e sockets TCP
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024

# 4. Conexões de Rede e Socket Backlog
# Melhora a capacidade de absorção de rajadas HTTP no coletor Vector
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fastopen = 3

# 5. Buffers de Leitura e Gravação TCP
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF
```

Aplique as configurações imediatamente sem reiniciar:
```bash
sudo sysctl --system
```

---

## 3. Otimizações de Filesystem e Contenção de I/O

Em Mini PCs de Homelab onde o Proxmox compartilha um único disco rígido mecânico (HD) ou um SSD modesto, a contenção de I/O é a principal causa de lentidão e congelamentos transitórios.

### 3.1 Eliminação de `atime` no Filesystem (`/etc/fstab`)
Por padrão, o Linux atualiza a data/hora de último acesso (`atime`) de cada arquivo lido. Ao realizar consultas no VictoriaLogs, milhares de pequenas peças de dados são lidas, gerando gravações parasitas de metadados.

Para eliminar essa sobrecarga:
1. Identifique a partição de dados do Proxmox / VM:
   ```bash
   df -h /
   ```
2. Edite `/etc/fstab` e adicione as opções `noatime,nodiratime`:
   ```text
   # Exemplo de partição ajustada:
   UUID=xxxx-xxxx-xxxx  /  ext4  errors=remount-ro,noatime,nodiratime  0  1
   ```
3. Remonte a partição ativa ou utilize o assistente automatizado da stack:
   ```bash
   sudo ./scripts/tune-disk-host.sh --remount-noatime /
   ```

### 3.2 Escalonador de I/O (`mq-deadline` para HDs)
Discos mecânicos exigem ordenação sequencial de cabeçote móvel (*elevator algorithm*). NVMe e SSDs operam com filas paralelas (`none` ou `kyber`).

Utilize a automação da stack para gerar regras `udev` seguras e persistentes:
```bash
sudo ./scripts/tune-disk-host.sh --apply-udev
```

### 3.3 Docker Daemon em Modo Assíncrono (`non-blocking`)
Se o Docker registrar logs de containers em modo síncrono padrão (`blocking`), qualquer pico de I/O no Proxmox (ex: backup noturno) trava as chamadas de sistema (`write(2)`) das aplicações.

Aplique a blindagem assíncrona com ring-buffer na memória:
```bash
sudo ./scripts/tune-docker-host.sh
```

Isso configura `/etc/docker/daemon.json` com:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "mode": "non-blocking",
    "max-buffer-size": "4m"
  }
}
```

---

## 4. Hardening de Containers e Isolamento no Docker Compose

A stack aplica parâmetros rigorosos de contenção para garantir que os containers nunca comprometam o host:

### 4.1 Isolamento do Docker Socket
- O coletor Vector necessita de visibilidade dos containers locais para captura de logs e eventos.
- A montagem no `docker-compose.yml` é estritamente **somente leitura**:
  ```yaml
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
  ```
- O flag `:ro` impede que um container comprometido envie chamadas de criação/remoção de containers para o daemon do host.

### 4.2 Limites Rígidos de Memória (Teto <= 150 MB)
Para evitar que tempestades acidentais de logs disparem o *Out of Memory (OOM) Killer* do Proxmox derrubando serviços essenciais, os limites são fixados no Compose:
- **VictoriaLogs:** `80 MB` de RAM (`deploy.resources.limits.memory: 80M`) combinada com `-memory.allowedPercent=60`.
- **Vector:** `60 MB` de RAM (`deploy.resources.limits.memory: 60M`).
- **Total combinado:** **140 MB**, com folga confortável dentro do teto de 150 MB.

### 4.3 Prevenção de Loop de Logs
- A fonte `docker_logs` do Vector inclui obrigatoriamente:
  ```yaml
  exclude_containers:
    - vector
  ```
- Isso elimina o risco de tempestade recursiva onde os logs gerados pelo próprio coletor seriam reingeridos indefinidamente.

### 4.4 Permissões de Arquivos no Host
Arquivos de configuração e segredos no host devem possuir permissões restritivas:
```bash
# Permissão estrita no .env (leitura/escrita apenas pelo proprietário)
chmod 600 .env

# Permissão de execução para os scripts operacionais
chmod 755 scripts/*.sh
```
> [!TIP]
> Você pode verificar e corrigir essas permissões automaticamente executando:
> ```bash
> ./scripts/audit-security.sh --fix
> ```

---

## 5. Hardening de Rede e Proxmox Firewall

Para proteger o painel web (VMUI), endpoints de ingestão e ferramentas de consulta contra acessos indevidos:

### 5.1 Regras de Proxmox Firewall (PVE GUI / CLI)
Se o firewall do Proxmox estiver ativo no Datacenter ou na VM:

1. **Permitir tráfego HTTP do VictoriaLogs apenas na LAN ou VPN:**
   - **Protocolo:** TCP
   - **Porta:** `9428`
   - **Origem (Source):** `192.168.0.0/24` (ou sub-rede da sua VPN WireGuard/Tailscale)
   - **Ação:** ACCEPT
2. **Permitir ingestão HTTP do Vector apenas de microsserviços autorizados:**
   - **Protocolo:** TCP
   - **Porta:** `8686`
   - **Origem (Source):** Sub-rede dos containers da LAN
   - **Ação:** ACCEPT
3. **Bloquear acesso externo direto:**
   - NUNCA exponha a porta `9428` ou `8686` diretamente na WAN (porta aberta no roteador) sem proxy reverso com TLS e autenticação.

### 5.2 Autenticação Básica (HTTP Basic Auth)
Quando a stack for acessada por múltiplos nós ou redes heterogêneas, ative a autenticação nativa no `.env`:
```env
VICTORIALOGS_AUTH_USERNAME=admin_homelab
VICTORIALOGS_AUTH_PASSWORD=coloque_uma_senha_forte_aqui
```
O VictoriaLogs rejeitará qualquer busca, exclusão de partição ou acesso à VMUI sem credenciais válidas.

---

## 6. Governança e Automação Operacional

A stack inclui utilitários integrados para manter o host auditado e protegido de forma contínua:

### 6.1 Auditoria de Conformidade Contínua
Execute a auditoria a qualquer momento para verificar permissões de host, integridade de compose e limites de runtime:
```bash
./scripts/audit-security.sh
```
Para validação em scripts ou esteiras automatizadas:
```bash
./scripts/audit-security.sh --strict
```

### 6.2 Rotina Diária de Manutenção e Backup Atômico
Agende o pipeline unificado de manutenção (auditoria de capacidade em disco, snapshot atômico e smoke test):
```bash
./scripts/run-maintenance-pipeline.sh --install-cron
```
O agendamento executa diariamente às 03:00 UTC e descarta preventivamente a rotina de backup caso o espaço livre em disco esteja em nível crítico.

### 6.3 Monitoramento 24/7 de Recursos e Ciclo de Vida
Instale os serviços de telemetria como daemons systemd no host:
```bash
sudo ./scripts/install-host-collectors.sh --install
```
Isso garante o envio contínuo de consumo de CPU/RAM (`service="docker-stats"`) e eventos de parada ou OOM (`service="docker-events"`) para o VictoriaLogs, permitindo diagnóstico forense imediato sem depender de ferramentas externas pesadas.

---

## 7. Checklist de Verificação

### Checklist Pré-Deploy (Novo Host Proxmox)
- [ ] VM KVM provisionada com Debian/Ubuntu (ou LXC desprivilegiado com `nesting=1`).
- [ ] `/etc/sysctl.d/99-observability.conf` configurado com `vm.max_map_count = 262144`.
- [ ] Filesystem montado com `noatime,nodiratime` no `/etc/fstab`.
- [ ] Docker daemon configurado em modo `non-blocking` (`/etc/docker/daemon.json`).
- [ ] Arquivo `.env` copiado de `.env.example` com permissões `600`.
- [ ] Docker Compose validado com `docker compose config`.
- [ ] Auditoria inicial executada: `./scripts/audit-security.sh`.

### Checklist de Manutenção Periódica (Mensal)
- [ ] Executar `./scripts/audit-security.sh --strict` para certificar que permissões não foram alteradas.
- [ ] Auditar retenção e partições diárias: `./scripts/manage-partitions.sh list`.
- [ ] Verificar integridade e rotação dos backups gerados em `backups/`.
- [ ] Checar saúde dos coletores de telemetria: `systemctl status victoria-docker-stats victoria-docker-events`.
