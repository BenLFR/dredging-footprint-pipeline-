#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import importlib.util
import json
import os
import re
import shutil
import site
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlencode

from learning_registry import (
    ROOT,
    git_head,
    load_ingest_log,
    load_registry_state,
    make_resource_id,
    normalize_list,
    now_iso,
    resolve_local_path,
    save_ingest_log,
    save_ingest_markdown,
    source_hash_for,
    upsert_ingest_record,
)
from learning_notes import save_learning_note

SECRET_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in [
        r"sk-[A-Za-z0-9]{10,}",
        r"AIza[0-9A-Za-z\-_]{20,}",
        r"OPENAI_API_KEY",
        r"api[_-]?key",
        r"password",
        r"secret",
        r"token",
    ]
]

TRANSIENT_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in [
        r"traceback",
        r"stack trace",
        r"debug session",
        r"one-off",
        r"exception",
    ]
]

DOI_RE = re.compile(r"\b10\.\d{4,9}/[-._;()/:A-Z0-9]+\b", re.IGNORECASE)
URL_RE = re.compile(r"https?://\S+", re.IGNORECASE)
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\([^)]+\)")
FILE_REF_RE = re.compile(r"`[^`]+\.(?:md|pdf|docx?|txt|json|ya?ml|csv|parquet|r|py|m)`", re.IGNORECASE)
NBLM_REF_RE = re.compile(r"nblm://\S+", re.IGNORECASE)
REFERENCE_HEADING_RE = re.compile(r"(?im)^(?:#+\s+)?(?:sources?|references|linked sources)\s*$")
BULLET_RE = re.compile(r"^\s*[-*+]\s+")

MODE_PROMPTS = {
    "simple": "Answer in plain language for a scientific user with limited coding background.",
    "technical": "Answer technically and precisely, but stay grounded in the imported sources.",
    "project": "Answer with project-specific relevance for the AIS dredging pipeline and manuscript.",
}

VENV_SITE_PACKAGES = ROOT / ".venv-notebooklm" / "Lib" / "site-packages"
LOCAL_ONLY_TARGET = "local-derived-note"
DEFAULT_OBSIDIAN_METHOD = os.environ.get("OBSIDIAN_METHOD", "auto")
DEFAULT_OBSIDIAN_VAULT = os.environ.get("OBSIDIAN_VAULT")
DEFAULT_OBSIDIAN_VAULT_ROOT = os.environ.get("OBSIDIAN_VAULT_ROOT")
DEFAULT_OBSIDIAN_BIN = os.environ.get("OBSIDIAN_BIN", "obsidian")


def ensure_local_notebooklm_on_path() -> None:
    if importlib.util.find_spec("notebooklm") is not None:
        return
    if VENV_SITE_PACKAGES.exists():
        site.addsitedir(str(VENV_SITE_PACKAGES))


class NotebookLMConnector:
    def __init__(self, storage_path: str | None = None) -> None:
        self.storage_path = storage_path

    @property
    def available(self) -> bool:
        ensure_local_notebooklm_on_path()
        return importlib.util.find_spec("notebooklm") is not None

    async def _client(self):
        ensure_local_notebooklm_on_path()
        from notebooklm import NotebookLMClient

        if self.storage_path:
            return await NotebookLMClient.from_storage(self.storage_path)
        return await NotebookLMClient.from_storage()

    async def _resolve_notebook(self, client, label: str):
        notebooks = await client.notebooks.list()
        for notebook in notebooks:
            if getattr(notebook, "id", None) == label or getattr(notebook, "title", None) == label:
                return notebook
        return await client.notebooks.create(label)

    async def ingest(
        self,
        *,
        target_notebook: str,
        source_path: str | None = None,
        source_url: str | None = None,
        wait: bool = False,
        wait_timeout: float = 120.0,
    ) -> dict[str, Any]:
        async with await self._client() as client:
            notebook = await self._resolve_notebook(client, target_notebook)
            if source_url:
                source = await client.sources.add_url(
                    notebook.id,
                    source_url,
                    wait=wait,
                    wait_timeout=wait_timeout,
                )
            else:
                local_path = resolve_local_path(source_path)
                if local_path is None or not local_path.exists():
                    raise FileNotFoundError(f"Local source not found: {source_path}")
                source = await client.sources.add_file(
                    notebook.id,
                    local_path,
                    wait=wait,
                    wait_timeout=wait_timeout,
                )
            return {
                "notebook_id": getattr(notebook, "id", None),
                "notebook_title": getattr(notebook, "title", target_notebook),
                "source_id": getattr(source, "id", None),
                "source_title": getattr(source, "title", None),
                "source_status": getattr(source, "status", None),
            }

    async def query(self, *, target_notebook: str, question: str, source_ids: list[str] | None = None):
        async with await self._client() as client:
            notebook = await self._resolve_notebook(client, target_notebook)
            result = await client.chat.ask(notebook.id, question, source_ids=source_ids or None)
            source_map = {}
            for source in await client.sources.list(notebook.id):
                source_map[getattr(source, "id", "")] = getattr(source, "title", getattr(source, "id", ""))
            references = []
            for ref in getattr(result, "references", []) or []:
                source_id = getattr(ref, "source_id", None)
                references.append(
                    {
                        "citation_number": getattr(ref, "citation_number", None),
                        "source_id": source_id,
                        "source_title": source_map.get(source_id),
                    }
                )
            return {
                "notebook_id": getattr(notebook, "id", None),
                "notebook_title": getattr(notebook, "title", target_notebook),
                "answer": getattr(result, "answer", ""),
                "conversation_id": getattr(result, "conversation_id", None),
                "references": references,
            }

    async def wait_for_sources(
        self,
        *,
        target_notebook: str,
        source_ids: list[str],
        timeout: float = 120.0,
    ) -> list[dict[str, Any]]:
        async with await self._client() as client:
            notebook = await self._resolve_notebook(client, target_notebook)
            ready_sources = await client.sources.wait_for_sources(
                notebook.id,
                source_ids,
                timeout=timeout,
            )
            return [
                {
                    "source_id": source.id,
                    "title": source.title,
                    "status": source.status,
                    "notebook_id": notebook.id,
                    "notebook_title": getattr(notebook, "title", target_notebook),
                }
                for source in ready_sources
            ]

    async def healthcheck(self) -> dict[str, Any]:
        async with await self._client() as client:
            notebooks = await client.notebooks.list()
            return {"ok": True, "notebook_count": len(notebooks)}


