# LMDeploy for Ascend 910B / A2
FROM crpi-4crprmm5baj1v8iv.cn-hangzhou.personal.cr.aliyuncs.com/lmdeploy_dlinfer/ascend:mineru-a2

ARG BACKEND=lmdeploy

# Use Aliyun apt mirror
RUN . /etc/os-release && \
    CODENAME="${VERSION_CODENAME:-jammy}" && \
    rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources && \
    printf '%s\n' \
      "deb https://mirrors.aliyun.com/ubuntu-ports/ ${CODENAME} main restricted universe multiverse" \
      "deb https://mirrors.aliyun.com/ubuntu-ports/ ${CODENAME}-updates main restricted universe multiverse" \
      "deb https://mirrors.aliyun.com/ubuntu-ports/ ${CODENAME}-backports main restricted universe multiverse" \
      "deb https://mirrors.aliyun.com/ubuntu-ports/ ${CODENAME}-security main restricted universe multiverse" \
      > /etc/apt/sources.list

# Install libgl for opencv support & Noto fonts for Chinese characters
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fonts-noto-core \
        fonts-noto-cjk \
        fontconfig \
        libgl1 \
        libglib2.0-0 && \
    fc-cache -fv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install MinerU, do not download models in image build
RUN python3 -m pip install -U pip -i https://mirrors.aliyun.com/pypi/simple && \
    python3 -m pip install \
        'mineru[core]>=3.4.0' \
        numpy==1.26.4 \
        opencv-python==4.11.0.86 \
        -i https://mirrors.aliyun.com/pypi/simple && \
    if [ "$BACKEND" = "lmdeploy" ]; then \
        python3 -m pip install 'qwen-vl-utils>=0.0.14,<1' -i https://mirrors.aliyun.com/pypi/simple; \
    fi && \
    python3 -m pip cache purge

ENV MINERU_MODEL_SOURCE=local

ENTRYPOINT ["/bin/bash", "-c", "exec \"$@\"", "--"]