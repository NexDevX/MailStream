#!/usr/bin/env python3
"""Read-only QQ Mail IMAP probe.

Use this to verify whether a QQ mailbox authorization code can see historical
messages through the official IMAP service. By default it fetches only headers
and counts, not message bodies.
"""

from __future__ import annotations

import argparse
import base64
import getpass
import imaplib
import json
import os
import re
import sys
from datetime import datetime
from email import policy
from email.parser import BytesParser
from pathlib import Path
from typing import Any


QQ_IMAP_HOST = "imap.qq.com"
QQ_IMAP_PORT = 993


def decode_imap_utf7(value: bytes) -> str:
    text = value.decode("ascii", errors="replace")
    parts: list[str] = []
    index = 0
    while index < len(text):
        amp = text.find("&", index)
        if amp < 0:
            parts.append(text[index:])
            break
        parts.append(text[index:amp])
        dash = text.find("-", amp)
        if dash < 0:
            parts.append(text[amp:])
            break
        token = text[amp + 1 : dash]
        if token == "":
            parts.append("&")
        else:
            padding = "=" * (-len(token) % 4)
            raw = base64.b64decode((token.replace(",", "/") + padding).encode("ascii"))
            parts.append(raw.decode("utf-16-be", errors="replace"))
        index = dash + 1
    return "".join(parts)


def encode_imap_utf7(value: str) -> bytes:
    output = bytearray()
    buffer: list[str] = []

    def flush_buffer() -> None:
        if not buffer:
            return
        raw = "".join(buffer).encode("utf-16-be")
        token = base64.b64encode(raw).decode("ascii").rstrip("=").replace("/", ",")
        output.extend(f"&{token}-".encode("ascii"))
        buffer.clear()

    for char in value:
        code = ord(char)
        if 0x20 <= code <= 0x7E:
            flush_buffer()
            if char == "&":
                output.extend(b"&-")
            else:
                output.extend(char.encode("ascii"))
        else:
            buffer.append(char)
    flush_buffer()
    return bytes(output)


def parse_list_item(item: bytes) -> dict[str, Any]:
    flag_match = re.match(rb"\(([^)]*)\)", item)
    flags = flag_match.group(1).split() if flag_match else []
    matches = re.findall(rb'(?:"((?:[^"\\]|\\.)*)"|([^"\s]+))', item)
    atoms = [quoted or bare for quoted, bare in matches]
    raw_name = atoms[-1] if atoms else item.rsplit(maxsplit=1)[-1]
    return {
        "raw": raw_name.decode("ascii", errors="replace"),
        "name": decode_imap_utf7(raw_name),
        "flags": [flag.decode("ascii", errors="replace") for flag in flags],
    }


def parse_since(value: str | None) -> str:
    if not value:
        return "ALL"
    try:
        parsed = datetime.strptime(value, "%Y-%m-%d")
    except ValueError as exc:
        raise SystemExit("--since must use YYYY-MM-DD, for example 2020-01-01") from exc
    return f'SINCE {parsed.strftime("%d-%b-%Y")}'


def connect(email_address: str, auth_code: str) -> imaplib.IMAP4_SSL:
    client = imaplib.IMAP4_SSL(QQ_IMAP_HOST, QQ_IMAP_PORT)
    client.login(email_address, auth_code)
    return client


def quote_imap_arg(value: str) -> bytes:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'.encode("ascii")


def list_folders(client: imaplib.IMAP4_SSL) -> list[dict[str, Any]]:
    status, data = client.list()
    if status != "OK":
        raise RuntimeError(f"LIST failed: {data!r}")
    return [parse_list_item(item) for item in data if item]


def select_folder(client: imaplib.IMAP4_SSL, raw_folder: bytes) -> int:
    status, data = client.select(raw_folder, readonly=True)
    if status != "OK":
        raise RuntimeError(f"SELECT failed for {raw_folder!r}: {data!r}")
    return int(data[0] or 0)


def search_uids(client: imaplib.IMAP4_SSL, criterion: str) -> list[bytes]:
    status, data = client.uid("SEARCH", None, *criterion.split())
    if status != "OK":
        raise RuntimeError(f"UID SEARCH failed: {data!r}")
    return data[0].split() if data and data[0] else []


def header_value(headers: Any, name: str) -> str | None:
    value = headers.get(name)
    return str(value) if value is not None else None


