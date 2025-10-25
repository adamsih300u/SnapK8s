# Snapcast Server Docker Container Makefile

# Variables
IMAGE_NAME := snapcast-server
REGISTRY := ghcr.io
REPO_NAME := $(shell basename $$(git config --get remote.origin.url) .git)
USERNAME := $(shell git config --get user.name | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
FULL_IMAGE := $(REGISTRY)/$(USERNAME)/$(REPO_NAME)
VERSION := $(shell git describe --tags --always --dirty)

# Default target
.PHONY: help
help: ## Show this help message
	@echo "Snapcast Server Docker Container"
	@echo "Available commands:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: build
build: ## Build the Docker image locally
	docker build -t $(IMAGE_NAME):latest .
	docker tag $(IMAGE_NAME):latest $(IMAGE_NAME):$(VERSION)

.PHONY: build-amd64
build-amd64: ## Build for AMD64 architecture
	docker build --platform linux/amd64 -t $(IMAGE_NAME):amd64 .

.PHONY: build-arm64
build-arm64: ## Build for ARM64 architecture
	docker build --platform linux/arm64 -t $(IMAGE_NAME):arm64 .

.PHONY: build-multi
build-multi: ## Build multi-architecture image
	docker buildx create --name snapcast-builder --use || true
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		-t $(FULL_IMAGE):latest \
		-t $(FULL_IMAGE):$(VERSION) \
		--push .

.PHONY: run
run: build ## Build and run the container
	docker-compose up -d

.PHONY: stop
stop: ## Stop the running container
	docker-compose down

.PHONY: logs
logs: ## Show container logs
	docker-compose logs -f

.PHONY: shell
shell: ## Get a shell in the running container
	docker-compose exec snapserver bash

.PHONY: test
test: build ## Test the built image
	@echo "Testing container startup..."
	docker run -d --name snapcast-test $(IMAGE_NAME):latest
	@sleep 10
	@echo "Checking if snapserver is running..."
	docker exec snapcast-test pgrep snapserver
	@echo "Checking if port 1704 is listening..."
	docker exec snapcast-test netcat -z localhost 1704
	@echo "Test passed!"
	docker stop snapcast-test
	docker rm snapcast-test

.PHONY: clean
clean: ## Clean up Docker images and containers
	docker-compose down -v
	docker system prune -f
	docker rmi $(IMAGE_NAME):latest $(IMAGE_NAME):$(VERSION) 2>/dev/null || true

.PHONY: setup-config
setup-config: ## Set up configuration directory
	mkdir -p config
	cp snapserver.conf config/ 2>/dev/null || true
	@echo "Configuration directory created at ./config/"
	@echo "Edit ./config/snapserver.conf to customize your setup"

.PHONY: dev
dev: setup-config run ## Set up development environment
	@echo "Development environment started!"
	@echo "Web interface: http://localhost:1780"
	@echo "Control API: http://localhost:1705"
	@echo "View logs with: make logs"

.PHONY: status
status: ## Show container status
	docker-compose ps
	@echo ""
	@echo "Service endpoints:"
	@echo "  Web interface: http://localhost:1780"
	@echo "  Control API: http://localhost:1705"
	@echo "  Snapcast server: localhost:1704"
	@echo "  AirPlay: localhost:5000"

.PHONY: update
update: ## Pull latest changes and rebuild
	git pull
	make build
	make stop
	make run

.PHONY: release
release: ## Create a release (requires VERSION variable)
ifndef VERSION
	@echo "Please specify VERSION: make release VERSION=v1.0.0"
	@exit 1
endif
	git tag $(VERSION)
	git push origin $(VERSION)
	@echo "Release $(VERSION) created. GitHub Actions will build and publish the images."

# Development helpers
.PHONY: lint-dockerfile
lint-dockerfile: ## Lint the Dockerfile
	docker run --rm -i hadolint/hadolint < Dockerfile

.PHONY: security-scan
security-scan: build ## Run security scan on the image
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		-v /tmp:/tmp aquasec/trivy image $(IMAGE_NAME):latest 