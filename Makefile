# Makefile for ICC Ollama Deployment

# Load configuration
include configs/config.sh

.PHONY: deploy deploy-ollama deploy-webui check logs shell cleanup help gpu-test gpu-monitor gpu-bench gpu-compat port-forward pull-model list-models rag-setup rag-stop rag-upload

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
	@echo "Model Management:"
	@echo "  make pull-model MODEL=llama3:8b   - Pull an Ollama model"
	@echo "  make list-models                  - List installed models"
	@echo ""
	@echo "RAG Commands:"
	@echo "  make rag-setup                   - Setup RAG infrastructure"
	@echo "  make rag-stop                    - Stop RAG infrastructure"
	@echo "  make rag-upload FILE=path/to/file.txt - Upload documents for RAG"
	@echo ""
	@echo "Utility Commands:"
	@echo "  make port-forward   - Start port forwarding for Ollama and WebUI"

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

list-models:
	@echo "Listing installed models..."
	./scripts/list-models.sh

# RAG Commands
rag-setup:
	@echo "Setting up RAG infrastructure..."
	./scripts/setup-rag.sh

rag-stop:
	@echo "Stopping RAG infrastructure..."
	./scripts/stop-rag.sh

rag-upload:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: No file specified. Usage: make rag-upload FILE=path/to/file.txt"; \
		exit 1; \
	fi
	@echo "Uploading document $(FILE) for RAG..."
	./scripts/upload-rag-documents.sh $(FILE)
