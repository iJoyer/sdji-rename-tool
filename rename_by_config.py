#!/usr/bin/env python3
import csv
import os
import re
from pathlib import Path
from typing import Any


def _strip_comment(line: str) -> str:
    in_quote = False
    quote_char = ""
    out = []
    i = 0
    while i < len(line):
        ch = line[i]
        if ch in ("'", '"'):
            if not in_quote:
                in_quote = True
                quote_char = ch
            elif quote_char == ch:
                in_quote = False
            out.append(ch)
            i += 1
            continue
        if ch == "#" and not in_quote:
            break
        out.append(ch)
        i += 1
    return "".join(out).rstrip()


def _parse_scalar(token: str) -> Any:
    token = token.strip()
    if not token:
        return ""
    if (token.startswith('"') and token.endswith('"')) or (
        token.startswith("'") and token.endswith("'")
    ):
        return token[1:-1]
    low = token.lower()
    if low == "true":
        return True
    if low == "false":
        return False
    if re.fullmatch(r"-?\d+", token):
        return int(token)
    return token


def load_simple_yaml(path: Path) -> dict[str, Any]:
    lines = path.read_text(encoding="utf-8").splitlines()
    root: dict[str, Any] = {}
    stack: list[tuple[int, Any]] = [(-1, root)]

    def pop_to(indent: int) -> None:
        while len(stack) > 1 and stack[-1][0] >= indent:
            stack.pop()

    i = 0
    while i < len(lines):
        raw = _strip_comment(lines[i])
        i += 1
        if not raw.strip():
            continue

        indent = len(raw) - len(raw.lstrip(" "))
        if indent % 2 != 0:
            raise ValueError(f"Invalid indentation at line {i}: {raw}")
        text = raw.strip()
        pop_to(indent)
        parent = stack[-1][1]

        if text.startswith("- "):
            if not isinstance(parent, list):
                raise ValueError(f"List item without list parent at line {i}: {raw}")
            parent.append(_parse_scalar(text[2:].strip()))
            continue

        if ":" not in text:
            raise ValueError(f"Invalid mapping line {i}: {raw}")
        key, rest = text.split(":", 1)
        key = key.strip()
        rest = rest.strip()

        if rest:
            if not isinstance(parent, dict):
                raise ValueError(f"Key-value under non-dict parent at line {i}: {raw}")
            parent[key] = _parse_scalar(rest)
            continue

        j = i
        next_item = None
        while j < len(lines):
            probe = _strip_comment(lines[j])
            j += 1
            if not probe.strip():
                continue
            probe_indent = len(probe) - len(probe.lstrip(" "))
            if probe_indent <= indent:
                next_item = None
                break
            next_item = probe.strip()
            break

        if next_item is not None and next_item.startswith("- "):
            node: Any = []
        else:
            node = {}

        if not isinstance(parent, dict):
            raise ValueError(f"Nested mapping under non-dict parent at line {i}: {raw}")
        parent[key] = node
        stack.append((indent, node))

    return root


def list_image_files(base_dir: Path, recursive: bool, exts: set[str]) -> list[Path]:
    files: list[Path] = []
    iterator = base_dir.rglob("*") if recursive else base_dir.glob("*")
    for p in iterator:
        if not p.is_file():
            continue
        ext = p.suffix.lower().lstrip(".")
        if ext in exts:
            files.append(p)
    return sorted(files)


def remove_timestamp_after_prefix(stem: str, prefix: str) -> str:
    pattern = re.compile(
        rf"^({re.escape(prefix)}_)(\d{{14}}|\d{{8}})_(.+)$", re.IGNORECASE
    )
    m = pattern.match(stem)
    if not m:
        return stem
    return f"{m.group(1)}{m.group(3)}"


