"""
Example usage of Loguru logger with VictoriaLogs + Vector canonical contract.
"""

from logger import logger

def process_order(order_id: str, request_id: str, trace_id: str):
    # Log with distributed tracing context and request metadata
    req_logger = logger.bind(
        request_id=request_id,
        trace_id=trace_id,
        order_id=order_id,
        customer_id="cust-9876",
    )

    req_logger.info("Starting order processing")

    try:
        if order_id == "invalid":
            raise ValueError("Invalid order value or insufficient funds")

        # Success simulation with HTTP metrics
        req_logger.bind(
            http_status=200,
            duration_ms=45.2,
        ).info("Order processed successfully")

    except Exception:
        # Exception with stack trace captured and serialized into a single line
        req_logger.bind(
            http_status=400,
            duration_ms=12.8,
        ).exception("Failed to settle order payment")


if __name__ == "__main__":
    logger.info("Application initialized successfully")

    # Successful request
    process_order(order_id="ord-1001", request_id="req-abc-123", trace_id="trace-xyz-789")

    # Failed request
    process_order(order_id="invalid", request_id="req-err-456", trace_id="trace-xyz-000")
