.PHONY: setup dev test lint format build clean help

# Colors for terminal output
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help
	@echo "$(CYAN)Lincoln - Persistent Learning Agent$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

# =============================================================================
# Setup
# =============================================================================

setup: docker-deps setup-elixir ## Install all dependencies and start Docker services
	@echo "$(GREEN)Setup complete!$(NC)"
	@echo ""
	@echo "$(CYAN)Next steps:$(NC)"
	@echo "  1. Copy .env.example to .env and add your ANTHROPIC_API_KEY"
	@echo "  2. Run 'make dev' to start all services"

setup-elixir: ## Install Elixir dependencies and setup database
	@echo "$(CYAN)Installing Elixir dependencies...$(NC)"
	cd apps/lincoln && mix deps.get
	cd apps/lincoln && mix ecto.setup

setup-python: ## Install Python dependencies (for local development without Docker)
	@echo "$(CYAN)Installing Python dependencies...$(NC)"
	cd apps/ml_service && uv sync

# =============================================================================
# Development
# =============================================================================

dev: docker-deps ## Start development (Docker services + local Elixir)
	@echo "$(CYAN)Starting Elixir server...$(NC)"
	@echo "$(YELLOW)DB: localhost:5432 | ML Service: localhost:8000 | Phoenix: localhost:4000$(NC)"
	cd apps/lincoln && mix phx.server

dev-all: ## Start everything in Docker (full containerized stack)
	@echo "$(CYAN)Starting all services in Docker...$(NC)"
	docker compose --profile full up -d
	@echo ""
	@echo "$(GREEN)All services started!$(NC)"
	@echo "$(YELLOW)Phoenix: http://localhost:4000$(NC)"
	docker compose logs -f lincoln

dev-local: ## Start Elixir and Python locally (assumes Docker DB is running)
	@trap 'kill 0' EXIT; \
	(cd apps/lincoln && mix phx.server) & \
	(cd apps/ml_service && uv run uvicorn main:app --reload --port 8000) & \
	wait

dev-elixir: ## Start only Elixir server (assumes Docker services are running)
	cd apps/lincoln && mix phx.server

dev-python: ## Start only Python server locally (for debugging)
	cd apps/ml_service && uv run uvicorn main:app --reload --port 8000

# =============================================================================
# Docker
# =============================================================================

docker-deps: ## Start Docker dependencies (DB + ML service)
	@echo "$(CYAN)Starting Docker services...$(NC)"
	docker compose up -d
	@echo "$(YELLOW)Waiting for services to be healthy...$(NC)"
	@until docker compose exec -T db pg_isready -U postgres > /dev/null 2>&1; do \
		echo "Waiting for PostgreSQL..."; \
		sleep 1; \
	done
	@echo "$(GREEN)PostgreSQL is ready!$(NC)"
	@until curl -sf http://localhost:8000/health > /dev/null 2>&1; do \
		echo "Waiting for ML service..."; \
		sleep 2; \
	done
	@echo "$(GREEN)ML service is ready!$(NC)"

docker-up: ## Start all Docker services (default profile)
	docker compose up -d

docker-up-full: ## Start all services including Elixir app in Docker
	docker compose --profile full up -d

docker-up-test: ## Start test database
	docker compose --profile test up -d db-test

docker-down: ## Stop all Docker services
	docker compose --profile full down

docker-logs: ## Tail Docker logs
	docker compose logs -f

docker-logs-ml: ## Tail ML service logs only
	docker compose logs -f ml_service

docker-build: ## Build Docker images
	docker compose build

docker-build-no-cache: ## Build Docker images without cache
	docker compose build --no-cache

docker-clean: ## Remove all Docker volumes and containers
	docker compose --profile full down -v --remove-orphans
	@echo "$(YELLOW)Cleaned up Docker resources$(NC)"

docker-status: ## Show status of Docker services
	@echo "$(CYAN)Docker Service Status$(NC)"
	@docker compose ps
	@echo ""
	@echo "$(CYAN)Health Checks$(NC)"
	@docker compose ps --format "table {{.Name}}\t{{.Status}}"

# =============================================================================
# Database
# =============================================================================

db-setup: ## Create and migrate database
	cd apps/lincoln && mix ecto.setup

db-reset: ## Drop, create, and migrate database
	cd apps/lincoln && mix ecto.reset

db-migrate: ## Run pending migrations
	cd apps/lincoln && mix ecto.migrate

db-rollback: ## Rollback last migration
	cd apps/lincoln && mix ecto.rollback

db-console: ## Open PostgreSQL console
	docker compose exec db psql -U postgres -d lincoln_dev

# =============================================================================
# Testing
# =============================================================================

test: test-elixir ## Run all tests
	@echo "$(GREEN)All tests passed!$(NC)"

test-elixir: ## Run Elixir tests
	@echo "$(CYAN)Running Elixir tests...$(NC)"
	cd apps/lincoln && mix test

test-python: ## Run Python tests
	@echo "$(CYAN)Running Python tests...$(NC)"
	cd apps/ml_service && uv run pytest

test-watch: ## Run Elixir tests in watch mode
	cd apps/lincoln && mix test.watch

test-llm: ## Test Claude API connection
	cd apps/lincoln && mix lincoln.test_llm

test-ml: ## Test ML service connection
	@curl -s http://localhost:8000/health | python3 -m json.tool || echo "$(RED)ML service not responding$(NC)"

# =============================================================================
# Code Quality
# =============================================================================

lint: lint-elixir ## Lint all code
	@echo "$(GREEN)Linting complete!$(NC)"

lint-elixir: ## Lint Elixir code
	@echo "$(CYAN)Linting Elixir...$(NC)"
	cd apps/lincoln && mix format --check-formatted
	cd apps/lincoln && mix credo --strict

lint-python: ## Lint Python code
	@echo "$(CYAN)Linting Python...$(NC)"
	cd apps/ml_service && uv run ruff check .

format: format-elixir format-python ## Format all code
	@echo "$(GREEN)Formatting complete!$(NC)"

format-elixir: ## Format Elixir code
	cd apps/lincoln && mix format

format-python: ## Format Python code
	cd apps/ml_service && uv run ruff format .

precommit: ## Run all checks before committing
	cd apps/lincoln && mix precommit

# =============================================================================
# Build & Deploy
# =============================================================================

build: docker-build ## Build all Docker images
	@echo "$(GREEN)Build complete!$(NC)"

release-elixir: ## Build Elixir release
	cd apps/lincoln && MIX_ENV=prod mix release

# =============================================================================
# Utilities
# =============================================================================

clean: ## Clean build artifacts
	cd apps/lincoln && mix clean
	cd apps/ml_service && rm -rf .venv __pycache__ .pytest_cache .mypy_cache .ruff_cache
	rm -rf _build deps

iex: ## Start IEx with Lincoln loaded
	cd apps/lincoln && iex -S mix

routes: ## Show all Phoenix routes
	cd apps/lincoln && mix phx.routes

gen-secret: ## Generate a new secret key base
	@mix phx.gen.secret

status: docker-status test-ml ## Show overall system status
	@echo ""
	@echo "$(CYAN)Testing LLM connection...$(NC)"
	@cd apps/lincoln && mix lincoln.test_llm 2>/dev/null || echo "$(RED)LLM not configured (set ANTHROPIC_API_KEY)$(NC)"