def split_tail_suffix(stem: str) -> tuple[str, str]:
    if "_" not in stem:
        return stem, ""
    head, tail = stem.rsplit("_", 1)
    if re.fullmatch(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*", tail):
        return head, tail
    return stem, ""


def strip_hyphen_chain(base: str, keep_markers: set[str], remove_markers: set[str]) -> str:
    if "-" not in base:
        return base
    core, hyphen_part = base.split("-", 1)
    chain = hyphen_part.split("-")
    for token in chain:
        marker = f"-{token}"
        if marker in keep_markers:
            continue
        if marker in remove_markers:
            return core
    return base


def remove_underscore_markers(base: str, remove_markers: set[str]) -> str:
    if "_" not in base:
        return base
    parts = base.split("_")
    if not parts:
        return base
    kept = [parts[0]]
    for token in parts[1:]:
        marker = f"_{token}"
        if marker in remove_markers:
            continue
        kept.append(token)
    return "_".join(kept)


def normalize_name(stem: str, rules: dict[str, Any]) -> str:
    original_stem = stem
    prefix = str(rules.get("starts_with", "DJI"))
    is_prefix_match = stem.startswith(prefix)
    changed = False

    if bool(rules.get("remove_middle_timestamp", False)) and bool(
        rules.get("timestamp_must_follow_prefix", False)
    ) and is_prefix_match:
        updated = remove_timestamp_after_prefix(stem, prefix)
        if updated != stem:
            changed = True
            stem = updated

    keep_markers = set(rules.get("keep_markers", []))
    remove_markers = set(rules.get("remove_markers", []))

    stem, suffix = split_tail_suffix(stem)
    updated = remove_underscore_markers(stem, remove_markers)
    if updated != stem:
        changed = True
        stem = updated

    updated = strip_hyphen_chain(stem, keep_markers, remove_markers)
    if updated != stem:
        changed = True
        stem = updated

    updated = remove_underscore_markers(stem, remove_markers)
    if updated != stem:
        changed = True
        stem = updated

    if suffix:
        stem = f"{stem}_{suffix}"

    # 仅在本轮确实发生清理时，才移除原始末尾 -数字，避免重复运行时二次漂移。
    if changed and bool(rules.get("remove_existing_trailing_dash_number", True)):
        stem = re.sub(r"-\d+$", "", stem)

    return stem if stem != original_stem else original_stem


def resolve_conflict(
    src: Path,
    target: Path,
    taken: set[Path],
    strategy: str,
    source_serial_stem: str,
    start_index: int,
) -> Path:
    if target == src:
        return target
    if target not in taken and not target.exists():
        return target
    if strategy != "append_dash_index":
        raise ValueError(f"Unsupported conflict strategy: {strategy}")

    idx = max(2, start_index)
    while True:
        candidate_name = f"{source_serial_stem}-{idx}{target.suffix}"
        candidate = target.with_name(candidate_name)
        if candidate not in taken and not candidate.exists():
            return candidate
        idx += 1


def main() -> None:
    base_dir = Path(".").resolve()
    config = load_simple_yaml(base_dir / "rename_config.yaml")

    scope = config.get("scope", {})
    file_types = config.get("file_types", {})
    dji_rules = config.get("dji_rules", {})
    conflict = config.get("conflict_resolution", {})
    execution = config.get("execution", {})

    recursive = bool(scope.get("recursive", True))
    exts = {str(e).lower() for e in file_types.get("image_extensions", [])}
    dry_run = bool(execution.get("dry_run", True))
    log_enabled = bool(execution.get("create_rename_log", True))
    log_name = str(execution.get("rename_log_file", "rename_log.csv"))
    conflict_strategy = str(conflict.get("strategy", "append_dash_index"))
    conflict_start_index = int(conflict.get("start_index", 2))
    dji_enabled = bool(dji_rules.get("enabled", True))

    if not exts:
        print("未配置 image_extensions，已退出。")
        return

    files = list_image_files(base_dir, recursive=recursive, exts=exts)
    if not files:
        print("未找到可处理的图片文件。")
        return

    plan: list[tuple[Path, Path]] = []
    taken_targets: set[Path] = set()

    for src in files:
        stem = src.stem
        ext = src.suffix

        if dji_enabled:
            new_stem = normalize_name(stem, dji_rules)
        else:
            new_stem = stem

        if new_stem == stem:
            continue

        target = src.with_name(new_stem + ext)
        target = resolve_conflict(
            src=src,
            target=target,
            taken=taken_targets,
            strategy=conflict_strategy,
            source_serial_stem=new_stem,
            start_index=conflict_start_index,
        )
        taken_targets.add(target)

        if target != src:
            plan.append((src, target))

    if not plan:
        print("没有需要改名的文件。")
        return

    print(f"待处理: {len(plan)}")
    for src, dst in plan:
        rel_src = src.relative_to(base_dir)
        rel_dst = dst.relative_to(base_dir)
        print(f"{rel_src} -> {rel_dst}")

    if log_enabled:
        with (base_dir / log_name).open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["source", "target"])
            for src, dst in plan:
                writer.writerow([str(src.relative_to(base_dir)), str(dst.relative_to(base_dir))])
        print(f"日志已写入: {log_name}")

    if dry_run:
        print("dry_run=true，未执行实际改名。")
        return

    for src, dst in plan:
        dst.parent.mkdir(parents=True, exist_ok=True)
        src.rename(dst)
    print("改名完成。")


if __name__ == "__main__":
    main()
