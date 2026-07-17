#!/usr/bin/env python3
"""vLLM 阶梯式并发压测。

脚本依次提升并发度，每档使用线程池同时发送多个非流式请求，统计成功率、
请求延迟和 Token 吞吐。每个请求都带唯一 UUID，避免前缀缓存污染压测结果。
"""

import argparse
import concurrent.futures
import statistics
import time
import uuid

import requests


def percentile(values, percent):
    """返回一组延迟样本的指定百分位值。"""
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, round((len(ordered) - 1) * percent)))
    return ordered[index]


def send_request(args, level, index):
    """发送单个请求；异常会转成失败结果，避免线程终止整个测试。"""
    # UUID 位于提示词前部，确保请求之间没有可复用的长前缀。
    request_id = uuid.uuid4().hex
    payload = {
        "model": args.model,
        "messages": [
            {
                "role": "user",
                "content": (
                    f"Unique request id: {request_id}. Concurrency level: {level}. "
                    "Write a concise technical explanation of load balancing."
                ),
            }
        ],
        "max_tokens": args.max_tokens,
        "temperature": 0.6,
    }
    started = time.perf_counter()
    try:
        response = requests.post(
            f"{args.url}/v1/chat/completions",
            json=payload,
            timeout=(10, args.timeout),
        )
        latency = time.perf_counter() - started
        response.raise_for_status()
        data = response.json()
        usage = data.get("usage") or {}
        return {
            "ok": True,
            "latency": latency,
            "prompt_tokens": int(usage.get("prompt_tokens") or 0),
            "completion_tokens": int(usage.get("completion_tokens") or 0),
        }
    except Exception as exc:
        return {
            "ok": False,
            "latency": time.perf_counter() - started,
            "error": f"{type(exc).__name__}: {exc}",
            "prompt_tokens": 0,
            "completion_tokens": 0,
        }


def run_level(args, concurrency):
    """以指定并发度完成一个压测档位并打印汇总指标。"""
    # 请求数至少等于并发数，确保每个工作线程都有任务。
    count = max(concurrency, args.requests_per_level)
    started = time.perf_counter()
    # 线程池负责 HTTP I/O 并发，实际模型计算在远端 NPU 服务完成。
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(send_request, args, concurrency, i) for i in range(count)]
        results = [future.result() for future in concurrent.futures.as_completed(futures)]
    wall_time = time.perf_counter() - started

    successes = [item for item in results if item["ok"]]
    failures = [item for item in results if not item["ok"]]
    latencies = [item["latency"] for item in successes]
    # 吞吐使用整个档位的总 Token 数除以该档位墙钟时间。
    prompt_tokens = sum(item["prompt_tokens"] for item in successes)
    completion_tokens = sum(item["completion_tokens"] for item in successes)

    print(f"\n=== concurrency={concurrency} requests={count} ===")
    print(
        f"success={len(successes)} failed={len(failures)} wall_time={wall_time:.3f}s "
        f"request_rate={len(successes) / wall_time:.3f} req/s"
    )
    if successes:
        print(
            f"latency_avg={statistics.mean(latencies):.3f}s "
            f"p50={percentile(latencies, 0.50):.3f}s "
            f"p95={percentile(latencies, 0.95):.3f}s "
            f"p99={percentile(latencies, 0.99):.3f}s"
        )
        print(
            f"prompt_throughput={prompt_tokens / wall_time:.2f} tok/s "
            f"output_throughput={completion_tokens / wall_time:.2f} tok/s "
            f"total_throughput={(prompt_tokens + completion_tokens) / wall_time:.2f} tok/s"
        )
    for failure in failures[:3]:
        print(f"sample_error={failure['error']}")
    return len(failures) == 0


def main():
    parser = argparse.ArgumentParser(description="阶梯式并发压测 vLLM OpenAI 接口")
    parser.add_argument("--url", default="http://127.0.0.1:7000", help="vLLM 服务根地址")
    parser.add_argument("--model", default="ds", help="API 中使用的模型名")
    parser.add_argument("--concurrency", default="1,2,4,8,16", help="逗号分隔的并发档位")
    parser.add_argument("--requests-per-level", type=int, default=32, help="每个并发档位的请求总数")
    parser.add_argument("--max-tokens", type=int, default=128, help="每个请求最多生成的 Token 数")
    parser.add_argument("--timeout", type=int, default=900, help="单次请求读取超时，单位秒")
    parser.add_argument("--pause", type=float, default=5.0, help="两个并发档位之间的冷却秒数")
    parser.add_argument("--continue-on-error", action="store_true", help="某档失败后仍继续升高并发")
    args = parser.parse_args()
    levels = [int(value.strip()) for value in args.concurrency.split(",") if value.strip()]

    print("=== 输出字段说明 ===")
    print("request_rate: 每秒完成的成功请求数")
    print("latency_avg/p50/p95/p99: 请求端到端平均及百分位延迟")
    print("prompt_throughput: 整个服务每秒处理的输入 Token 数")
    print("output_throughput: 整个服务每秒生成的输出 Token 数")
    print("total_throughput: 输入与输出 Token 吞吐之和\n")

    # 两次预热用于触发惰性初始化，降低首轮压测的冷启动偏差。
    print("Sending two warm-up requests...")
    for index in range(2):
        warmup = send_request(args, 0, index)
        print(f"warmup_{index + 1}={'OK' if warmup['ok'] else warmup['error']}")

    for index, level in enumerate(levels):
        passed = run_level(args, level)
        if not passed:
            print("This level had failures; review service logs before increasing load.")
            if not args.continue_on_error:
                print("Stopping the stepped load test. Use --continue-on-error to override.")
                break
        if index != len(levels) - 1 and args.pause > 0:
            time.sleep(args.pause)


if __name__ == "__main__":
    main()