def parse_multi(values: list[str] | None) -> list[str]:
    parts: list[str] = []
    for value in values or []:
        parts.extend(chunk.strip() for chunk in value.split(","))
    return normalize_list(parts)


def ensure_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value if str(item).strip()]
    text = str(value).strip()
    return [text] if text else []


def print_json(payload: Any) -> None:
    print(json.dumps(payload, indent=2, ensure_ascii=False))


def add_obsidian_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--open-in-obsidian",
        action="store_true",
        help="Open the saved or promoted note in Obsidian after success",
    )
    parser.add_argument(
        "--obsidian-method",
        choices=["auto", "uri", "cli"],
        default=DEFAULT_OBSIDIAN_METHOD,
        help="How to open Obsidian; auto tries the URI scheme first, then the CLI",
    )
    parser.add_argument(
        "--obsidian-vault",
        default=DEFAULT_OBSIDIAN_VAULT,
        help="Optional Obsidian vault name for vault-relative URI or CLI opens",
    )
    parser.add_argument(
        "--obsidian-vault-root",
        default=DEFAULT_OBSIDIAN_VAULT_ROOT,
        help="Optional vault root path used to derive a vault-relative note path",
    )
    parser.add_argument(
        "--obsidian-bin",
        default=DEFAULT_OBSIDIAN_BIN,
        help="Obsidian CLI executable or absolute path when using --obsidian-method cli",
    )


def resolve_note_path(path_value: str | Path) -> Path:
    path = resolve_local_path(str(path_value))
    if path is None or not path.exists():
        raise FileNotFoundError(f"Note not found: {path_value}")
    return path.resolve()


def resolve_obsidian_relative_path(note_path: Path, vault_root: str | None) -> str:
    candidate_roots: list[Path] = []
    if vault_root:
        candidate_roots.append(Path(vault_root).expanduser().resolve())
    candidate_roots.append(ROOT.resolve())

    for base in candidate_roots:
        try:
            return note_path.relative_to(base).as_posix()
        except ValueError:
            continue
    raise ValueError(
        "Cannot derive an Obsidian vault-relative path for CLI open. "
        "Pass --obsidian-vault-root to point at the vault root."
    )


def build_obsidian_open_uri(note_path: Path, *, vault: str | None, vault_root: str | None) -> str:
    if vault and vault_root:
        relative_path = resolve_obsidian_relative_path(note_path, vault_root)
        query = urlencode(
            {"vault": vault, "file": relative_path},
            quote_via=quote,
            safe="/",
        )
    else:
        query = urlencode(
            {"path": note_path.as_posix()},
            quote_via=quote,
            safe="/:",
        )
    return f"obsidian://open?{query}"


def launch_obsidian_uri(uri: str) -> None:
    if os.name == "nt":
        os.startfile(uri)  # type: ignore[attr-defined]
        return
    if sys.platform == "darwin":
        subprocess.run(["open", uri], check=True)
        return
    subprocess.run(["xdg-open", uri], check=True)


def resolve_obsidian_cli(note_path: Path, *, obsidian_bin: str, vault: str | None, vault_root: str | None) -> list[str]:
    binary_path = Path(obsidian_bin)
    if not binary_path.exists() and shutil.which(obsidian_bin) is None:
        raise FileNotFoundError(f"Obsidian CLI not found: {obsidian_bin}")
    relative_path = resolve_obsidian_relative_path(note_path, vault_root)
    command = [obsidian_bin]
    if vault:
        command.append(f"vault={vault}")
    command.extend(["open", f"path={relative_path}"])
    return command


