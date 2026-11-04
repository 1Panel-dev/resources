docker run --gpus all \
  --privileged --ipc=host -p 8000:8000 \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  -e VLLM_USE_RUST_FRONTEND=1 \
  vllm/vllm-openai:latest Qwen/Qwen3.6-35B-A3B \
  --trust-remote-code \
  --gpu-memory-utilization 0.8 \
  --tensor-parallel-size 1 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --reasoning-parser qwen3 \
  --mm-encoder-tp-mode data \
  --speculative-config '{"method":"mtp","num_speculative_tokens":3,"moe_backend":"triton"}'