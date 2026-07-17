#!/usr/bin/env python3
"""vLLM 连续调用稳定性测试。

脚本按顺序发送流式请求，测量每次请求的端到端延迟、首 Token 延迟（TTFT）
和 Decode 阶段输出速度。每个请求都使用不同的 UUID，避免前缀缓存影响结果。
"""

import argparse
import json
import statistics
import time
import uuid

import requests


def percentile(values, percent):
    """使用 nearest-rank 风格从一组样本中取指定百分位值。"""
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, round((len(ordered) - 1) * percent)))
    return ordered[index]


def run_one(args, index):
    """发送一次流式 Chat Completions 请求并返回性能指标。"""
    # 唯一 ID 放在提示词开头，使不同请求不共享完整的 KV Cache 前缀块。
    request_id = uuid.uuid4().hex
    payload = {
        "model": args.model,
        "messages": [
            {
                "role": "user",
                "content": (
                    f"Unique request id: {request_id}. "
                    "Explain in about 100 words why service health checks matter."
                ),
            }
        ],
        "max_tokens": args.max_tokens,
        "temperature": 0.6,
        "stream": True,
        "stream_options": {"include_usage": True},
    }

    # perf_counter 使用单调高精度时钟，不受系统时间校准影响。
    started = time.perf_counter()
    first_token_at = None
    completion_tokens = 0
    output_parts = []

    with requests.post(
        f"{args.url}/v1/chat/completions",
        json=payload,
        stream=True,
        timeout=(10, args.timeout),
    ) as response:
        response.raise_for_status()
        # vLLM 流式接口采用 SSE，每一行有效事件以 "data:" 开头。
        for raw_line in response.iter_lines(decode_unicode=True):
            if not raw_line or not raw_line.startswith("data:"):
                continue
            data = raw_line[5:].strip()
            if data == "[DONE]":
                break
            event = json.loads(data)
            # include_usage=True 时，最后几个事件会携带精确 Token 用量。
            usage = event.get("usage") or {}
            completion_tokens = usage.get("completion_tokens", completion_tokens)
            for choice in event.get("choices") or []:
                delta = choice.get("delta") or {}
                # DeepSeek 可能先返回 reasoning_content，再返回普通 content。
                text = delta.get("reasoning_content") or delta.get("content") or ""
                if text:
                    if first_token_at is None:
                        first_token_at = time.perf_counter()
                    output_parts.append(text)

    ended = time.perf_counter()
    ttft = (first_token_at - started) if first_token_at else None
    generation_time = (ended - first_token_at) if first_token_at else None
    # Decode 速度只统计收到第一个 Token 之后的阶段，不包含 TTFT。
    output_tps = (
        completion_tokens / generation_time
        if completion_tokens and generation_time and generation_time > 0
        else 0.0
    )
    return {
        "index": index,
        "request_id": request_id,
        "latency": ended - started,
        "ttft": ttft,
        "completion_tokens": completion_tokens,
        "output_tps": output_tps,
        "output_chars": len("".join(output_parts)),
    }


def main():
    parser = argparse.ArgumentParser(description="连续流式调用稳定性和 TTFT 测试")
    parser.add_argument("--url", default="http://127.0.0.1:7000", help="vLLM 服务根地址")
    parser.add_argument("--model", default="ds", help="API 中使用的模型名")
    parser.add_argument("--requests", type=int, default=20, help="顺序请求总数")
    parser.add_argument("--max-tokens", type=int, default=128, help="每次最多生成的 Token 数")
    parser.add_argument("--timeout", type=int, default=600, help="单次请求读取超时，单位秒")
    parser.add_argument("--interval", type=float, default=1.0, help="相邻请求之间的等待秒数")
    args = parser.parse_args()

    print("=== 输出字段说明 ===")
    print("latency: 从发出请求到流式响应结束的端到端耗时")
    print("ttft: Time To First Token，从发出请求到收到首个输出片段的耗时")
    print("output_tokens: 服务端统计的实际生成 Token 数")
    print("decode: 首 Token 返回后到生成结束期间的平均输出速度\n")

    results = []
    failures = 0
    suite_started = time.perf_counter()
    for index in range(1, args.requests + 1):
        try:
            result = run_one(args, index)
            results.append(result)
            ttft_text = f"{result['ttft']:.3f}s" if result["ttft"] else "N/A"
            print(
                f"[{index:03d}/{args.requests:03d}] OK "
                f"latency={result['latency']:.3f}s ttft={ttft_text} "
                f"output_tokens={result['completion_tokens']} "
                f"decode={result['output_tps']:.2f} tok/s"
            )
        except Exception as exc:
            failures += 1
            print(f"[{index:03d}/{args.requests:03d}] FAILED {type(exc).__name__}: {exc}")
        if index != args.requests and args.interval > 0:
            time.sleep(args.interval)

    # wall_time 包含所有请求耗时以及请求之间的 interval 等待时间。
    wall_time = time.perf_counter() - suite_started
    latencies = [item["latency"] for item in results]
    ttfts = [item["ttft"] for item in results if item["ttft"] is not None]
    print("\n=== Continuous call summary ===")
    print(f"success={len(results)} failed={failures} total={args.requests}")
    print(f"wall_time={wall_time:.3f}s")
    if results:
        print(
            f"latency_avg={statistics.mean(latencies):.3f}s "
            f"latency_p50={percentile(latencies, 0.50):.3f}s "
            f"latency_p95={percentile(latencies, 0.95):.3f}s"
        )
        if ttfts:
            print(
                f"ttft_avg={statistics.mean(ttfts):.3f}s "
                f"ttft_p50={percentile(ttfts, 0.50):.3f}s "
                f"ttft_p95={percentile(ttfts, 0.95):.3f}s"
            )


if __name__ == "__main__":
    main()