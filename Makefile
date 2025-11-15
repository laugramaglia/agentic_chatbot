# =============================================================================
# Shopping Cart Chatbot - Makefile
# =============================================================================
# Common commands for managing the microservices
# =============================================================================

.PHONY: help setup build up down restart logs clean test lint migrate-up migrate-down ps stats

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# =============================================================================
# Help
# =============================================================================

help: ## Show this help message
	@echo "$(BLUE)Shopping Cart Chatbot - Available Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# Setup
# =============================================================================

setup: ## Initial project setup (copy .env.example to .env)
	@echo "$(BLUE)Setting up project...$(NC)"
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "$(GREEN)✓$(NC) Created .env file from .env.example"; \
		echo "$(YELLOW)⚠ Please edit .env with your actual configuration!$(NC)"; \
	else \
		echo "$(YELLOW)⚠ .env file already exists, skipping...$(NC)"; \
	fi

check-env: ## Check if .env file exists
	@if [ ! -f .env ]; then \
		echo "$(RED)✗ .env file not found!$(NC)"; \
		echo "$(YELLOW)Run 'make setup' to create it from .env.example$(NC)"; \
		exit 1; \
	fi

# =============================================================================
# Docker Compose Commands
# =============================================================================

build: check-env ## Build all services
	@echo "$(BLUE)Building all services...$(NC)"
	docker-compose build
	@echo "$(GREEN)✓ Build complete$(NC)"

build-service: check-env ## Build specific service (usage: make build-service SERVICE=chat-service)
	@echo "$(BLUE)Building $(SERVICE)...$(NC)"
	docker-compose build $(SERVICE)
	@echo "$(GREEN)✓ Build complete for $(SERVICE)$(NC)"

up: check-env ## Start all services
	@echo "$(BLUE)Starting all services...$(NC)"
	docker-compose up -d
	@echo "$(GREEN)✓ All services started$(NC)"
	@echo "$(YELLOW)Run 'make logs' to view logs$(NC)"

up-build: check-env ## Build and start all services
	@echo "$(BLUE)Building and starting all services...$(NC)"
	docker-compose up -d --build
	@echo "$(GREEN)✓ All services built and started$(NC)"

down: ## Stop and remove all containers
	@echo "$(BLUE)Stopping all services...$(NC)"
	docker-compose down
	@echo "$(GREEN)✓ All services stopped$(NC)"

down-volumes: ## Stop all containers and remove volumes
	@echo "$(RED)Stopping all services and removing volumes...$(NC)"
	docker-compose down -v
	@echo "$(GREEN)✓ All services stopped and volumes removed$(NC)"

restart: ## Restart all services
	@echo "$(BLUE)Restarting all services...$(NC)"
	docker-compose restart
	@echo "$(GREEN)✓ All services restarted$(NC)"

restart-service: ## Restart specific service (usage: make restart-service SERVICE=chat-service)
	@echo "$(BLUE)Restarting $(SERVICE)...$(NC)"
	docker-compose restart $(SERVICE)
	@echo "$(GREEN)✓ $(SERVICE) restarted$(NC)"

# =============================================================================
# Logs
# =============================================================================

logs: ## View logs from all services
	docker-compose logs -f

logs-service: ## View logs from specific service (usage: make logs-service SERVICE=chat-service)
	docker-compose logs -f $(SERVICE)

logs-gateway: ## View API Gateway logs
	docker-compose logs -f api-gateway

logs-chat: ## View Chat Service logs
	docker-compose logs -f chat-service

logs-cart: ## View Cart Service logs
	docker-compose logs -f cart-service

logs-product: ## View Product Service logs
	docker-compose logs -f product-service

logs-session: ## View Session Service logs
	docker-compose logs -f session-service

logs-recommend: ## View Recommendation Service logs
	docker-compose logs -f recommendation-service

# =============================================================================
# Status and Info
# =============================================================================

ps: ## List all running containers
	@echo "$(BLUE)Running services:$(NC)"
	@docker-compose ps

stats: ## Show container resource usage
	@echo "$(BLUE)Container resource usage:$(NC)"
	@docker stats --no-stream $$(docker-compose ps -q)

health: ## Check health status of all services
	@echo "$(BLUE)Health status:$(NC)"
	@docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# =============================================================================
# Development
# =============================================================================

shell-service: ## Open shell in specific service (usage: make shell-service SERVICE=chat-service)
	docker-compose exec $(SERVICE) /bin/sh

shell-gateway: ## Open shell in API Gateway
	docker-compose exec api-gateway /bin/sh

shell-chat: ## Open shell in Chat Service
	docker-compose exec chat-service /bin/sh

shell-cart: ## Open shell in Cart Service
	docker-compose exec cart-service /bin/sh

shell-product: ## Open shell in Product Service
	docker-compose exec product-service /bin/sh

# =============================================================================
# Testing
# =============================================================================

test: ## Run tests in all services
	@echo "$(BLUE)Running tests...$(NC)"
	@for service in chat-service cart-service product-service session-service recommendation-service; do \
		echo "$(YELLOW)Testing $$service...$(NC)"; \
		docker-compose exec -T $$service go test ./... -v || exit 1; \
	done
	@echo "$(GREEN)✓ All tests passed$(NC)"

test-service: ## Run tests in specific service (usage: make test-service SERVICE=chat-service)
	@echo "$(BLUE)Testing $(SERVICE)...$(NC)"
	docker-compose exec -T $(SERVICE) go test ./... -v

test-coverage: ## Run tests with coverage
	@echo "$(BLUE)Running tests with coverage...$(NC)"
	@for service in chat-service cart-service product-service session-service recommendation-service; do \
		echo "$(YELLOW)Testing $$service with coverage...$(NC)"; \
		docker-compose exec -T $$service go test ./... -coverprofile=coverage.out || exit 1; \
	done
	@echo "$(GREEN)✓ Coverage reports generated$(NC)"

