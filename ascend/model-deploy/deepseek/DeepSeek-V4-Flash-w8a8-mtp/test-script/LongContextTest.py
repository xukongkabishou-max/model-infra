#!/usr/bin/env python3
"""vLLM 长上下文能力测试。

脚本通过 /tokenize 把提示词校准到指定 Token 数，然后从小到大逐档调用模型。
每档提示词开头包含唯一 UUID，因此测试结果不依赖前缀缓存。
"""

import argparse
import time
import uuid

import requests


# 重复这段稳定文本来构造长提示词，避免随机内容带来的额外变量。
CHUNK = (
    "Distributed inference systems divide model computation across accelerators. "
    "Stable serving requires predictable memory use, communication, and scheduling. "
)


def token_count(args, prompt):
    """调用 vLLM /tokenize，获得指定文本的精确 Token 数。"""
    response = requests.post(
        f"{args.url}/tokenize",
        json={"model": args.model, "prompt": prompt},
        timeout=(10, args.timeout),
    )
    response.raise_for_status()
    data = response.json()
    if "count" in data:
        return int(data["count"])
    if "tokens" in data:
        return len(data["tokens"])
    raise RuntimeError(f"Unexpected /tokenize response: {data}")


def calibrated_prompt(args, target_tokens, use_tokenizer):
    """通过指数扩展和二分搜索生成接近目标 Token 数的提示词。"""
    unique_prefix = f"Unique test id: {uuid.uuid4().hex}.\n"
    suffix = "\nSummarize the main recurring idea in one short sentence."
    if not use_tokenizer:
        # /tokenize 不可用时只能按英文文本约 4 字符/Token 粗略估算。
        estimated_chars_per_token = 4
        needed = max(1, target_tokens * estimated_chars_per_token)
        repeats = max(1, needed // len(CHUNK))
        return unique_prefix + (CHUNK * repeats) + suffix, None

    # 先指数扩大重复次数，快速找到覆盖目标值的搜索上界。
    low, high = 1, 1
    while token_count(args, unique_prefix + CHUNK * high + suffix) < target_tokens:
        high *= 2
    best_prompt = None
    best_count = None
    # 再用二分搜索寻找最接近 target_tokens 的重复次数。
    while low <= high:
        middle = (low + high) // 2
        prompt = unique_prefix + CHUNK * middle + suffix
        count = token_count(args, prompt)
        if best_count is None or abs(count - target_tokens) < abs(best_count - target_tokens):
            best_prompt, best_count = prompt, count
        if count < target_tokens:
            low = middle + 1
        elif count > target_tokens:
            high = middle - 1
        else:
            break
    return best_prompt, best_count


def run_case(args, target_tokens, use_tokenizer):
    """构造一个目标长度请求，调用模型并收集实际 Token 数与延迟。"""
    prompt, calibrated_tokens = calibrated_prompt(args, target_tokens, use_tokenizer)
    payload = {
        "model": args.model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": args.max_tokens,
        "temperature": 0,
    }
    started = time.perf_counter()
    response = requests.post(
        f"{args.url}/v1/chat/completions",
        json=payload,
        timeout=(10, args.timeout),
    )
    latency = time.perf_counter() - started
    response.raise_for_status()
    data = response.json()
    usage = data.get("usage") or {}
    text = data["choices"][0]["message"].get("content") or ""
    return {
        "target_tokens": target_tokens,
        "calibrated_tokens": calibrated_tokens,
        "actual_prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": usage.get("completion_tokens"),
        "latency": latency,
        "answer": text.replace("\n", " ")[:160],
    }


def main():
    parser = argparse.ArgumentParser(description="逐档验证 vLLM 长上下文能力")
    parser.add_argument("--url", default="http://127.0.0.1:7000", help="vLLM 服务根地址")
    parser.add_argument("--model", default="ds", help="API 中使用的模型名")
    parser.add_argument("--targets", default="8192,32768,65536,120000", help="逗号分隔的目标 Token 档位")
    parser.add_argument("--max-tokens", type=int, default=64, help="每档测试最多生成的 Token 数")
    parser.add_argument("--timeout", type=int, default=1800, help="单次长请求读取超时，单位秒")
    args = parser.parse_args()
    targets = [int(value.strip()) for value in args.targets.split(",") if value.strip()]

    print("=== 输出字段说明 ===")
    print("target: 计划测试的输入 Token 数")
    print("calibrated: /tokenize 校准后的纯提示词 Token 数")
    print("actual_prompt: 加入聊天模板后，服务端实际统计的输入 Token 数")
    print("completion: 实际生成 Token 数；latency: 整个非流式请求耗时\n")

    use_tokenizer = True
    try:
        probe = token_count(args, "tokenizer probe")
        print(f"/tokenize available, probe_tokens={probe}")
    except Exception as exc:
        use_tokenizer = False
        print(f"WARNING: /tokenize unavailable ({type(exc).__name__}: {exc})")
        print("Falling back to an approximate 4 characters per token.")

    passed = 0
    failures = 0
    for target in targets:
        print(f"\n--- Target context: {target} tokens ---")
        try:
            result = run_case(args, target, use_tokenizer)
            print(
                f"OK target={target} calibrated={result['calibrated_tokens']} "
                f"actual_prompt={result['actual_prompt_tokens']} "
                f"completion={result['completion_tokens']} latency={result['latency']:.3f}s"
            )
            print(f"answer={result['answer']}")
            passed += 1
        except Exception as exc:
            failures += 1
            print(f"FAILED target={target}: {type(exc).__name__}: {exc}")
            # 小档位失败后不继续施加更大的上下文压力。
            print("Stopping larger contexts because this size did not pass.")
            break

    print(f"\nLong-context test finished: passed={passed} failed={failures}")


if __name__ == "__main__":
    main()