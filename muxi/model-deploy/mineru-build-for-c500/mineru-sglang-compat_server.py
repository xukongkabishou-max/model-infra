import base64
import io
import os
import signal
import asyncio
import time
from typing import Any, Dict

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse
from PIL import Image

VLLM_BASE_URL = os.getenv("VLLM_BASE_URL", "http://127.0.0.1:30000")
MODEL_PATH = os.getenv("MINERU_VLM_MODEL_PATH", "/root/.cache/modelscope/hub/models/OpenDataLab/MinerU2___5-Pro-2605-1___2B")
SERVED_MODEL_NAME = os.getenv("MINERU_SERVED_MODEL_NAME", "MinerU2.5-Pro-2605-1.2B")
HTTP_TIMEOUT = float(os.getenv("MINERU_COMPAT_HTTP_TIMEOUT", "1800"))
MAX_COMPAT_TOKENS = int(os.getenv("MINERU_COMPAT_MAX_TOKENS", "4096"))
ENABLE_RAG_COMPAT = os.getenv("MINERU_RAG_COMPAT_ENABLE", "true").lower() in {"1", "true", "yes", "on"}

app = FastAPI(title="MinerU sglang-client compatibility API")
_mineru_client = None


def _openai_model() -> str:
    try:
        with httpx.Client(timeout=10) as client:
            resp = client.get(f"{VLLM_BASE_URL}/v1/models")
            if resp.status_code == 200:
                data = resp.json().get("data") or []
                if data and data[0].get("id"):
                    return data[0]["id"]
    except Exception:
        pass
    return SERVED_MODEL_NAME


def _sampling_to_openai(params: Dict[str, Any]) -> Dict[str, Any]:
    mapped: Dict[str, Any] = {}
    if params.get("temperature") is not None:
        mapped["temperature"] = params["temperature"]
    if params.get("top_p") is not None:
        mapped["top_p"] = params["top_p"]
    requested_tokens = params.get("max_new_tokens") if params.get("max_new_tokens") is not None else params.get("max_tokens")
    if requested_tokens is not None:
        mapped["max_tokens"] = min(int(requested_tokens), MAX_COMPAT_TOKENS)
    if params.get("repetition_penalty") is not None:
        mapped["repetition_penalty"] = params["repetition_penalty"]
    return mapped


def _build_chat_payload(body: Dict[str, Any], stream: bool = False) -> Dict[str, Any]:
    prompt = body.get("text") or body.get("prompt") or ""
    image_data = body.get("image_data") or body.get("image")
    sampling = body.get("sampling_params") or {}
    content: list[Dict[str, Any]] = [{"type": "text", "text": prompt}]
    if image_data:
        image_url = image_data if isinstance(image_data, str) and image_data.startswith("data:") else f"data:image/png;base64,{image_data}"
        content.append({"type": "image_url", "image_url": {"url": image_url}})
    payload: Dict[str, Any] = {"model": _openai_model(), "messages": [{"role": "user", "content": content}], "stream": stream}
    payload.update(_sampling_to_openai(sampling))
    return payload


def _looks_like_old_mineru_request(body: Dict[str, Any]) -> bool:
    text = body.get("text") or body.get("prompt") or ""
    return bool(body.get("image_data") or body.get("image")) and ("Document Parsing:" in text or "<|im_start|>" in text)


def _decode_image(body: Dict[str, Any]) -> Image.Image:
    image_data = body.get("image_data") or body.get("image")
    if not image_data:
        raise ValueError("image_data is required")
    if isinstance(image_data, str) and image_data.startswith("data:"):
        image_data = image_data.split(",", 1)[1]
    raw = base64.b64decode(image_data)
    return Image.open(io.BytesIO(raw)).convert("RGB")


def _get_mineru_client():
    global _mineru_client
    if _mineru_client is None:
        from mineru_vl_utils.mineru_client import MinerUClient
        _mineru_client = MinerUClient(
            backend="http-client",
            server_url=VLLM_BASE_URL,
            model_name=_openai_model(),
            use_tqdm=False,
            image_analysis=False,
            max_concurrency=int(os.getenv("MINERU_COMPAT_MAX_CONCURRENCY", "4")),
            http_timeout=int(HTTP_TIMEOUT),
            connect_timeout=10,
            skip_model_name_checking=True,
        )
    return _mineru_client


def _escape_md(content: str | None) -> str:
    return (content or "").replace("<|md_end|>", "").replace("<|im_end|>", "")


