"""
Exemplo de uso do logger Loguru com contrato canônico do VictoriaLogs + Vector.
"""

from logger import logger

def process_order(order_id: str, request_id: str, trace_id: str):
    # Log com contexto de rastreamento distribuído e dados da requisição
    req_logger = logger.bind(
        request_id=request_id,
        trace_id=trace_id,
        order_id=order_id,
        customer_id="cust-9876",
    )

    req_logger.info("Iniciando processamento do pedido")

    try:
        if order_id == "invalid":
            raise ValueError("Valor do pedido inválido ou saldo insuficiente")

        # Simulação de sucesso com métricas HTTP
        req_logger.bind(
            http_status=200,
            duration_ms=45.2,
        ).info("Pedido processado com sucesso")

    except Exception:
        # Exceção com stack trace capturado e serializado em 1 linha
        req_logger.bind(
            http_status=400,
            duration_ms=12.8,
        ).exception("Falha ao liquidar pagamento do pedido")


if __name__ == "__main__":
    logger.info("Aplicação inicializada com sucesso")

    # Requisição bem-sucedida
    process_order(order_id="ord-1001", request_id="req-abc-123", trace_id="trace-xyz-789")

    # Requisição com erro
    process_order(order_id="invalid", request_id="req-err-456", trace_id="trace-xyz-000")