def open_note_in_obsidian(path_value: str | Path, args: argparse.Namespace) -> dict[str, Any]:
    note_path = resolve_note_path(path_value)
    method = getattr(args, "obsidian_method", "auto")
    vault = getattr(args, "obsidian_vault", None)
    vault_root = getattr(args, "obsidian_vault_root", None)
    obsidian_bin = getattr(args, "obsidian_bin", DEFAULT_OBSIDIAN_BIN)
    uri_error: Exception | None = None

    if method in {"auto", "uri"}:
        try:
            uri = build_obsidian_open_uri(note_path, vault=vault, vault_root=vault_root)
            launch_obsidian_uri(uri)
            return {"method": "uri", "uri": uri, "note_path": str(note_path)}
        except Exception as exc:
            if method == "uri":
                raise RuntimeError(f"Failed to open note in Obsidian via URI: {exc}") from exc
            uri_error = exc

    try:
        command = resolve_obsidian_cli(
            note_path,
            obsidian_bin=obsidian_bin,
            vault=vault,
            vault_root=vault_root,
        )
        subprocess.run(command, check=True)
        return {"method": "cli", "command": command, "note_path": str(note_path)}
    except Exception as exc:
        if uri_error is not None:
            raise RuntimeError(
                "Failed to open note in Obsidian via URI and CLI: "
                f"{uri_error}; {exc}"
            ) from exc
        raise RuntimeError(f"Failed to open note in Obsidian via CLI: {exc}") from exc


def structured_reference_count(text: str) -> int:
    count = 0
    count += len(DOI_RE.findall(text))
    count += len(URL_RE.findall(text))
    count += len(MARKDOWN_LINK_RE.findall(text))
    count += len(FILE_REF_RE.findall(text))
    count += len(NBLM_REF_RE.findall(text))

    lines = text.splitlines()
    for index, line in enumerate(lines):
        if not REFERENCE_HEADING_RE.match(line.strip()):
            continue
        for candidate in lines[index + 1 : index + 21]:
            stripped = candidate.strip()
            if not stripped:
                continue
            if stripped.startswith("#"):
                break
            if BULLET_RE.match(candidate) and (
                DOI_RE.search(candidate)
                or URL_RE.search(candidate)
                or MARKDOWN_LINK_RE.search(candidate)
                or FILE_REF_RE.search(candidate)
                or NBLM_REF_RE.search(candidate)
            ):
                count += 1
    return count


def save_note(
    path_value: str,
    title: str,
    body: str,
    references: list[dict[str, Any]],
    *,
    notebook: str,
    mode: str,
    question: str,
    registers: list[str] | None = None,
    concepts: list[str] | None = None,
    topic: str | None = None,
) -> Path:
    path, _metadata = save_learning_note(
        title=title,
        body=body.strip(),
        references=references,
        notebook=notebook,
        mode=mode,
        question=question,
        registers=registers or [],
        concepts=concepts or [],
        explicit_topic=topic,
        preferred_path=path_value,
    )
    return path


def build_record(args: argparse.Namespace, operation: str, status: str, *, notes: str | None = None) -> dict[str, Any]:
    created_at = getattr(args, "created_at", None) or now_iso()
    source_path = args.path if hasattr(args, "path") else None
    source_url = args.url if hasattr(args, "url") else None
    source_hash = source_hash_for(source_path=source_path, source_url=source_url)
    title = args.title or (Path(source_path).name if source_path else source_url or operation)
    resource_id = args.resource_id or make_resource_id(title, source_hash, created_at, operation)
    source_version = git_head() if source_path else None
    return {
        "resource_id": resource_id,
        "title": title,
        "status": status,
        "operation": operation,
        "type": args.type,
        "source_path": [source_path] if source_path else [],
        "source_url": [source_url] if source_url else [],
        "target_notebook": [args.notebook],
        "registers": parse_multi(getattr(args, "register", None)),
        "concepts": parse_multi(getattr(args, "concept", None)),
        "created_at": created_at,
        "last_synced_at": None,
        "sync_attempts": 0,
        "source_hash": source_hash,
        "source_version": source_version,
        "notebooklm_source_id": None,
        "notebooklm_notebook_id": None,
        "promotion_candidate": getattr(args, "promotion_candidate", "unknown"),
        "notes": notes,
        "why_it_matters": getattr(args, "why", None) or "",
        "local_actions": [],
        "notebooklm_actions": [],
        "last_error": None,
        "sync_results": [],
    }
