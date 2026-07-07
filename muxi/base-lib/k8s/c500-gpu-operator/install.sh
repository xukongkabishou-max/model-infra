#!/bin/bash
helm upgrade metax-operator-0-1780477739 ./metax-operator-0.15.1.tgz \
  -n metax-operator \
  --wait \
  --set registry=cr.metax-tech.com/cloud \
  --set driver.payload.version=3.7.2.30-amd64 \
  --set maca.payload.registry=harbor.gpu.ecmasai.com:543/library \
  --set 'maca.payload.images={maca-native:3.7.2.1-kylinv11-amd64-findfix}' \
  --set 'gpuScheduler.deploy=true' \
  --set gpuScheduler.kubeScheduler.image.registry=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io \
  --set gpuScheduler.kubeScheduler.image.version=v1.28.9