def fetch_message_summary(
    client: imaplib.IMAP4_SSL,
    uid: bytes,
    include_body: bool,
    body_bytes: int,
) -> dict[str, Any]:
    fetch_parts = [
        "RFC822.SIZE",
        "INTERNALDATE",
        "BODY.PEEK[HEADER.FIELDS (DATE FROM TO CC SUBJECT MESSAGE-ID)]",
    ]
    if include_body:
        fetch_parts.append(f"BODY.PEEK[TEXT]<0.{body_bytes}>")

    status, data = client.uid("FETCH", uid, f"({' '.join(fetch_parts)})")
    if status != "OK":
        raise RuntimeError(f"UID FETCH failed for {uid!r}: {data!r}")

    headers = None
    body_preview = None
    size = None
    internal_date = None

    for part in data:
        if not isinstance(part, tuple):
            continue
        meta, payload = part
        meta_text = meta.decode("ascii", errors="replace")
        size_match = re.search(r"RFC822\.SIZE\s+(\d+)", meta_text)
        date_match = re.search(r'INTERNALDATE\s+"([^"]+)"', meta_text)
        if size_match:
            size = int(size_match.group(1))
        if date_match:
            internal_date = date_match.group(1)
        if b"HEADER.FIELDS" in meta:
            headers = BytesParser(policy=policy.default).parsebytes(payload)
        elif include_body:
            body_preview = payload.decode("utf-8", errors="replace")

    result: dict[str, Any] = {
        "uid": uid.decode("ascii", errors="replace"),
        "size": size,
        "internal_date": internal_date,
    }
    if headers is not None:
        result.update(
            {
                "date": header_value(headers, "date"),
                "from": header_value(headers, "from"),
                "to": header_value(headers, "to"),
                "cc": header_value(headers, "cc"),
                "subject": header_value(headers, "subject"),
                "message_id": header_value(headers, "message-id"),
            }
        )
    if include_body:
        result["body_preview"] = body_preview
    return result


def inspect_folder(
    client: imaplib.IMAP4_SSL,
    folder: dict[str, Any],
    since: str,
    limit: int,
    include_body: bool,
    body_bytes: int,
) -> dict[str, Any]:
    total = select_folder(client, quote_imap_arg(folder["raw"]))
    uids = search_uids(client, since)
    sample_uids = uids[-limit:] if limit > 0 else []
    messages = [
        fetch_message_summary(client, uid, include_body, body_bytes)
        for uid in reversed(sample_uids)
    ]
    return {
        "folder": folder["name"],
        "raw_folder": folder["raw"],
        "total_messages": total,
        "matched_messages": len(uids),
        "sampled_messages": messages,
    }


def inspect_folder_safely(
    client: imaplib.IMAP4_SSL,
    folder: dict[str, Any],
    since: str,
    limit: int,
    include_body: bool,
    body_bytes: int,
) -> dict[str, Any]:
    try:
        return inspect_folder(client, folder, since, limit, include_body, body_bytes)
    except Exception as exc:
        return {
            "folder": folder["name"],
            "raw_folder": folder["raw"],
            "inspect_error": str(exc),
        }


def write_or_print(payload: dict[str, Any], output: Path | None) -> None:
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    if output:
        output.write_text(text + "\n", encoding="utf-8")
        print(f"Wrote {output}")
    else:
        print(text)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Probe QQ Mail historical mail visibility through read-only IMAP."
    )
    parser.add_argument("--email", default=os.getenv("QQMAIL_EMAIL"), help="QQ email address")
    parser.add_argument(
        "--auth-code",
        default=os.getenv("QQMAIL_AUTH_CODE"),
        help="QQ Mail authorization code; omit to prompt securely",
    )
    parser.add_argument("--folder", default="INBOX", help="Folder name to inspect")
    parser.add_argument("--all-folders", action="store_true", help="Inspect every selectable folder")
    parser.add_argument("--since", help="Only count/sample messages since YYYY-MM-DD")
    parser.add_argument("--limit", type=int, default=10, help="Header samples per folder")
    parser.add_argument("--include-body", action="store_true", help="Also fetch a small body preview")
    parser.add_argument("--body-bytes", type=int, default=2048, help="Body preview byte limit")
    parser.add_argument("--output", type=Path, help="Write JSON result to this file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.email:
        raise SystemExit("Provide --email or set QQMAIL_EMAIL")
    auth_code = args.auth_code or getpass.getpass("QQ Mail authorization code: ")
    criterion = parse_since(args.since)

    client = connect(args.email, auth_code)
    try:
        folders = list_folders(client)
        selectable = [
            folder
            for folder in folders
            if all(flag.lower() != "\\noselect" for flag in folder["flags"])
        ]
        if args.all_folders:
            targets = selectable
        else:
            raw_target = encode_imap_utf7(args.folder).decode("ascii")
            targets = [
                folder
                for folder in selectable
                if folder["raw"].upper() == raw_target.upper() or folder["name"] == args.folder
            ]
            if not targets:
                known = ", ".join(folder["name"] for folder in selectable)
                raise SystemExit(f"Folder not found: {args.folder}. Known folders: {known}")

        inspected = [
                inspect_folder_safely(
                client,
                folder,
                criterion,
                args.limit,
                args.include_body,
                args.body_bytes,
            )
            for folder in targets
        ]
        payload = {
            "account": args.email,
            "server": f"{QQ_IMAP_HOST}:{QQ_IMAP_PORT}",
            "mode": "read_only_imap",
            "search": criterion,
            "folders": folders,
            "inspected": inspected,
        }
        write_or_print(payload, args.output)
        return 0
    finally:
        try:
            client.logout()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
