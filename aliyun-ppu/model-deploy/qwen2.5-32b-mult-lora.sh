nerdctl run -it --rm \
  -v /data/nvme0/data/models:/models \
  --network=host \
  --shm-size=128g \
  --device /dev/alixpu \
  $(for dev in /dev/alixpu_ppu[1-7]*; do echo "--device $dev"; done) \
  --device /dev/alixpu_ctl \
  --name qwen-lora \
  asllm:1.3.1-pytorch2.6.0-ubuntu24.04-cuda12.6-vllm0.8.3-sglang0.4.6.post1-py312 \
  vllm serve /models/Qwen2.5-32B-Instruct \
    --served-model-name base-qwen-model \
    --enable-lora \
    --max-loras 10 \
    --max-lora-rank 32 \
    --lora-modules \
      multi_turn_rewrite=/models/multi_turn_rewrite/multi_turn_rewrite \
      fuzzy_clear_classify=/models/fuzzy_clear_classify/fuzzy_classify \
      min_unit_judge=/models/min_unit_judge/min_unit_judge \
      slot_extract=/models/slot_extract/slot_extract \
      classify=/models/classify/agent-sop \
      photovoltaic=/models/photovoltaic/checkpoint-3000 \
      photovoltaic_fewshots=/models/photovoltaic_fewshots/checkpoint-3000 \
      device=/models/device/checkpoint-3000 \
      energy_usage_scds=/models/energy_usage_scds/checkpoint-4100 \
      energy_usage_sw=/models/energy_usage_sw/checkpoint-2800 \
    --dtype auto \
    --max-model-len 8192 \
    --gpu-memory-utilization 0.85 \
    --trust-remote-code \
    --tensor-parallel-size 4 \
    --port 8113 \
    --enable-prefix-caching \
    --max-num-seqs 64