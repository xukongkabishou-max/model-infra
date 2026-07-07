FROM mineru:maca-vllm-nomodel-libgl

WORKDIR /opt/mineru-compat
COPY mineru_sglang_compat_server.py /opt/mineru-compat/mineru_sglang_compat_server.py
COPY start-mineru-sglang-compat.sh /opt/mineru-compat/start-mineru-sglang-compat.sh
RUN chmod +x /opt/mineru-compat/start-mineru-sglang-compat.sh

EXPOSE 16543
CMD ["/opt/mineru-compat/start-mineru-sglang-compat.sh"]
