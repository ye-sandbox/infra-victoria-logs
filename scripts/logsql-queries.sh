#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs CLI — Painel de Consultas LogsQL Salvas
# ==============================================================================
# Utilitário de diagnóstico rápido via terminal que executa consultas analíticas
# pré-configuradas no VictoriaLogs com formatação visual rica ou exportação JSON.
#
# Comandos disponíveis:
#   top-errors        Exibe os containers e serviços com maior volume de erros
#   slow-requests     Lista requisições lentas (duration_ms > 1000)
#   http-status       Distribuição de status code HTTP (2xx, 4xx, 5xx)
#   crashes           Eventos do Docker Engine (OOMKilled, die, restart)
#   trace <ID>        Localiza todos os logs de uma transação pelo trace_id/request_id
#   stats-summary     Métricas de consumo de recursos dos containers (docker-stats)
#   raw "<QUERY>"     Executa uma query LogsQL customizada
#
# Opções gerais:
#   --time, -t <JANELA>    Janela de tempo LogsQL (ex: 5m, 15m, 1h, 24h, 7d). Padrão: 1h
#   --service, -s <NOME>   Filtra por um serviço ou container específico
#   --limit, -l <N>        Limite de registros retornados. Padrão: 20
#   --json                 Emite a saída bruta em JSON para scripts/agentes
#   --help, -h             Exibe esta ajuda
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
HOST="${VICTORIALOGS_HOST:-127.0.0.1}"
VL_URL="${VICTORIALOGS_URL:-http://${HOST}:${VICTORIALOGS_PORT}}"

# Configurar autenticação HTTP básica para curl se configurada
CURL_AUTH_OPTS=()
if [[ -n "${VICTORIALOGS_AUTH_USERNAME:-}" ]]; then
  CURL_AUTH_OPTS=(-u "${VICTORIALOGS_AUTH_USERNAME}:${VICTORIALOGS_AUTH_PASSWORD:-}")
fi

COMMAND=""
TIME_WINDOW="1h"
SERVICE_FILTER=""
LIMIT="20"
JSON_OUTPUT=false
EXTRA_PARAM=""

usage() {
  cat <<EOF
Uso: $(basename "$0") <COMANDO> [OPÇÕES]

Comandos:
  top-errors           Agrupa e conta erros por serviço na janela de tempo
  slow-requests        Lista requisições HTTP lentas ordenadas por duração
  http-status          Exibe distribuição de respostas HTTP por código de status
  crashes              Containers finalizados por OOM ou encerramento anormal
  trace <ID>           Rastreia transações pelo trace_id ou request_id
  stats-summary        Métricas mais recentes de CPU e memória (docker-stats)
  raw "<QUERY>"        Executa consulta LogsQL customizada

Opções:
  -t, --time <JANELA>      Janela de tempo (ex: 5m, 15m, 1h, 6h, 24h, 7d). Padrão: 1h
  -s, --service <NOME>     Filtra logs de um serviço ou container específico
  -l, --limit <N>          Quantidade máxima de linhas retornadas. Padrão: 20
  --json                   Gera a saída em formato JSON puro (ideal para pipelines e agentes)
  -h, --help               Exibe esta mensagem de ajuda

Exemplos:
  $(basename "$0") top-errors --time 24h
  $(basename "$0") slow-requests --service api-gateway -l 10
  $(basename "$0") trace tr-abc-12345
  $(basename "$0") raw 'level:"error" AND service:"whatsapp-api"' --time 15m
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

# Parsing de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    top-errors|slow-requests|http-status|crashes|stats-summary)
      COMMAND="$1"
      shift
      ;;
    trace|raw)
      COMMAND="$1"
      if [[ $# -lt 2 || "$2" =~ ^- ]]; then
        echo "❌ Erro: O comando '$1' requer um argumento (ID ou Query)."
        exit 1
      fi
      EXTRA_PARAM="$2"
      shift 2
      ;;
    -t|--time)
      TIME_WINDOW="$2"
      shift 2
      ;;
    -s|--service)
      SERVICE_FILTER="$2"
      shift 2
      ;;
    -l|--limit)
      LIMIT="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "❌ Opção ou comando desconhecido: $1"
      usage
      exit 1
      ;;
  esac
done

# Checa se o comando foi informado
if [[ -z "${COMMAND}" ]]; then
  echo "❌ Nenhum comando informado."
  usage
  exit 1
fi