# =============================================================================
# Linting and Formatting
# =============================================================================

lint: ## Run golangci-lint on all services
	@echo "$(BLUE)Running linters...$(NC)"
	@for service in chat-service cart-service product-service session-service recommendation-service; do \
		echo "$(YELLOW)Linting $$service...$(NC)"; \
		docker-compose exec -T $$service golangci-lint run ./... || exit 1; \
	done
	@echo "$(GREEN)✓ Linting complete$(NC)"

fmt: ## Format code in all services
	@echo "$(BLUE)Formatting code...$(NC)"
	@for service in chat-service cart-service product-service session-service recommendation-service; do \
		echo "$(YELLOW)Formatting $$service...$(NC)"; \
		docker-compose exec -T $$service go fmt ./...; \
	done
	@echo "$(GREEN)✓ Formatting complete$(NC)"

# =============================================================================
# Database
# =============================================================================

migrate-up: ## Run database migrations
	@echo "$(BLUE)Running database migrations...$(NC)"
	@echo "$(YELLOW)TODO: Implement migration script$(NC)"
	# cd scripts && go run migrate.go up

migrate-down: ## Rollback database migrations
	@echo "$(BLUE)Rolling back database migrations...$(NC)"
	@echo "$(YELLOW)TODO: Implement migration script$(NC)"
	# cd scripts && go run migrate.go down

db-shell: ## Connect to SurrealDB (requires surreal CLI)
	@echo "$(BLUE)Connecting to SurrealDB...$(NC)"
	surreal sql --endpoint $$(grep SURREALDB_URL .env | cut -d '=' -f2) \
		--namespace $$(grep SURREALDB_NAMESPACE .env | cut -d '=' -f2) \
		--database $$(grep SURREALDB_DATABASE .env | cut -d '=' -f2)

# =============================================================================
# Cleanup
# =============================================================================

clean: down ## Stop services and remove containers, networks, and images
	@echo "$(BLUE)Cleaning up...$(NC)"
	docker-compose down --rmi local --volumes --remove-orphans
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

clean-all: ## Remove all Docker resources (containers, images, volumes, networks)
	@echo "$(RED)⚠ WARNING: This will remove ALL Docker resources for this project!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker-compose down --rmi all --volumes --remove-orphans; \
		echo "$(GREEN)✓ All resources removed$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled$(NC)"; \
	fi

prune: ## Remove unused Docker resources
	@echo "$(BLUE)Pruning unused Docker resources...$(NC)"
	docker system prune -f
	@echo "$(GREEN)✓ Prune complete$(NC)"

# =============================================================================
# Production
# =============================================================================

prod-build: ## Build for production
	@echo "$(BLUE)Building for production...$(NC)"
	BUILD_ENV=production docker-compose build
	@echo "$(GREEN)✓ Production build complete$(NC)"

prod-up: ## Start in production mode
	@echo "$(BLUE)Starting in production mode...$(NC)"
	BUILD_ENV=production docker-compose up -d
	@echo "$(GREEN)✓ Production services started$(NC)"

# =============================================================================
# Utilities
# =============================================================================

validate-env: check-env ## Validate .env file has all required variables
	@echo "$(BLUE)Validating .env file...$(NC)"
	@required_vars="SURREALDB_URL GROQ_API_KEY JWT_SECRET"; \
	missing=0; \
	for var in $$required_vars; do \
		if ! grep -q "^$$var=" .env || grep -q "^$$var=$$" .env || grep -q "^$$var=.*change_me" .env; then \
			echo "$(RED)✗ Missing or invalid: $$var$(NC)"; \
			missing=1; \
		fi; \
	done; \
	if [ $$missing -eq 0 ]; then \
		echo "$(GREEN)✓ .env validation passed$(NC)"; \
	else \
		echo "$(RED)✗ .env validation failed$(NC)"; \
		exit 1; \
	fi

ports: ## Show which ports are in use
	@echo "$(BLUE)Services and their ports:$(NC)"
	@echo "  API Gateway:          http://localhost:8080"
	@echo "  Chat Service:         http://localhost:8081"
	@echo "  Cart Service:         http://localhost:8082"
	@echo "  Product Service:      http://localhost:8083"
	@echo "  Session Service:      http://localhost:8084"
	@echo "  Recommendation Svc:   http://localhost:8085"

endpoints: ## Show available API endpoints
	@echo "$(BLUE)API Endpoints:$(NC)"
	@echo ""
	@echo "$(GREEN)Public Endpoints (via API Gateway):$(NC)"
	@echo "  POST   http://localhost:8080/chat"
	@echo "  GET    http://localhost:8080/chat/history/:session"
	@echo "  POST   http://localhost:8080/cart/add"
	@echo "  POST   http://localhost:8080/cart/remove"
	@echo "  PUT    http://localhost:8080/cart/update"
	@echo "  GET    http://localhost:8080/cart"
	@echo "  GET    http://localhost:8080/products/:id"
	@echo "  POST   http://localhost:8080/products/search"
	@echo "  POST   http://localhost:8080/session/create"
	@echo "  GET    http://localhost:8080/session/:id"
	@echo "  POST   http://localhost:8080/checkout"
	@echo "  GET    http://localhost:8080/recommend"

dev: setup build up ## Full development setup (setup + build + up)
	@echo "$(GREEN)✓ Development environment ready!$(NC)"
	@make ports
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Edit .env with your configuration"
	@echo "  2. Run 'make logs' to view service logs"
	@echo "  3. Run 'make endpoints' to see available APIs"
