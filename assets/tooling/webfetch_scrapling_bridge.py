#!/usr/bin/env python3
import json
import platform
import sys
import traceback


def _emit(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def _normalize_text(value):
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return str(value)


def _probe():
    try:
        import scrapling  # noqa: F401
        from scrapling.fetchers import Fetcher  # noqa: F401
    except ModuleNotFoundError as error:
        name = getattr(error, "name", "") or ""
        if name == "scrapling":
            return {
                "ok": False,
                "error": "scrapling_not_installed",
                "detail": "请执行：pip install 'scrapling[fetchers]'",
            }
        return {
            "ok": False,
            "error": "scrapling_fetchers_missing",
            "detail": f"缺少 Python 模块：{name}。请执行：pip install 'scrapling[fetchers]'",
        }
    except ImportError as error:
        detail = f"{type(error).__name__}: {error}"
        architecture_mismatch = "incompatible architecture" in detail.lower()
        return {
            "ok": False,
            "error": (
                "python_architecture_mismatch"
                if architecture_mismatch
                else "scrapling_probe_failed"
            ),
            "detail": detail,
        }
    except Exception as error:
        return {
            "ok": False,
            "error": "scrapling_probe_failed",
            "detail": f"{type(error).__name__}: {error}",
        }
    return {
        "ok": True,
        "python": sys.executable,
        "python_architecture": platform.machine(),
        "runtime_installed": True,
    }


def _handle_fetch(request):
    from scrapling.fetchers import Fetcher

    url = _normalize_text(request.get("url")).strip()
    if not url:
        return {
            "ok": False,
            "error": "missing_url",
            "detail": "URL 不能为空",
        }

    timeout_seconds = int(request.get("timeout_seconds") or 30)
    timeout_seconds = 5 if timeout_seconds < 5 else timeout_seconds
    timeout_seconds = 180 if timeout_seconds > 180 else timeout_seconds
    max_chars = int(request.get("max_chars") or 100000)
    max_chars = 1000 if max_chars < 1000 else max_chars
    max_chars = 400000 if max_chars > 400000 else max_chars

    response = Fetcher.get(
        url,
        timeout=timeout_seconds,
        follow_redirects=False,
        verify=True,
        stealthy_headers=True,
    )

    content = _normalize_text(response.get_all_text(separator="\n", strip=True))
    if not content.strip():
        content = _normalize_text(response.html_content)
    if len(content) > max_chars:
        content = content[:max_chars] + "…"

    title = ""
    try:
        title = _normalize_text(response.css("title::text").get()).strip()
    except Exception:
        title = ""

    headers = {}
    try:
        raw_headers = getattr(response, "headers", None) or {}
        headers = {str(k).lower(): _normalize_text(v) for k, v in dict(raw_headers).items()}
    except Exception:
        headers = {}

    status_code = getattr(response, "status", None)
    final_url = _normalize_text(getattr(response, "url", "")).strip() or url
    content_type = headers.get("content-type", "text/html")

    return {
        "ok": True,
        "final_url": final_url,
        "title": title,
        "content": content,
        "content_type": content_type,
        "status_code": status_code,
        "response_headers": headers,
    }


def main():
    _emit({"type": "ready", **_probe()})
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        request_id = None
        try:
            request = json.loads(raw)
            if not isinstance(request, dict):
                raise ValueError("请求必须是 JSON 对象")
            request_id = request.get("id")
            command = _normalize_text(request.get("command")).strip().lower()
            if command == "ping":
                _emit({"id": request_id, "ok": True, "pong": True})
                continue
            if command == "probe":
                _emit({"id": request_id, **_probe()})
                continue
            if command == "fetch":
                _emit({"id": request_id, **_handle_fetch(request)})
                continue
            _emit({
                "id": request_id,
                "ok": False,
                "error": "unsupported_command",
                "detail": f"不支持的命令：{command}",
            })
        except ModuleNotFoundError as error:
            name = getattr(error, "name", "") or ""
            code = "scrapling_not_installed" if name == "scrapling" else "scrapling_fetchers_missing"
            _emit({
                "id": request_id,
                "ok": False,
                "error": code,
                "detail": f"缺少 Python 模块：{name}",
            })
        except Exception as error:
            _emit({
                "id": request_id,
                "ok": False,
                "error": "bridge_exception",
                "detail": f"{type(error).__name__}: {error}",
                "traceback": traceback.format_exc(limit=6),
            })


if __name__ == "__main__":
    main()