# Constrói a query LogsQL de acordo com o comando
QUERY=""
case "${COMMAND}" in
  top-errors)
    QUERY='level:"error"'
    if [[ -n "${SERVICE_FILTER}" ]]; then
      QUERY="${QUERY} AND (service:\"${SERVICE_FILTER}\" OR container_name:\"${SERVICE_FILTER}\")"
    fi
    QUERY="${QUERY} AND _time:${TIME_WINDOW} | stats by (service, app) count() as total_errors | sort by (total_errors desc)"
    ;;

  slow-requests)
    QUERY='duration_ms:>1000'
    if [[ -n "${SERVICE_FILTER}" ]]; then
      QUERY="${QUERY} AND (service:\"${SERVICE_FILTER}\" OR container_name:\"${SERVICE_FILTER}\")"
    fi
    QUERY="${QUERY} AND _time:${TIME_WINDOW} | sort by (duration_ms desc)"
    ;;

  http-status)
    QUERY='exists(http_status)'
    if [[ -n "${SERVICE_FILTER}" ]]; then
      QUERY="${QUERY} AND (service:\"${SERVICE_FILTER}\" OR container_name:\"${SERVICE_FILTER}\")"
    fi
    QUERY="${QUERY} AND _time:${TIME_WINDOW} | stats by (http_status, service) count() as total_requests | sort by (total_requests desc)"
    ;;

  crashes)
    QUERY='_stream:{service="docker-events"} AND (oom_killed:"true" OR exit_code:!"0" OR action:"die" OR action:"oom")'
    if [[ -n "${SERVICE_FILTER}" ]]; then
      QUERY="${QUERY} AND container_name:\"${SERVICE_FILTER}\""
    fi
    QUERY="${QUERY} AND _time:${TIME_WINDOW} | sort by (_time desc)"
    ;;

  trace)
    ID="${EXTRA_PARAM}"
    QUERY="trace_id:\"${ID}\" OR request_id:\"${ID}\" OR \"${ID}\""
    if [[ -n "${SERVICE_FILTER}" ]]; then
      QUERY="(${QUERY}) AND (service:\"${SERVICE_FILTER}\" OR container_name:\"${SERVICE_FILTER}\")"
    fi
    QUERY="${QUERY} AND _time:${TIME_WINDOW} | sort by (_time asc)"
    ;;

  stats-summary)
    QUERY='_stream:{service="docker-stats"}'
    if [[ -n "${SERVICE_FILTER}" ]]; then
      QUERY="${QUERY} AND container_name:\"${SERVICE_FILTER}\""
    fi
    QUERY="${QUERY} AND _time:${TIME_WINDOW} | sort by (_time desc)"
    ;;

  raw)
    QUERY="${EXTRA_PARAM}"
    if [[ -n "${SERVICE_FILTER}" ]]; then
      QUERY="(${QUERY}) AND (service:\"${SERVICE_FILTER}\" OR container_name:\"${SERVICE_FILTER}\")"
    fi
    if [[ "${QUERY}" != *"_time:"* ]]; then
      QUERY="${QUERY} AND _time:${TIME_WINDOW}"
    fi
    ;;
esac

# Executa consulta HTTP contra o VictoriaLogs
ENDPOINT="${VL_URL}/select/logsql/query"
RAW_RESPONSE=$(curl "${CURL_AUTH_OPTS[@]}" -s -G "${ENDPOINT}" \
  --data-urlencode "query=${QUERY}" \
  --data-urlencode "limit=${LIMIT}" || true)

if [[ -z "${RAW_RESPONSE}" ]]; then
  if [[ "${JSON_OUTPUT}" == "true" ]]; then
    echo "[]"
  else
    echo "ℹ️ Nenhum log encontrado para o filtro e janela informados."
  fi
  exit 0
fi

# Se requisitado JSON, processa e emite array JSON
if [[ "${JSON_OUTPUT}" == "true" ]]; then
  echo "${RAW_RESPONSE}" | python3 -c "
import sys, json
lines = [json.loads(line) for line in sys.stdin if line.strip()]
print(json.dumps(lines, indent=2, ensure_ascii=False))
"
  exit 0
fi

# Renderização formatada para terminal humano/operador
echo "================================================================================"
echo "📊 [VictoriaLogs Query CLI] Comando: ${COMMAND} | Janela: ${TIME_WINDOW} | Limite: ${LIMIT}"
echo "🔍 LogsQL: ${QUERY}"
echo "================================================================================"

