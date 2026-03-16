#!/usr/bin/env python3
import base64
import os
import sys


def strip_outer_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1].strip()
    return value


def raw_payload() -> str:
    return strip_outer_quotes(os.environ["SINGLE_NODE_VPS_SSH_PRIVATE_KEY"].replace("\r", "").strip())


def normalize() -> str:
    raw = raw_payload()
    candidates = [raw]

    if "\\n" in raw:
        candidates.append(strip_outer_quotes(raw.replace("\\n", "\n").strip()))

    try:
        decoded = base64.b64decode(raw, validate=True).decode("utf-8").replace("\r", "").strip()
    except Exception:
        decoded = ""

    if decoded:
        candidates.append(strip_outer_quotes(decoded))

    for candidate in candidates:
        if "BEGIN " in candidate and "PRIVATE KEY" in candidate:
            return candidate.rstrip("\n") + "\n"

    return raw.rstrip("\n") + "\n"


def hint() -> str:
    raw = os.environ["SINGLE_NODE_VPS_SSH_PRIVATE_KEY"].replace("\r", "").strip()
    trimmed = raw.strip("'\"").strip()

    if trimmed.startswith("ssh-rsa ") or trimmed.startswith("ssh-ed25519 ") or trimmed.startswith("ecdsa-sha2-"):
        return "looks like a public key, not a private key"
    if trimmed.startswith("~/.ssh/") or trimmed.startswith("/") or trimmed.endswith(".pem") or trimmed.endswith("id_rsa"):
        return "looks like a filesystem path, not file contents"
    if "BEGIN " in trimmed and "PRIVATE KEY" in trimmed:
        return "contains private-key markers but failed ssh-keygen validation"
    if "\\n" in raw:
        return "contains escaped newlines but did not normalize to a valid private key"
    return "does not look like a supported private key payload"


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in {"normalize", "hint"}:
        raise SystemExit("usage: private-key-payload.py <normalize|hint>")

    if sys.argv[1] == "normalize":
        sys.stdout.write(normalize())
        return

    print(hint())


if __name__ == "__main__":
    main()
