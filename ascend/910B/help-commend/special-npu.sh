docker run --rm \
  --device=/dev/davinci4 \ #挂载具体的卡
  --device=/dev/davinci_manager \
  --device=/dev/devmm_svm \
  --device=/dev/hisi_hdc \
  ...