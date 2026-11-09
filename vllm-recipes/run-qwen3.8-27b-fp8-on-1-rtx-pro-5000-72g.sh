docker run --gpus all \
  --ipc=host -p 8000:8000 \
  -e CUDA_VISIBLE_DEVICES=0 \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  -e VLLM_USE_RUST_FRONTEND=1 \
  vllm/vllm-openai:v0.33.0 Qwen/Qwen3.8-27B-FP8 \
  --trust-remote-code \
  --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.92 \
  --max-model-len 262144 \
  --max-num-seqs 12 \
  --max-num-batched-tokens 16384 \
  --kv-cache-dtype fp8 \
  --disable-custom-all-reduce \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --reasoning-parser qwen3 \
  --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
  --default-chat-template-kwargs '{"enable_thinking":false}'
