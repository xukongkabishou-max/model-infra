docker run -d \
  --ipc host \
  --cap-add SYS_PTRACE \
  --privileged=true \
  --device=/dev/mem \
  --device=/dev/mxcd \
  --device=/dev/dri/card3 \
  --device=/dev/dri/renderD130 \
  --device=/dev/infiniband \
  --group-add video \
  --network=host \
  --shm-size '100gb' \
  --ulimit memlock=-1 \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --name mineru_vllm_parse \
  -v /datapool:/datapool \
  -v /data/model:/data/model \
  -v /data/model/modelscope-cache:/root/.cache/modelscope \
  -e MINERU_MODEL_SOURCE=local \
  -e MINERU_LMDEPLOY_DEVICE=maca \
  -e CUDA_VISIBLE_DEVICES=2 \
  -e MACA_VISIBLE_DEVICES=2 \
  -e VLLM_WORKER_MULTIPROC_METHOD=spawn \
  mineru:maca-vllm-nomodel-libgl \
  /bin/bash -lc 'cp /data/model/mineru.json /root/mineru.json 2>/dev/null || true; exec /opt/conda/bin/mineru -p /data/model/测试图文-全局.pdf -o /data/model/mineru-output-vllm-gpu2 -b vlm-auto-engine --image-analysis true'