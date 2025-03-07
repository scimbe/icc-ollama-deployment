# Makefile for ICC Ollama Deployment

# Load configuration
include configs/config.sh

.PHONY: deploy deploy-ollama deploy-webui check logs shell cleanup help gpu-test gpu-monitor gpu-bench gpu-compat port-forward pull-model

help:
	@echo "Available commands:"
	@echo "  make deploy         - Deploy both Ollama and WebUI"
	@echo "  make deploy-ollama  - Deploy only Ollama"
	@echo "  make deploy-webui   - Deploy only WebUI"
	@echo "  make check          - Check the status of deployments"
	@echo "  make logs           - Show logs from Ollama pod"
	@echo "  make shell          - Open a shell in the Ollama pod"
	@echo "  make cleanup        - Remove all resources"
	@echo ""
	@echo "GPU Tools:"
	@echo "  make gpu-test       - Test GPU functionality"
	@echo "  make gpu-monitor    - Monitor GPU usage"
	@echo "  make gpu-bench      - Run GPU benchmarks"
	@echo "  make gpu-compat     - Check GPU compatibility"
	@echo ""
	@echo "Utility Commands:"
	@echo "  make port-forward   - Start port forwarding for Ollama and WebUI"
	@echo "  make pull-model     - Pull an Ollama model (usage: make pull-model MODEL=llama3:8b)"

deploy: deploy-ollama deploy-webui

deploy-ollama:
	@echo "Deploying Ollama..."
	./scripts/deploy-ollama.sh

deploy-webui:
	@echo "Deploying WebUI..."
	./scripts/deploy-webui-k8s.sh

check:
	@echo "Checking deployment status..."
	kubectl -n $(NAMESPACE) get pods,svc

logs:
	@POD=$$(kubectl -n $(NAMESPACE) get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}') && \
	kubectl -n $(NAMESPACE) logs -f $$POD

shell:
	@POD=$$(kubectl -n $(NAMESPACE) get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}') && \
	kubectl -n $(NAMESPACE) exec -it $$POD -- /bin/bash

cleanup:
	@echo "Cleaning up resources..."
	./scripts/cleanup.sh

# GPU Testing and Monitoring Commands
gpu-test:
	@echo "Testing GPU functionality..."
	./scripts/test-gpu.sh

gpu-monitor:
	@echo "Starting GPU monitoring..."
	./scripts/monitor-gpu.sh

gpu-bench:
	@echo "Running GPU benchmark..."
	./scripts/benchmark-gpu.sh $(if $(MODEL),$(MODEL),)

gpu-compat:
	@echo "Checking GPU compatibility..."
	./scripts/check-gpu-compatibility.sh

# Utility Commands
port-forward:
	@echo "Starting port forwarding..."
	./scripts/port-forward.sh

pull-model:
	@if [ -z "$(MODEL)" ]; then \
		echo "Error: No model specified. Usage: make pull-model MODEL=llama3:8b"; \
		exit 1; \
	fi
	@echo "Pulling model $(MODEL)..."
	./scripts/pull-model.sh $(MODEL)
