.PHONY: up down logs restart status run-cli prepare clean

# Load environment variables if .env exists
-include .env
export

# Default variable values just in case .env doesn't exist or is missing values
PORT ?= 4242
MODEL_DIR ?= ./
MODEL_NAME ?= Qwen3.6-35B-A3B-Q4_K_M.gguf
N_CTX ?= 512
HF_REPO ?= Qwen/Qwen3.6-35B-A3B
QUANT_FORMAT ?= Q4_K_M

# Derived names matching what prepare-model.sh produces
MODEL_BASENAME = $(notdir $(HF_REPO))
MODEL_FP16     = $(MODEL_BASENAME)-fp16.gguf

# Deploy using Docker Compose
up:
	docker compose up -d

# Stop Docker Compose deployment
down:
	docker compose down

# Restart Docker Compose deployment
restart:
	docker compose restart

# View logs from Docker Compose
logs:
	docker compose logs -f

# View status of Docker Compose containers
status:
	docker compose ps

# Alternative deployment running raw Docker CLI without compose
run-cli:
	docker run -d --rm \
		--name llama-cpp-server-cli \
		--device /dev/dri \
		-p $(PORT):8080 \
		-v "$$(cd "$(MODEL_DIR)" && pwd):/models" \
		ghcr.io/ggml-org/llama.cpp:server-vulkan \
		-m /models/$(MODEL_NAME) \
		--port 8080 \
		--host 0.0.0.0 \
		-n $(N_CTX)

# Prepare model: download, convert to GGUF, and quantize
prepare:
	chmod +x prepare-model.sh
	docker run --rm -it \
		--name llama-cpp-prepare \
		-v "$$(pwd)/workspace:/workspace" \
		-v "$$(pwd)/prepare-model.sh:/prepare-model.sh:ro" \
		-w /workspace \
		python:3.11-slim \
		/prepare-model.sh "$(HF_REPO)" "$(QUANT_FORMAT)"

# Clean up all intermediate artifacts from the prepare process
# (does NOT remove the final quantized model)
clean:
	@echo "Removing stale prepare container..."
	-docker rm -f llama-cpp-prepare 2>/dev/null || true
	@echo "Removing downloaded model weights..."
	rm -rf "$$(pwd)/workspace"/$(MODEL_BASENAME)
	@echo "Removing intermediate FP16 GGUF..."
	rm -f "$$(pwd)/workspace"/$(MODEL_FP16)
	@echo "Removing cloned llama.cpp repo..."
	rm -rf "$$(pwd)/workspace"/llama.cpp
	@echo "Removing step markers..."
	rm -f "$$(pwd)/workspace"/.step_*_done
	@echo "Prepare cleanup complete."
