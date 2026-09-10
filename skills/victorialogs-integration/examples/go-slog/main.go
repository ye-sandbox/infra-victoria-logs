package main

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"strings"
	"time"
)

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func newVictoriaLogsHandler() slog.Handler {
	opts := &slog.HandlerOptions{
		Level: slog.LevelInfo,
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			switch a.Key {
			case slog.MessageKey:
				a.Key = "message"
			case slog.LevelKey:
				a.Key = "level"
				a.Value = slog.StringValue(strings.ToLower(a.Value.String()))
			case slog.TimeKey:
				a.Key = "timestamp"
				// Converte para ISO-8601 UTC
				a.Value = slog.StringValue(a.Value.Time().UTC().Format(time.RFC3339Nano))
			}
			return a
		},
	}

	serviceName := getEnv("SERVICE_NAME", getEnv("APP_NAME", "app-go"))
	envName := getEnv("ENVIRONMENT", getEnv("ENV", "production"))

	baseHandler := slog.NewJSONHandler(os.Stdout, opts)
	return baseHandler.WithAttrs([]slog.Attr{
		slog.String("service", serviceName),
		slog.String("app", serviceName),
		slog.String("env", envName),
	})
}

func main() {
	logger := slog.New(newVictoriaLogsHandler())
	slog.SetDefault(logger)

	logger.Info("Serviço Go inicializado com sucesso")

	// Log com correlação de requisição e telemetria HTTP
	ctx := context.Background()
	reqLogger := logger.With(
		slog.String("trace_id", "tr-go-999"),
		slog.String("request_id", "req-go-111"),
	)

	reqLogger.InfoContext(ctx, "Processando requisição de pagamento",
		slog.String("customer_id", "cust-555"),
	)

	// Simulação de resposta bem-sucedida
	reqLogger.InfoContext(ctx, "Pagamento aprovado",
		slog.Int("http_status", 200),
		slog.Float64("duration_ms", 23.4),
	)

	// Simulação de erro com causa
	err := errors.New("timeout ao contatar gateway bancário")
	reqLogger.ErrorContext(ctx, "Falha na liquidação",
		slog.String("error", err.Error()),
		slog.Int("http_status", 504),
		slog.Float64("duration_ms", 3005.1),
	)
}
