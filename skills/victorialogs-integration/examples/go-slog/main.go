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
				// Convert to ISO-8601 UTC
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

	logger.Info("Go service initialized successfully")

	// Log with request correlation and HTTP telemetry
	ctx := context.Background()
	reqLogger := logger.With(
		slog.String("trace_id", "tr-go-999"),
		slog.String("request_id", "req-go-111"),
	)

	reqLogger.InfoContext(ctx, "Processing payment request",
		slog.String("customer_id", "cust-555"),
	)

	// Success response simulation
	reqLogger.InfoContext(ctx, "Payment approved",
		slog.Int("http_status", 200),
		slog.Float64("duration_ms", 23.4),
	)

	// Error simulation with cause
	err := errors.New("timeout contacting banking gateway")
	reqLogger.ErrorContext(ctx, "Settlement failure",
		slog.String("error", err.Error()),
		slog.Int("http_status", 504),
		slog.Float64("duration_ms", 3005.1),
	)
}