def build_derived_note_record(args: argparse.Namespace, note_path: Path, result: dict[str, Any]) -> dict[str, Any]:
    created_at = now_iso()
    title = args.derived_title or note_path.stem.replace("_", " ").strip() or "Derived note"
    source_hash = source_hash_for(source_path=str(note_path))
    resource_id = make_resource_id(title, source_hash, created_at, "derive-note")
    return {
        "resource_id": resource_id,
        "title": title,
        "status": "INDEXED",
        "operation": "derive_note",
        "type": args.derived_type,
        "source_path": [str(note_path.relative_to(ROOT)) if note_path.is_absolute() else str(note_path)],
        "source_url": [],
        "target_notebook": [args.derived_notebook],
        "registers": parse_multi(getattr(args, "register", None)),
        "concepts": parse_multi(getattr(args, "concept", None)),
        "created_at": created_at,
        "last_synced_at": None,
        "sync_attempts": 0,
        "source_hash": source_hash,
        "source_version": git_head(),
        "notebooklm_source_id": None,
        "notebooklm_notebook_id": None,
        "promotion_candidate": getattr(args, "promotion_candidate", "medium"),
        "notes": f"Derived from NotebookLM query conversation {result.get('conversation_id')}",
        "why_it_matters": getattr(args, "why", None) or "Derived teaching note from NotebookLM query.",
        "local_actions": ["Review note and decide whether to promote to Core Curriculum."],
        "notebooklm_actions": ["Optional promotion later via the promote command."],
        "last_error": None,
        "sync_results": [],
    }


def merge_sync_results(existing: list[dict[str, Any]] | None, incoming: list[dict[str, Any]] | None) -> list[dict[str, Any]]:
    seen: set[tuple[str | None, str | None, str | None, str | None]] = set()
    merged: list[dict[str, Any]] = []
    for item in (existing or []) + (incoming or []):
        key = (
            item.get("notebook_id"),
            item.get("source_id"),
            item.get("requested_path"),
            item.get("requested_url"),
        )
        if key in seen:
            continue
        seen.add(key)
        merged.append(item)
    return merged