python3 -c "
import sys, json

lines = [line.strip() for line in sys.stdin if line.strip()]
if not lines:
    print('ℹ️ Nenhum registro retornado.')
    sys.exit(0)

cmd = '${COMMAND}'
print(f'Total de registros retornados: {len(lines)}\n')

if cmd == 'top-errors':
    print(f'{\"SERVIÇO / APP\":<35} | {\"TOTAL DE ERROS\":<15}')
    print('-' * 55)
    for l in lines:
        d = json.loads(l)
        svc = d.get('service') or d.get('app') or 'unknown'
        cnt = d.get('total_errors', '0')
        print(f'{svc:<35} | {cnt:<15}')

elif cmd == 'http-status':
    print(f'{\"STATUS\":<10} | {\"SERVIÇO\":<30} | {\"TOTAL\":<10}')
    print('-' * 55)
    for l in lines:
        d = json.loads(l)
        st = str(d.get('http_status', '-'))
        svc = str(d.get('service', '-'))
        cnt = str(d.get('total_requests', '0'))
        print(f'{st:<10} | {svc:<30} | {cnt:<10}')

elif cmd == 'slow-requests':
    print(f'{\"HORÁRIO UTC\":<25} | {\"DURAÇÃO\":<12} | {\"STATUS\":<8} | {\"SERVIÇO\":<20} | {\"MENSAGEM\"}')
    print('-' * 85)
    for l in lines:
        d = json.loads(l)
        ts = d.get('_time', '')[:19].replace('T', ' ')
        dur = f\"{d.get('duration_ms', '-')} ms\"
        st = str(d.get('http_status', '-'))
        svc = str(d.get('service', 'unknown'))
        msg = d.get('_msg', d.get('message', ''))[:40]
        print(f'{ts:<25} | {dur:<12} | {st:<8} | {svc:<20} | {msg}')

elif cmd == 'crashes':
    print(f'{\"HORÁRIO UTC\":<25} | {\"CONTAINER\":<25} | {\"AÇÃO\":<10} | {\"EXIT\":<6} | {\"OOM?\":<6} | {\"MENSAGEM\"}')
    print('-' * 85)
    for l in lines:
        d = json.loads(l)
        ts = d.get('_time', '')[:19].replace('T', ' ')
        cname = str(d.get('container_name', 'unknown'))
        act = str(d.get('action', '-'))
        exit_c = str(d.get('exit_code', '-'))
        oom = str(d.get('oom_killed', '-'))
        msg = d.get('_msg', d.get('message', ''))[:40]
        print(f'{ts:<25} | {cname:<25} | {act:<10} | {exit_c:<6} | {oom:<6} | {msg}')

elif cmd == 'trace':
    print(f'{\"HORÁRIO UTC\":<24} | {\"LEVEL\":<7} | {\"SERVIÇO\":<18} | {\"MENSAGEM\"}')
    print('-' * 85)
    for l in lines:
        d = json.loads(l)
        ts = d.get('_time', '')[:19].replace('T', ' ')
        lvl = str(d.get('level', 'info')).upper()
        svc = str(d.get('service', 'unknown'))
        msg = d.get('_msg', d.get('message', ''))
        print(f'{ts:<24} | {lvl:<7} | {svc:<18} | {msg}')

elif cmd == 'stats-summary':
    print(f'{\"HORÁRIO UTC\":<20} | {\"CONTAINER\":<25} | {\"CPU %\":<10} | {\"RAM USADA\":<15} | {\"RAM %\":<10}')
    print('-' * 85)
    for l in lines:
        d = json.loads(l)
        ts = d.get('_time', '')[:19].replace('T', ' ')
        cname = str(d.get('container_name', 'unknown'))
        cpu = f\"{d.get('cpu_percent', '-')} %\"
        mem = f\"{d.get('mem_usage_mb', '-')} MB\"
        memp = f\"{d.get('mem_percent', '-')} %\"
        print(f'{ts:<20} | {cname:<25} | {cpu:<10} | {mem:<15} | {memp:<10}')

else:
    for idx, l in enumerate(lines, 1):
        d = json.loads(l)
        ts = d.get('_time', '')
        lvl = d.get('level', 'info')
        msg = d.get('_msg', d.get('message', ''))
        print(f'[{idx}] {ts} [{lvl.upper()}]: {msg}')
" <<< "${RAW_RESPONSE}"

echo "================================================================================"
