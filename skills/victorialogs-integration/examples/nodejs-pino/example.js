/**
 * Practical usage example of Pino with request correlation and error handling.
 */

const { logger } = require('./logger');

function simulateRequest(orderId, requestId, traceId) {
  // Create child logger with bound request context
  const reqLog = logger.child({
    request_id: requestId,
    trace_id: traceId,
    order_id: orderId,
  });

  reqLog.info('Starting transaction processing');

  if (orderId === 'invalid') {
    const err = new Error('Failed to process checkout: insufficient balance');
    reqLog.error(
      {
        err,
        http_status: 422,
        duration_ms: 18.4,
      },
      'Transaction rejected'
    );
    return;
  }

  reqLog.info(
    {
      http_status: 200,
      duration_ms: 32.1,
    },
    'Transaction completed successfully'
  );
}

// Initialization
logger.info('Node.js server listening on port 3000');

simulateRequest('ord-9901', 'req-node-1', 'trace-node-1');
simulateRequest('invalid', 'req-node-2', 'trace-node-2');