def store_record(rows: list[dict[str, Any]], record: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    for existing in rows:
        if existing.get("resource_id") == record.get("resource_id"):
            record["sync_results"] = merge_sync_results(existing.get("sync_results"), record.get("sync_results"))
            break
    return upsert_ingest_record(rows, record)


def update_record_after_sync(
    record: dict[str, Any],
    *,
    status: str,
    sync_time: str | None,
    source_id: str | None = None,
    notebook_id: str | None = None,
    notes: str | None = None,
    error: str | None = None,
    sync_results: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    updated = dict(record)
    updated["status"] = status
    updated["sync_attempts"] = int(updated.get("sync_attempts") or 0) + 1
    updated["last_synced_at"] = sync_time
    if source_id:
        updated["notebooklm_source_id"] = source_id
    if notebook_id:
        updated["notebooklm_notebook_id"] = notebook_id
    if notes:
        updated["notes"] = notes
    updated["last_error"] = error
    if sync_results is not None:
        updated["sync_results"] = merge_sync_results(updated.get("sync_results"), sync_results)
    return updated


def evaluate_promotion(path_value: str) -> dict[str, bool]:
    path = resolve_local_path(path_value)
    if path is None or not path.exists():
        raise FileNotFoundError(f"Teaching note not found: {path_value}")
    text = path.read_text(encoding="utf-8-sig")
    checks = {
        "grounded_in_sources": structured_reference_count(text) >= 1,
        "no_secrets": not any(pattern.search(text) for pattern in SECRET_PATTERNS),
        "not_transient_debug": not any(pattern.search(text) for pattern in TRANSIENT_PATTERNS),
        "valid_beyond_session": len(text.strip()) >= 200,
        "standalone": text.lstrip().startswith("# ") and len(re.findall(r"(?m)^#", text)) >= 1,
    }
    return checks


def promotion_failed_reason(checks: dict[str, bool]) -> str:
    failed = [name for name, passed in checks.items() if not passed]
    return "Promotion checklist failed: " + ", ".join(failed)


def sync_specs_from_record(record: dict[str, Any]) -> list[dict[str, str | None]]:
    specs: list[dict[str, str | None]] = []
    for path_value in ensure_list(record.get("source_path")):
        specs.append({"source_path": path_value, "source_url": None})
    for url_value in ensure_list(record.get("source_url")):
        specs.append({"source_path": None, "source_url": url_value})
    return specs


def notebook_targets_from_record(record: dict[str, Any]) -> list[str]:
    return ensure_list(record.get("target_notebook"))


def sync_record_batch(
    connector: NotebookLMConnector,
    record: dict[str, Any],
    *,
    wait: bool,
    wait_timeout: float,
) -> tuple[list[dict[str, Any]], list[str]]:
    sync_results: list[dict[str, Any]] = []
    errors: list[str] = []
    targets = notebook_targets_from_record(record)
    specs = sync_specs_from_record(record)

    if not targets:
        return [], ["No target notebooks configured for record"]
    if not specs:
        return [], ["No source paths or URLs configured for record"]

    for target in targets:
        for spec in specs:
            try:
                result = asyncio.run(
                    connector.ingest(
                        target_notebook=target,
                        source_path=spec.get("source_path"),
                        source_url=spec.get("source_url"),
                        wait=wait,
                        wait_timeout=wait_timeout,
                    )
                )
                sync_results.append(
                    {
                        **result,
                        "requested_notebook": target,
                        "requested_path": spec.get("source_path"),
                        "requested_url": spec.get("source_url"),
                    }
                )
            except Exception as exc:
                errors.append(f"{target} :: {spec.get('source_path') or spec.get('source_url')}: {exc}")
    return sync_results, errors


def collect_source_ids(record: dict[str, Any]) -> list[str]:
    source_ids: list[str] = []
    direct = record.get("notebooklm_source_id")
    if direct:
        source_ids.append(str(direct))
    for item in record.get("sync_results") or []:
        source_id = item.get("source_id")
        if source_id and str(source_id) not in source_ids:
            source_ids.append(str(source_id))
    return source_ids


def collect_notebook_ids(record: dict[str, Any]) -> list[str]:
    notebook_ids: list[str] = []
    direct = record.get("notebooklm_notebook_id")
    if direct:
        notebook_ids.append(str(direct))
    for item in record.get("sync_results") or []:
        notebook_id = item.get("notebook_id")
        if notebook_id and str(notebook_id) not in notebook_ids:
            notebook_ids.append(str(notebook_id))
    return notebook_ids


def run_healthcheck(connector: NotebookLMConnector) -> dict[str, Any]:
    if not connector.available:
        return {"ok": False, "error": "notebooklm package not installed"}
    try:
        return asyncio.run(connector.healthcheck())
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
def cmd_ingest(args: argparse.Namespace) -> int:
    records = load_ingest_log()
    record = build_record(args, "ingest", "INDEXED", notes="Dry run only" if args.dry_run else None)
    connector = NotebookLMConnector(storage_path=args.storage)

    if args.dry_run:
        records, saved = store_record(records, record)
        save_ingest_log(records)
        save_ingest_markdown(records)
        print_json({"status": saved["status"], "resource_id": saved["resource_id"], "dry_run": True})
        return 0

    if not connector.available:
        updated = update_record_after_sync(record, status="SYNC_PENDING", sync_time=None, error="notebooklm package not installed")
        records, saved = store_record(records, updated)
        save_ingest_log(records)
        save_ingest_markdown(records)
        print_json({"status": saved["status"], "resource_id": saved["resource_id"], "reason": saved["last_error"]})
        return 0

    sync_results, errors = sync_record_batch(connector, record, wait=args.wait, wait_timeout=args.wait_timeout)
    if errors:
        updated = update_record_after_sync(
            record,
            status="FAILED",
            sync_time=now_iso() if sync_results else None,
            error="; ".join(errors),
            sync_results=sync_results,
            source_id=sync_results[0].get("source_id") if sync_results else None,
            notebook_id=sync_results[0].get("notebook_id") if sync_results else None,
            notes=f"Partial ingest: {len(sync_results)} success, {len(errors)} failure",
        )
        records, saved = store_record(records, updated)
        save_ingest_log(records)
        save_ingest_markdown(records)
        print_json({"status": saved["status"], "resource_id": saved["resource_id"], "errors": errors, "sync_results": sync_results})
        return 1

    updated = update_record_after_sync(
        record,
        status="INGESTED",
        sync_time=now_iso(),
        source_id=sync_results[0].get("source_id") if sync_results else None,
        notebook_id=sync_results[0].get("notebook_id") if sync_results else None,
        notes=f"Batch sync results stored: {len(sync_results)} item(s)",
        sync_results=sync_results,
    )
    records, saved = store_record(records, updated)
    save_ingest_log(records)
    save_ingest_markdown(records)
    print_json({"status": saved["status"], "resource_id": saved["resource_id"], "results": sync_results})
    return 0


def cmd_query(args: argparse.Namespace) -> int:
    if args.log_derived_note and not args.save_note:
        print_json({"status": "FAILED", "error": "--log-derived-note requires --save-note"})
        return 2
    if args.open_in_obsidian and not args.save_note:
        print_json({"status": "FAILED", "error": "--open-in-obsidian requires --save-note for query"})
        return 2

    connector = NotebookLMConnector(storage_path=args.storage)
    if not connector.available:
        print_json({"status": "FAILED", "reason": "notebooklm package not installed"})
        return 2
    question = MODE_PROMPTS[args.mode] + "\n\n" + args.question
    try:
        result = asyncio.run(
            connector.query(
                target_notebook=args.notebook,
                question=question,
                source_ids=parse_multi(args.source_id),
            )
        )
    except Exception as exc:
        print_json({"status": "FAILED", "error": str(exc)})
        return 1

    saved_note_path: Path | None = None
    if args.save_note:
        saved_note_path = save_note(
            args.save_note,
            f"NotebookLM query: {args.question}",
            result["answer"],
            result["references"],
            notebook=args.notebook,
            mode=args.mode,
            question=args.question,
            registers=parse_multi(getattr(args, "register", None)),
            concepts=parse_multi(getattr(args, "concept", None)),
            topic=getattr(args, "topic", None),
        )

    if args.log_derived_note:
        rows = load_ingest_log()
        derived_record = build_derived_note_record(args, saved_note_path, result)
        rows, _saved = store_record(rows, derived_record)
        save_ingest_log(rows)
        save_ingest_markdown(rows)

    payload = {"status": "OK", **result}
    if saved_note_path is not None:
        payload["saved_note_path"] = str(saved_note_path)
        payload["derived_note_logged"] = bool(args.log_derived_note)
        if args.open_in_obsidian:
            try:
                payload["obsidian_open"] = open_note_in_obsidian(saved_note_path, args)
            except Exception as exc:
                payload["status"] = "PARTIAL"
                payload["obsidian_error"] = str(exc)
                print_json(payload)
                return 1

    if args.json:
        print_json(payload)
    else:
        print(result["answer"])
        if result["references"]:
            print("\nReferences:")
            for ref in result["references"]:
                label = ref.get("source_title") or ref.get("source_id") or "unknown"
                print(f"- [{ref.get('citation_number')}] {label}")
        if saved_note_path is not None:
            print(f"\nSaved note: {saved_note_path}")
            if payload.get("obsidian_open"):
                print(f"Opened in Obsidian via {payload['obsidian_open']['method']}")
    return 0


def cmd_promote(args: argparse.Namespace) -> int:
    checks = evaluate_promotion(args.path)
    record = build_record(args, "promote", "INDEXED", notes="Promotion dry run" if args.dry_run else None)
    record["promotion_candidate"] = "high"
    record["notes"] = json.dumps(checks, ensure_ascii=False)
    records = load_ingest_log()

    if not all(checks.values()):
        updated = update_record_after_sync(record, status="FAILED", sync_time=None, error=promotion_failed_reason(checks))
        records, saved = store_record(records, updated)
        save_ingest_log(records)
        save_ingest_markdown(records)
        print_json({"status": saved["status"], "resource_id": saved["resource_id"], "checks": checks, "error": saved["last_error"]})
        return 1

    connector = NotebookLMConnector(storage_path=args.storage)
    if args.dry_run:
        records, saved = store_record(records, record)
        save_ingest_log(records)
        save_ingest_markdown(records)
        print_json({"status": saved["status"], "resource_id": saved["resource_id"], "checks": checks, "dry_run": True})
        return 0

    if not connector.available:
        updated = update_record_after_sync(record, status="SYNC_PENDING", sync_time=None, error="notebooklm package not installed")
        records, saved = store_record(records, updated)
        save_ingest_log(records)
        save_ingest_markdown(records)
        print_json({"status": saved["status"], "resource_id": saved["resource_id"], "checks": checks, "reason": saved["last_error"]})
        return 0

    sync_results, errors = sync_record_batch(connector, record, wait=args.wait, wait_timeout=args.wait_timeout)
    if errors:
        updated = update_record_after_sync(
            record,
            status="FAILED",
            sync_time=now_iso() if sync_results else None,
            error="; ".join(errors),
            sync_results=sync_results,
            source_id=sync_results[0].get("source_id") if sync_results else None,
            notebook_id=sync_results[0].get("notebook_id") if sync_results else None,
            notes=f"Partial promotion: {len(sync_results)} success, {len(errors)} failure",
        )
        records, saved = store_record(records, updated)
        save_ingest_log(records)
        save_ingest_markdown(records)
        print_json({"status": saved["status"], "resource_id": saved["resource_id"], "checks": checks, "errors": errors, "sync_results": sync_results})
        return 1

    updated = update_record_after_sync(
        record,
        status="PROMOTED",
        sync_time=now_iso(),
        source_id=sync_results[0].get("source_id") if sync_results else None,
        notebook_id=sync_results[0].get("notebook_id") if sync_results else None,
        notes=f"Batch sync results stored: {len(sync_results)} item(s)",
        sync_results=sync_results,
    )
    records, saved = store_record(records, updated)
    save_ingest_log(records)
    save_ingest_markdown(records)
    payload = {"status": saved["status"], "resource_id": saved["resource_id"], "checks": checks, "results": sync_results}
    if args.open_in_obsidian:
        try:
            payload["obsidian_open"] = open_note_in_obsidian(args.path, args)
        except Exception as exc:
            payload["status"] = "PARTIAL"
            payload["obsidian_error"] = str(exc)
            print_json(payload)
            return 1
    print_json(payload)
    return 0


def cmd_wait(args: argparse.Namespace) -> int:
    connector = NotebookLMConnector(storage_path=args.storage)
    if not connector.available:
        print_json({"status": "FAILED", "reason": "notebooklm package not installed"})
        return 2

    wait_targets: dict[str, list[str]] = {}
    explicit_source_ids = parse_multi(args.source_id)
    if explicit_source_ids:
        if not args.notebook:
            print_json({"status": "FAILED", "error": "--notebook is required when using --source-id"})
            return 2
        wait_targets[args.notebook] = explicit_source_ids

    if args.resource_id:
        rows = load_ingest_log()
        matching = [row for row in rows if row.get("resource_id") == args.resource_id]
        if not matching:
            print_json({"status": "FAILED", "error": f"Unknown resource_id: {args.resource_id}"})
            return 2
        for record in matching:
            source_ids = collect_source_ids(record)
            notebook_ids = [args.notebook] if args.notebook else collect_notebook_ids(record)
            if not source_ids:
                print_json({"status": "FAILED", "error": f"No NotebookLM source IDs recorded for {args.resource_id}"})
                return 2
            if not notebook_ids:
                print_json({"status": "FAILED", "error": f"No NotebookLM notebook IDs recorded for {args.resource_id}; pass --notebook explicitly"})
                return 2
            for notebook_id in notebook_ids:
                wait_targets.setdefault(notebook_id, [])
                for source_id in source_ids:
                    if source_id not in wait_targets[notebook_id]:
                        wait_targets[notebook_id].append(source_id)

    if not wait_targets:
        print_json({"status": "FAILED", "error": "Provide either --source-id or --resource-id"})
        return 2

    payload: list[dict[str, Any]] = []
    for notebook_id, source_ids in wait_targets.items():
        try:
            ready_sources = asyncio.run(
                connector.wait_for_sources(
                    target_notebook=notebook_id,
                    source_ids=source_ids,
                    timeout=args.timeout,
                )
            )
            payload.append({"notebook": notebook_id, "sources": ready_sources})
        except Exception as exc:
            print_json({"status": "FAILED", "notebook": notebook_id, "error": str(exc)})
            return 1

    print_json({"status": "OK", "wait_results": payload})
    return 0
def cmd_status(args: argparse.Namespace) -> int:
    rows = load_ingest_log()
    counts = Counter(row.get("status", "UNKNOWN") for row in rows)
    recent_promoted = [
        {
            "resource_id": row.get("resource_id"),
            "title": row.get("title"),
            "last_synced_at": row.get("last_synced_at"),
        }
        for row in sorted(rows, key=lambda item: item.get("last_synced_at") or "", reverse=True)
        if row.get("status") == "PROMOTED"
    ][:5]
    pending = [
        {
            "resource_id": row.get("resource_id"),
            "title": row.get("title"),
            "target_notebook": row.get("target_notebook"),
        }
        for row in rows
        if row.get("status") == "SYNC_PENDING"
    ]
    connector = NotebookLMConnector(storage_path=args.storage)
    payload = {
        "connector_available": connector.available,
        "connector_health": run_healthcheck(connector) if args.healthcheck else None,
        "registry_concepts": len(load_registry_state().get("concepts", [])),
        "ingest_records": len(rows),
        "status_counts": dict(counts),
        "sync_pending": pending,
        "recent_promoted": recent_promoted,
    }
    print_json(payload)
    return 0


def replay_record(connector: NotebookLMConnector, record: dict[str, Any], *, wait: bool, wait_timeout: float) -> tuple[dict[str, Any], bool]:
    operation = record.get("operation")
    sync_results, errors = sync_record_batch(connector, record, wait=wait, wait_timeout=wait_timeout)
    final_status = "PROMOTED" if operation == "promote" else "INGESTED"
    if errors:
        updated = update_record_after_sync(
            record,
            status="FAILED",
            sync_time=now_iso() if sync_results else None,
            error="; ".join(errors),
            sync_results=sync_results,
            source_id=sync_results[0].get("source_id") if sync_results else None,
            notebook_id=sync_results[0].get("notebook_id") if sync_results else None,
            notes=f"Partial replay: {len(sync_results)} success, {len(errors)} failure",
        )
        return updated, False

    updated = update_record_after_sync(
        record,
        status=final_status,
        sync_time=now_iso(),
        source_id=sync_results[0].get("source_id") if sync_results else None,
        notebook_id=sync_results[0].get("notebook_id") if sync_results else None,
        notes=f"Batch sync results stored: {len(sync_results)} item(s)",
        sync_results=sync_results,
    )
    return updated, True


def cmd_sync_pending(args: argparse.Namespace) -> int:
    connector = NotebookLMConnector(storage_path=args.storage)
    if not connector.available:
        print_json({"status": "FAILED", "reason": "notebooklm package not installed"})
        return 2

    rows = load_ingest_log()
    updated_rows: list[dict[str, Any]] = []
    replayed = 0
    successes = 0
    for row in rows:
        if row.get("status") != "SYNC_PENDING":
            updated_rows.append(row)
            continue
        replayed += 1
        updated, ok = replay_record(connector, row, wait=args.wait, wait_timeout=args.wait_timeout)
        if ok:
            successes += 1
        updated_rows.append(updated)

    save_ingest_log(updated_rows)
    save_ingest_markdown(updated_rows)
    print_json({"replayed": replayed, "successful": successes, "failed": replayed - successes})
    return 0 if replayed == successes else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Thin local-first NotebookLM sync wrapper")
    parser.add_argument("--storage", help="Optional notebooklm-py storage path", default=None)
    subparsers = parser.add_subparsers(dest="command", required=True)

    ingest = subparsers.add_parser("ingest", help="Log and optionally ingest a resource")
    source_group = ingest.add_mutually_exclusive_group(required=True)
    source_group.add_argument("--path", help="Local file path to ingest")
    source_group.add_argument("--url", help="Remote URL to ingest")
    ingest.add_argument("--notebook", required=True, help="NotebookLM notebook id or title")
    ingest.add_argument("--type", default="resource", help="Resource type label")
    ingest.add_argument("--title", help="Optional human title")
    ingest.add_argument("--register", action="append", help="Register name; repeat or comma-separate")
    ingest.add_argument("--concept", action="append", help="Concept name; repeat or comma-separate")
    ingest.add_argument("--resource-id", help="Optional explicit resource id")
    ingest.add_argument("--why", help="Why this resource matters")
    ingest.add_argument("--dry-run", action="store_true", help="Update local state only")
    ingest.add_argument("--wait", action="store_true", help="Wait for source processing before returning")
    ingest.add_argument("--wait-timeout", type=float, default=120.0, help="Seconds to wait when --wait is used")
    ingest.set_defaults(func=cmd_ingest)

    query = subparsers.add_parser("query", help="Ask a NotebookLM notebook")
    query.add_argument("--notebook", required=True, help="NotebookLM notebook id or title")
    query.add_argument("--question", required=True, help="Question to ask")
    query.add_argument("--source-id", action="append", help="Optional source ids to scope the query")
    query.add_argument("--mode", choices=sorted(MODE_PROMPTS), default="simple")
    query.add_argument("--save-note", help="Optional local markdown note path")
    query.add_argument("--json", action="store_true", help="Emit JSON")
    query.add_argument("--log-derived-note", action="store_true", help="Log the saved query note as a derived local resource")
    query.add_argument("--derived-title", help="Optional title for the derived local note record")
    query.add_argument("--derived-type", default="derived_note", help="Type label for the derived local note record")
    query.add_argument("--derived-notebook", default=LOCAL_ONLY_TARGET, help="Logical target notebook for the derived note record")
    query.add_argument("--register", action="append", help="Register name for a derived note record")
    query.add_argument("--concept", action="append", help="Concept name for a derived note record")
    query.add_argument("--topic", help="Topic label used to cluster related notes in folders and graph metadata")
    query.add_argument("--why", help="Why the derived note matters")
    add_obsidian_args(query)
    query.set_defaults(func=cmd_query)

    promote = subparsers.add_parser("promote", help="Promote a teaching note to core curriculum")
    promote.add_argument("--path", required=True, help="Local markdown note path")
    promote.add_argument("--notebook", default="NBLM-10-Core-Curriculum", help="Target notebook")
    promote.add_argument("--type", default="teaching_note", help="Resource type label")
    promote.add_argument("--title", help="Optional human title")
    promote.add_argument("--resource-id", help="Optional explicit resource id")
    promote.add_argument("--register", action="append", help="Register name; repeat or comma-separate")
    promote.add_argument("--concept", action="append", help="Concept name; repeat or comma-separate")
    promote.add_argument("--why", help="Why this note matters")
    promote.add_argument("--dry-run", action="store_true", help="Validate and log only")
    promote.add_argument("--wait", action="store_true", help="Wait for source processing before returning")
    promote.add_argument("--wait-timeout", type=float, default=120.0, help="Seconds to wait when --wait is used")
    add_obsidian_args(promote)
    promote.set_defaults(func=cmd_promote)

    wait_cmd = subparsers.add_parser("wait", help="Wait for one or more NotebookLM sources to become ready")
    wait_cmd.add_argument("--notebook", help="NotebookLM notebook id or title")
    wait_cmd.add_argument("--source-id", action="append", help="Source id(s); repeat or comma-separate")
    wait_cmd.add_argument("--resource-id", help="Existing local resource id to resolve NotebookLM source ids from the log")
    wait_cmd.add_argument("--timeout", type=float, default=120.0, help="Maximum seconds to wait per notebook batch")
    wait_cmd.set_defaults(func=cmd_wait)

    status = subparsers.add_parser("status", help="Show local sync status")
    status.add_argument("--healthcheck", action="store_true", help="Also verify that auth and notebook listing work")
    status.set_defaults(func=cmd_status)

    sync_pending = subparsers.add_parser("sync-pending", help="Replay pending ingest/promote items")
    sync_pending.add_argument("--wait", action="store_true", help="Wait for source processing during replay")
    sync_pending.add_argument("--wait-timeout", type=float, default=120.0, help="Seconds to wait when --wait is used")
    sync_pending.set_defaults(func=cmd_sync_pending)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())