def _bbox_to_1000(bbox) -> str:
    vals = [max(0, min(999, int(round(float(x) * 1000)))) for x in bbox]
    if vals[0] >= vals[2]:
        vals[2] = min(999, vals[0] + 1)
    if vals[1] >= vals[3]:
        vals[3] = min(999, vals[1] + 1)
    return "%03d %03d %03d %03d" % tuple(vals)


def _old_type(block_type: str) -> str:
    return {
        "equation_block": "equation",
        "list_item": "text",
        "aside_text": "text",
        "ref_text": "text",
        "image_block": "image",
        "chart": "image",
    }.get(block_type, block_type)


def _blocks_to_old_token(blocks) -> str:
    parts: list[str] = []
    for block in blocks:
        block_type = _old_type(block.get("type"))
        content = block.get("content")
        # Old MinerU 2.0 parser can crop image/table by token, but rag-embedding mainly needs markdown text.
        # Skip empty visual/container blocks to avoid generating empty image placeholders.
        if block_type in {"image", "table"} and not content:
            continue
        if not content and block_type not in {"equation"}:
            continue
        if block_type == "title" and content and not content.lstrip().startswith("#"):
            content = "# " + content
        parts.append(
            f"<|box_start|>{_bbox_to_1000(block.get('bbox'))}<|box_end|>"
            f"<|ref_start|>{block_type}<|ref_end|>"
            f"<|md_start|>{_escape_md(content)}<|md_end|>"
        )
    return "\n".join(parts) + "<|im_end|>"


def _generate_rag_compatible_token(body: Dict[str, Any]) -> str:
    image = _decode_image(body)
    client = _get_mineru_client()
    blocks = client.two_step_extract(image, image_analysis=False)
    return _blocks_to_old_token(blocks)


@app.get("/health")
async def health():
    return {"status": "healthy", "compat": "mineru-sglang-client", "rag_compat": ENABLE_RAG_COMPAT, "vllm_base_url": VLLM_BASE_URL}


@app.get("/health_generate")
async def health_generate():
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(f"{VLLM_BASE_URL}/health")
            if resp.status_code in (200, 404):
                models = await client.get(f"{VLLM_BASE_URL}/v1/models")
                if models.status_code == 200:
                    return {"status": "healthy"}
        raise HTTPException(status_code=503, detail="vLLM backend is not ready")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"vLLM backend is not reachable: {exc}")


@app.get("/get_model_info")
async def get_model_info():
    return {"model_path": MODEL_PATH}


@app.api_route("/generate", methods=["POST", "PUT"])
async def generate(request: Request):
    body = await request.json()
    stream = bool(body.get("stream"))
    if ENABLE_RAG_COMPAT and not stream and _looks_like_old_mineru_request(body):
        try:
            text = await asyncio.to_thread(_generate_rag_compatible_token, body)
            return JSONResponse({"text": text})
        except Exception as exc:
            raise HTTPException(status_code=502, detail=f"rag-compatible MinerU parse failed: {exc}")

    payload = _build_chat_payload(body, stream=stream)
    url = f"{VLLM_BASE_URL}/v1/chat/completions"
    if stream:
        async def event_stream():
            async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
                async with client.stream("POST", url, json=payload) as resp:
                    if resp.status_code >= 400:
                        detail = await resp.aread()
                        yield f"data: {{\"text\": \"\", \"error\": {detail.decode('utf-8', 'replace')!r}}}\n\n"
                        yield "data: [DONE]\n\n"
                        return
                    async for line in resp.aiter_lines():
                        if not line or not line.startswith("data:"):
                            continue
                        if line.strip() == "data: [DONE]":
                            yield "data: [DONE]\n\n"
                            break
                        import json
                        chunk = json.loads(line[5:].strip())
                        delta = chunk.get("choices", [{}])[0].get("delta", {}).get("content") or ""
                        yield f"data: {json.dumps({'text': delta}, ensure_ascii=False)}\n\n"
        return StreamingResponse(event_stream(), media_type="text/event-stream")

    try:
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
            resp = await client.post(url, json=payload)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"vLLM request failed: {exc}")
    if resp.status_code >= 400:
        raise HTTPException(status_code=resp.status_code, detail=resp.text)
    data = resp.json()
    text = data.get("choices", [{}])[0].get("message", {}).get("content") or ""
    return JSONResponse({"text": text})
