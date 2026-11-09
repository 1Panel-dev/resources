docker run --gpus all \
  --ipc=host -p 8000:8000 \
  -e CUDA_VISIBLE_DEVICES=1 \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  -e VLLM_USE_RUST_FRONTEND=1 \
  vllm/vllm-openai:v0.33.0 Qwen/Qwen3.6-35B-A3B-FP8 \
  --trust-remote-code \
  --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.90 \
  --max-model-len 32768 \
  --max-num-seqs 64 \
  --max-num-batched-tokens 8192 \
  --block-size 32 \
  --attention-backend FLASH_ATTN \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --reasoning-parser qwen3 \
  --speculative-config '{"method":"mtp","num_speculative_tokens":4}' \
  --default-chat-template-kwargs '{"enable_thinking":false}'
