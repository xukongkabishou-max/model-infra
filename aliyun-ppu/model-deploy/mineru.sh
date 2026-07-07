#!/bin/bash
#基础镜像ppu150-pytorch26-ppu-py310-cu126-ubuntu2204


#适配构建
# git clone https://github.com/opendatalab/MinerU.git
# cd MinerU/
# pip install -e .
# pip uninstall numpy scipy pandas
# pip install numpy scipy pandas

# mineru -v
# 2025-09-05 17:19:23.619 | WARNING  | mineru.backend.vlm.predictor:<module>:35 - sglang is not installed. If you are not using sglang, you can ignore this warning.
# mineru, version 2.1.11

nerdctl run  \
  --name mineru-zzxy \
  --hostname mineru-host \
   --device /dev/alixpu \
  $(for dev in /dev/alixpu_ppu[1-2]*; do echo "--device $dev"; done) \
  --device /dev/alixpu_ctl \
  --network host \
  --shm-size=20g \
  -e MINERU_MODEL_SOURCE=local \
  -w /sgl-workspace \
  ppu150-pytorch26-ppu-py310-cu126-ubuntu2204 \
