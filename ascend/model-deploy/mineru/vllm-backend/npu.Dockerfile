#相较于官方的vllm-ascend镜像，修改了基础镜像版本 ，官方的vllm-ascend镜像的transformers版本不兼容，并且修改了apt 安装源的地址，还有删除了下载模型的操作
# ARM64 + Ascend 910B
FROM quay.m.daocloud.io/ascend/vllm-ascend:v0.13.0

ARG BACKEND=vllm
ARG APT_MIRROR=https://mirrors.aliyun.com/ubuntu-ports

# 强制使用阿里云 ARM64 Ubuntu 软件源
RUN set -eux; \
    . /etc/os-release; \
    CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"; \
    test -n "${CODENAME}"; \
    rm -f /etc/apt/sources.list.d/*.list; \
    rm -f /etc/apt/sources.list.d/*.sources; \
    printf '%s\n' \
        "deb [arch=arm64] ${APT_MIRROR} ${CODENAME} main restricted universe multiverse" \
        "deb [arch=arm64] ${APT_MIRROR} ${CODENAME}-updates main restricted universe multiverse" \
        "deb [arch=arm64] ${APT_MIRROR} ${CODENAME}-backports main restricted universe multiverse" \
        "deb [arch=arm64] ${APT_MIRROR} ${CODENAME}-security main restricted universe multiverse" \
        > /etc/apt/sources.list; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get -o Acquire::Retries=5 update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        fonts-noto-core \
        fonts-noto-cjk \
        fontconfig \
        libgl1 \
        libglib2.0-0; \
    fc-cache -fv; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 安装 MinerU，Python 包使用阿里云源
RUN python3 -m pip install -U pip \
        -i https://mirrors.aliyun.com/pypi/simple && \
    python3 -m pip install \
        'mineru[core]>=3.4.0' \
        numpy==1.26.4 \
        opencv-python==4.11.0.86 \
        -i https://mirrors.aliyun.com/pypi/simple && \
    if [ "${BACKEND}" = "lmdeploy" ]; then \
        python3 -m pip install \
            'qwen-vl-utils>=0.0.14,<1' \
            -i https://mirrors.aliyun.com/pypi/simple; \
    fi && \
    python3 -m pip cache purge

ENV MINERU_MODEL_SOURCE=local
ENV MINERU_LMDEPLOY_DEVICE=ascend
ENV VLLM_WORKER_MULTIPROC_METHOD=spawn

ENTRYPOINT ["/bin/bash", "-c", "exec \"$@\"", "--"]