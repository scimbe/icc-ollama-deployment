# Makefile for ICC Ollama Deployment

# Load configuration
include configs/config.sh

.PHONY: deploy deploy-ollama deploy-webui check logs shell cleanup help gpu-test gpu-monitor gpu-bench gpu-compat port-forward pull-model list-models finetune-simple convert-training-data create-template test-model

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
	@echo "  make test-model MODEL=llama3:8b   - Test a model with a sample prompt"
	@echo ""
	@echo "Model Finetuning:"
	@echo "  make finetune-simple MODEL=llama3:8b NAME=haw-custom DATA=data.jsonl - Simple finetuning"
	@echo "  make convert-training-data INPUT=file.jsonl OUTPUT=out.txt - Convert training data"
	@echo "  make create-template TYPE=academic NAME=my-template - Create a modelfile template"
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

# Model Testing
test-model:
	@if [ -z "$(MODEL)" ]; then \
		echo "Error: No model specified. Usage: make test-model MODEL=llama3:8b"; \
		exit 1; \
	fi
	@PROMPT=$${PROMPT:-"Erkläre in einem kurzen Absatz, was die HAW Hamburg ist."}; \
	echo "Testing model $(MODEL) with prompt: $$PROMPT"; \
	./scripts/ollama-api-client.sh test $(MODEL) -m "$$PROMPT"

# Model Finetuning Commands
finetune-simple:
	@if [ -z "$(MODEL)" ]; then \
		echo "Error: No base model specified. Usage: make finetune-simple MODEL=llama3:8b NAME=haw-custom DATA=data.jsonl"; \
		exit 1; \
	fi
	@if [ -z "$(DATA)" ]; then \
		echo "Error: No training data specified. Usage: make finetune-simple MODEL=llama3:8b NAME=haw-custom DATA=data.jsonl"; \
		exit 1; \
	fi
	@NAME=$${NAME:-"$${MODEL%:*}-custom"}; \
	TEMPLATE=$${TEMPLATE:-""}; \
	echo "Finetuning model $(MODEL) as $$NAME with data $(DATA)"; \
	./scripts/finetune-simple.sh -m $(MODEL) -n $$NAME -d $(DATA) $(if $(TEMPLATE),-t $(TEMPLATE),)

convert-training-data:
	@if [ -z "$(INPUT)" ]; then \
		echo "Error: No input file specified. Usage: make convert-training-data INPUT=data.jsonl OUTPUT=out.txt FORMAT=txt"; \
		exit 1; \
	fi
	@OUTPUT=$${OUTPUT:-"$${INPUT%.*}.converted.$${FORMAT:-txt}"}; \
	FORMAT=$${FORMAT:-"txt"}; \
	echo "Converting training data from $(INPUT) to $$OUTPUT in format $$FORMAT"; \
	./scripts/convert-training-data.sh -i $(INPUT) -o $$OUTPUT -f $$FORMAT

create-template:
	@TYPE=$${TYPE:-"assistance"}; \
	LANG=$${LANG:-"de"}; \
	NAME=$${NAME:-"custom_template"}; \
	OUTPUT=$${OUTPUT:-"templates"}; \
	echo "Creating template of type $$TYPE in language $$LANG as $$NAME"; \
	./scripts/create-template.sh -t $$TYPE -l $$LANG -o $$OUTPUT $$NAME
