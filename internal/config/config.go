package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	Server struct {
		Addr string
	}
	Gateway struct {
		BaseURL string
	}
	Execution struct {
		MaxParallel int
		TimeoutMS   int
	}
}

func Load(env string) (Config, error) {
	env = normalizeEnv(env)
	if env == "" {
		env = normalizeEnv(os.Getenv("MCP_ENV"))
	}
	if env == "" {
		env = "dev"
	}

	cfg := defaultConfig(env)
	path := os.Getenv("FULL_STACK_TEST_CONFIG")
	if path == "" {
		path = filepath.Join("configs", env+".yaml")
	}
	if _, err := os.Stat(path); err == nil {
		if err := applyYAML(path, &cfg); err != nil {
			return Config{}, err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return Config{}, err
	}
	overrideFromEnv(&cfg)
	return cfg, nil
}

func defaultConfig(env string) Config {
	cfg := Config{}
	cfg.Server.Addr = ":8080"
	cfg.Gateway.BaseURL = "http://127.0.0.1:8080"
	cfg.Execution.MaxParallel = 3
	cfg.Execution.TimeoutMS = 30000
	if env == "pre" {
		cfg.Execution.TimeoutMS = 45000
	}
	if env == "prod" {
		cfg.Execution.TimeoutMS = 60000
	}
	return cfg
}

func overrideFromEnv(cfg *Config) {
	if addr := os.Getenv("MCP_GATEWAY_ADDR"); addr != "" {
		cfg.Server.Addr = addr
	}
	if baseURL := os.Getenv("MCP_GATEWAY_BASE_URL"); baseURL != "" {
		cfg.Gateway.BaseURL = baseURL
	}
}

func applyYAML(path string, cfg *Config) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	section := ""
	for idx, line := range strings.Split(string(raw), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasSuffix(line, ":") {
			section = strings.TrimSuffix(line, ":")
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			return fmt.Errorf("%s:%d invalid yaml line", path, idx+1)
		}
		key := strings.TrimSpace(parts[0])
		value := strings.Trim(strings.TrimSpace(parts[1]), "\"'")
		switch section + "." + key {
		case "server.addr":
			cfg.Server.Addr = value
		case "gateway.base_url":
			cfg.Gateway.BaseURL = value
		case "execution.max_parallel":
			fmt.Sscanf(value, "%d", &cfg.Execution.MaxParallel)
		case "execution.timeout_ms":
			fmt.Sscanf(value, "%d", &cfg.Execution.TimeoutMS)
		}
	}
	return nil
}

func normalizeEnv(env string) string {
	switch strings.ToLower(strings.TrimSpace(env)) {
	case "dev", "pre", "prod":
		return strings.ToLower(strings.TrimSpace(env))
	default:
		return ""
	}
}
