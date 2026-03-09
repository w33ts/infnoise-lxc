#!/usr/bin/env python3

import json
import os
import re
import signal
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


HEALTH_LINE_RE = re.compile(r"Estimated entropy per bit:\s*([0-9.]+),\s*estimated K:\s*([0-9.]+)")
ONES_LINE_RE = re.compile(r"num1s:([0-9.]+)%,\s*even misfires:([0-9.]+)%,\s*odd misfires:([0-9.]+)%")


def getenv_int(name: str, fallback: int) -> int:
    value = os.getenv(name)
    if not value:
        return fallback
    try:
        return int(value)
    except ValueError:
        return fallback


def read_entropy(binary: str, byte_count: int) -> bytes:
    process = subprocess.Popen([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        if process.stdout is None:
            raise RuntimeError("infnoise stdout pipe is unavailable")
        output = process.stdout.read(byte_count)
        if len(output) != byte_count:
            raise RuntimeError(f"expected {byte_count} bytes but received {len(output)}")
        return output
    finally:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()


def read_health(binary: str, timeout_seconds: int) -> dict | None:
    try:
        subprocess.run(
            [binary, "--debug", "--no-output"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout_seconds,
            check=False,
            text=True,
        )
        return None
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout.decode("utf-8", errors="replace") if isinstance(exc.stdout, bytes) else exc.stdout or ""
        lines = [line.strip() for line in output.splitlines() if line.strip()]
        entropy_line = next((line for line in reversed(lines) if "Estimated entropy per bit" in line), None)
        ones_line = next((line for line in reversed(lines) if line.startswith("num1s:")), None)
        if not entropy_line:
            return None
        entropy_match = HEALTH_LINE_RE.search(entropy_line)
        if not entropy_match:
            return None

        result = {
            "entropyPerBit": float(entropy_match.group(1)),
            "estimatedK": float(entropy_match.group(2)),
        }

        if ones_line:
            ones_match = ONES_LINE_RE.search(ones_line)
            if ones_match:
                result["numOnesPct"] = float(ones_match.group(1))
                result["evenMisfiresPct"] = float(ones_match.group(2))
                result["oddMisfiresPct"] = float(ones_match.group(3))

        return result


def post_refill(url: str, token: str, payload: dict) -> int:
    body = json.dumps(payload).encode("utf-8")
    request = Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
            "X-Ingest-Token": token,
            "User-Agent": "infnoise-trng-push/1.0",
        },
    )
    with urlopen(request, timeout=15) as response:
        print(response.read().decode("utf-8"))
        return response.status


def main() -> int:
    ingest_url = os.getenv("TRNG_INGEST_URL")
    ingest_token = os.getenv("TRNG_INGEST_TOKEN")
    source = os.getenv("TRNG_SOURCE", "proxmox-infnoise")
    batch_bytes = getenv_int("TRNG_BATCH_BYTES", 8192)
    health_timeout = getenv_int("INFNOISE_HEALTH_TIMEOUT_SECONDS", 3)
    binary = os.getenv("INFNOISE_BINARY", "/usr/local/bin/infnoise")

    if not ingest_url or not ingest_token:
        print("TRNG_INGEST_URL and TRNG_INGEST_TOKEN are required", file=sys.stderr)
        return 1

    try:
        entropy = read_entropy(binary, batch_bytes)
        health = read_health(binary, health_timeout)
        payload = {
            "entropyHex": entropy.hex(),
            "byteCount": len(entropy),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "source": source,
            "health": health,
        }
        status = post_refill(ingest_url, ingest_token, payload)
        print(f"Pushed {len(entropy)} bytes from {source} (status={status})")
        return 0
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        print(f"HTTP error {exc.code}: {body}", file=sys.stderr)
    except (URLError, TimeoutError) as exc:
        print(f"Network error: {exc}", file=sys.stderr)
    except Exception as exc:
        print(f"Unexpected error: {exc}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
