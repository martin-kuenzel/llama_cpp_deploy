# LLaMA.cpp Deployment

This deployment setup creates a `llama.cpp` server with Vulkan support utilizing the hardware acceleration specified in the `receipt.txt`.

## Getting Started

### Configuration

You can configure the deployment via the `.env` file containing:
- `MODEL_DIR`: The directory on your host machine where the model is located (default: `./`)
- `MODEL_NAME`: The filename of your quantized `.gguf` model (default: `Qwen3.6-35B-A3B-Q4_K_M.gguf`)
- `PORT`: The host port to expose (default: `4242`)
- `N_CTX`: Context window size (default: `512`)

### 1. Deploy via Docker Compose

To deploy the server in detached mode:
```bash
docker compose up -d
```
Or using the provided Makefile:
```bash
make up
```

Stop the server:
```bash
docker compose down
```
Or using Makefile:
```bash
make down
```

### 2. Deploy via Docker CLI

If you prefer to deploy using pure Docker CLI without Docker Compose, you can use the Makefile wrapper which executes the underlying `docker run` command:
```bash
make run-cli
```

### Checking Logs and Status

View logs:
```bash
make logs
```

View status of running containers:
```bash
make status
```
