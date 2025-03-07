# Makefile for ICC Ollama Deployment

# Load configuration
include configs/config.sh

.PHONY: deploy deploy-ollama deploy-webui check logs shell cleanup help

help:
	@echo "Available commands:"
	@echo "  make deploy         - Deploy both Ollama and WebUI"
	@echo "  make deploy-ollama  - Deploy only Ollama"
	@echo "  make deploy-webui   - Deploy only WebUI"
	@echo "  make check          - Check the status of deployments"
	@echo "  make logs           - Show logs from Ollama pod"
	@echo "  make shell          - Open a shell in the Ollama pod"
	@echo "  make cleanup        - Remove all resources"

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
