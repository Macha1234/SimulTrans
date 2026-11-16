#!/usr/bin/env python3
"""Small single-threaded OpenAI-compatible server for mlx-qwen3-asr.

The upstream ``mlx-qwen3-asr serve`` endpoint currently offloads transcription
through ``asyncio.to_thread``. MLX GPU streams are thread-local, so that can fail
on macOS with "There is no Stream(gpu, 1) in current thread."  SimulTrans only
needs one local transcription request at a time, so a single-threaded stdlib
HTTP server is simpler and more stable.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import traceback
import time
from dataclasses import asdict, is_dataclass
from email.parser import BytesParser
from email.policy import default
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any

class QwenASRServer(HTTPServer):
    def __init__(self, address: tuple[str, int], handler: type[BaseHTTPRequestHandler], args: argparse.Namespace) -> None:
        super().__init__(address, handler)
        import mlx.core as mx
        from mlx_qwen3_asr import Session

        self.args = args
        dtype = getattr(mx, args.dtype)
        print(f"[qwen-sidecar] loading {args.model} ({args.dtype})", flush=True)
        self.session = Session(model=args.model, dtype=dtype)
        print(f"[qwen-sidecar] ready: {self.session.model_info}", flush=True)


class Handler(BaseHTTPRequestHandler):
    server: QwenASRServer

    def log_message(self, format: str, *args: Any) -> None:
        print(f"[qwen-sidecar] {self.address_string()} - {format % args}", flush=True)

    def do_GET(self) -> None:
        if self.path in ("/", "/health", "/v1/health"):
            self.send_json({
                "status": "ok",
                "server": "simultrans-qwen-sidecar",
                "model": self.server.args.model,
            })
            return
        self.send_json({"detail": "not found"}, status=HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        if self.path != "/v1/audio/transcriptions":
            self.send_json({"detail": "not found"}, status=HTTPStatus.NOT_FOUND)
            return

        if not self.is_authorized():
            self.send_json({"detail": "unauthorized"}, status=HTTPStatus.UNAUTHORIZED)
            return

        try:
            fields, file_bytes, filename = self.read_multipart()
            language = fields.get("language") or None
            prompt = fields.get("prompt") or ""
            response_format = (fields.get("response_format") or "json").lower()

            suffix = Path(filename or "audio.wav").suffix or ".wav"
            with tempfile.NamedTemporaryFile(prefix="simultrans_qwen_", suffix=suffix, delete=False) as tmp:
                tmp.write(file_bytes)
                tmp_path = tmp.name

            try:
                result = self.server.session.transcribe(
                    tmp_path,
                    language=language,
                    context=prompt,
                    return_chunks=response_format == "verbose_json",
                )
            finally:
                Path(tmp_path).unlink(missing_ok=True)

            payload = result_to_dict(result)
            text = str(payload.get("text", "")).strip()

            if response_format == "text":
                self.send_text(text)
            elif response_format == "verbose_json":
                self.send_json(payload)
            else:
                self.send_json({"text": text})
        except Exception as exc:
            traceback.print_exc()
            self.send_json({"detail": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)

    def is_authorized(self) -> bool:
        api_key = self.server.args.api_key
        if not api_key:
            return True
        expected = f"Bearer {api_key}"
        return self.headers.get("Authorization", "") == expected

    def read_multipart(self) -> tuple[dict[str, str], bytes, str]:
        content_type = self.headers.get("Content-Type", "")
        content_length = int(self.headers.get("Content-Length", "0"))
        if "multipart/form-data" not in content_type:
            raise ValueError("Expected multipart/form-data")

        body = self.rfile.read(content_length)
        message = BytesParser(policy=default).parsebytes(
            f"Content-Type: {content_type}\r\nMIME-Version: 1.0\r\n\r\n".encode("utf-8") + body
        )

        fields: dict[str, str] = {}
        file_bytes: bytes | None = None
        filename = "audio.wav"

        for part in message.iter_parts():
            if part.get_content_disposition() != "form-data":
                continue
            name = part.get_param("name", header="content-disposition")
            if not name:
                continue

            data = part.get_payload(decode=True) or b""
            part_filename = part.get_filename()
            if part_filename or name == "file":
                file_bytes = data
                filename = part_filename or filename
            else:
                charset = part.get_content_charset() or "utf-8"
                fields[name] = data.decode(charset, errors="replace")

        if not file_bytes:
            raise ValueError("No uploaded audio file")

        return fields, file_bytes, filename

    def send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_text(self, text: str, status: HTTPStatus = HTTPStatus.OK) -> None:
        data = text.encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def result_to_dict(result: Any) -> dict[str, Any]:
    if is_dataclass(result):
        return asdict(result)
    if isinstance(result, dict):
        return result
    return {"text": str(result)}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the SimulTrans Qwen3 ASR sidecar.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--model", default="Qwen/Qwen3-ASR-1.7B")
    parser.add_argument("--dtype", default="float16", choices=("float16", "float32", "bfloat16"))
    parser.add_argument("--parent-pid", type=int, default=0)
    parser.add_argument("--api-key", default="simultrans-local")
    return parser.parse_args()


def is_process_alive(pid: int) -> bool:
    if pid <= 0:
        return True
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def main() -> int:
    args = parse_args()
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

    server = QwenASRServer((args.host, args.port), Handler, args)
    server.timeout = 1.0
    print(f"[qwen-sidecar] listening on http://{args.host}:{args.port}", flush=True)
    try:
        while is_process_alive(args.parent_pid):
            server.handle_request()
        print(f"[qwen-sidecar] parent process {args.parent_pid} exited", flush=True)
    except KeyboardInterrupt:
        print("[qwen-sidecar] stopping", flush=True)
    finally:
        server.server_close()
        time.sleep(0.05)
    return 0


if __name__ == "__main__":
    sys.exit(main())
