/**
 * Exemplo prático de uso do Pino com correlação e tratamento de erro.
 */

const { logger } = require('./logger');

function simulateRequest(orderId, requestId, traceId) {
  // Cria logger filho com contexto amarrado da requisição
  const reqLog = logger.child({
    request_id: requestId,
    trace_id: traceId,
    order_id: orderId,
  });

  reqLog.info('Iniciando processamento da transação');

  if (orderId === 'invalid') {
    const err = new Error('Falha ao processar checkout: saldo insuficiente');
    reqLog.error(
      {
        err,
        http_status: 422,
        duration_ms: 18.4,
      },
      'Transação rejeitada'
    );
    return;
  }

  reqLog.info(
    {
      http_status: 200,
      duration_ms: 32.1,
    },
    'Transação concluída com sucesso'
  );
}

// Inicialização
logger.info('Servidor Node.js ouvindo requisições na porta 3000');

simulateRequest('ord-9901', 'req-node-1', 'trace-node-1');
simulateRequest('invalid', 'req-node-2', 'trace-node-2');
