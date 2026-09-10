# Exemplos e Templates de Logging Canônico (VictoriaLogs + Vector)

Este diretório contém templates de código plug-and-play prontos para uso nos projetos da organização `ye-sandbox`.

Cada exemplo implementa com rigor o contrato canônico esperado pelo pipeline **VictoriaLogs + Vector**:
- **NDJSON Puro:** exatamente 1 objeto JSON por linha no `stdout`, sem quebras intermediárias ou formatações *pretty*.
- **Campos Canônicos Base:** `timestamp` (ISO-8601 UTC), `level` (minúsculo), `service`, `app`, `env`, `message`.
- **Campos Canônicos de Correlação:** `trace_id`, `request_id`, `http_status`, `duration_ms` no primeiro nível para filtros diretos no LogsQL (`http_status:>=500`, `duration_ms:>1000`).
- **Tratamento de Exceções:** stack traces serializados dentro de `stack_trace` ou no mesmo registro, sem quebrar linhas adicionais avulsas.

---

## 📂 Templates Disponíveis

### 1. [Python com Loguru](./python-loguru) *(Recomendado para Python moderno/FastAPI)*
- Utiliza a biblioteca `loguru`.
- Sink personalizado que formata o evento conforme o contrato canônico.
- Suporte nativo a contexto via `logger.bind(...)` e captura de exceções via `logger.exception(...)`.
- Ver: [`python-loguru/logger.py`](./python-loguru/logger.py) e [`python-loguru/example_usage.py`](./python-loguru/example_usage.py).

### 2. [Python Standard Library](./python-stdlib) *(Zero dependências)*
- Utiliza a biblioteca nativa `logging` do Python.
- Formatador customizado `VictoriaLogsJsonFormatter`.
- Ideal para scripts leves, utilitários CLI ou microsserviços sem dependências de terceiros.
- Ver: [`python-stdlib/logger.py`](./python-stdlib/logger.py).

### 3. [Node.js com Pino](./nodejs-pino) *(Recomendado para Node/TypeScript)*
- Utiliza `pino` de altíssima performance.
- Configuração sem `pino-pretty` para produção.
- Suporte a loggers filhos (`logger.child(...)`) para rastreamento de requisições.
- Ver: [`nodejs-pino/logger.js`](./nodejs-pino/logger.js) e [`nodejs-pino/example.js`](./nodejs-pino/example.js).

### 4. [Go com `slog`](./go-slog) *(Go 1.21+ nativo)*
- Utiliza o pacote padrão `log/slog` da linguagem Go.
- `ReplaceAttr` configurado para compatibilidade com o schema VictoriaLogs.
- Ver: [`go-slog/main.go`](./go-slog/main.go).

---

## 🚀 Como testar localmente

Para verificar que um script emite NDJSON válido que passa pelo coletor:

```bash
# Teste Python Stdlib
python3 python-stdlib/logger.py | python3 -c "import sys, json; [json.loads(line) for line in sys.stdin]; print('NDJSON validado!')"

# Teste Python Loguru (necessita pip install loguru)
python3 python-loguru/example_usage.py | python3 -c "import sys, json; [json.loads(line) for line in sys.stdin]; print('NDJSON validado!')"
```
