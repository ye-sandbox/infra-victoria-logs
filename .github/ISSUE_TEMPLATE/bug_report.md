---
name: Bug report
about: Relate um problema ou comportamento inesperado na stack
title: "[BUG] "
labels: bug
assignees: ''
---

### Descrição do Problema
Uma descrição clara e concisa do que aconteceu.

### Ambiente de Execução
- **Hardware:** (ex: Mini PC Intel NUC, Raspberry Pi 4, Servidor Dell)
- **Tipo de Armazenamento:** (ex: HD Mecânico SATA, SSD NVMe, USB externo)
- **Perfil Utilizado:** (ex: `STORAGE_PROFILE=hdd`, `ssd` ou `geoip`)
- **Sistema Operacional / Hipervisor:** (ex: Proxmox VE 8.2 VM Debian 12, Ubuntu 24.04 bare metal)
- **Versão do Docker & Docker Compose:** (`docker --version`, `docker compose version`)
- **Versão da Stack:** (ex: `v1.0.0` ou commit específico)

### Passos para Reproduzir
1. Configurei o `.env` com '...'
2. Executei o comando '...'
3. Ocorreu o erro '...'

### Comportamento Esperado
Uma descrição clara do que você esperava que acontecesse.

### Logs Relevantes
Cole abaixo os logs relevantes do VictoriaLogs ou Vector (omitindo senhas ou dados sensíveis):
```text
docker compose logs victorialogs
docker compose logs vector
```

### Contexto Adicional
Adicione qualquer outro contexto, saída de `./scripts/audit-security.sh` ou capturas de tela sobre o problema.
