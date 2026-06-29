#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from importlib.abc import Traversable
import importlib.resources as pkg_resources
import os
import platform
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from pic_rename_tool import __version__


APP_NAME = "pic-rename"
MAC_APP_NAME = "SDJI Rename Tool"


@dataclass(frozen=True)
class RenamePlanItem:
    source: Path
    target: Path


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
    if low in {"true", "yes", "on"}:
        return True
    if low in {"false", "no", "off"}:
        return False
    if low in {"null", "none", "~"}:
        return None
    if re.fullmatch(r"-?\d+", token):
        return int(token)
    return token


def load_simple_yaml(path: Path) -> dict[str, Any]:
    lines = path.read_text(encoding="utf-8").splitlines()
    return load_simple_yaml_lines(lines)


def load_simple_yaml_lines(lines: list[str]) -> dict[str, Any]:
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


def load_builtin_default_config() -> dict[str, Any]:
    text = get_builtin_config_resource().read_text(encoding="utf-8")
    return load_simple_yaml_lines(text.splitlines())


def get_builtin_config_resource() -> Traversable:
    return pkg_resources.files("pic_rename_tool").joinpath("default_config.yaml")


def get_user_config_path() -> Path:
    if os.name == "nt":
        appdata = os.getenv("APPDATA")
        if appdata:
            return Path(appdata) / APP_NAME / "config.yaml"
        return Path.home() / "AppData" / "Roaming" / APP_NAME / "config.yaml"

    xdg_home = os.getenv("XDG_CONFIG_HOME")
    if xdg_home:
        return Path(xdg_home).expanduser() / APP_NAME / "config.yaml"
    return Path.home() / ".config" / APP_NAME / "config.yaml"


def resolve_config_path(explicit_config_path: Path | None) -> tuple[Path | None, str]:
    if explicit_config_path is not None:
        return explicit_config_path, "explicit"

    user_config_path = get_user_config_path()
    if user_config_path.exists():
        return user_config_path, "user"

    return None, "builtin"


def init_user_config(path: Path, force: bool = False) -> int:
    if path.exists() and not force:
        print(f"配置已存在: {path}")
        print("如需覆盖请加 --force")
        return 0

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(get_builtin_config_resource().read_text(encoding="utf-8"), encoding="utf-8")
    print(f"已写入用户配置: {path}")
    return 0


def find_macos_app_executable() -> Path | None:
    if platform.system() != "Darwin":
        return None

    env_path = os.getenv("SDJI_RENAME_TOOL_APP")
    candidates: list[Path] = []
    if env_path:
        candidates.append(Path(env_path))

    candidates.extend(
        [
            Path("/Applications") / f"{MAC_APP_NAME}.app" / "Contents" / "MacOS" / MAC_APP_NAME,
            Path.home() / "Applications" / f"{MAC_APP_NAME}.app" / "Contents" / "MacOS" / MAC_APP_NAME,
            Path(__file__).resolve().parents[1]
            / "dist-swift"
            / f"{MAC_APP_NAME}.app"
            / "Contents"
            / "MacOS"
            / MAC_APP_NAME,
        ]
    )

    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def translate_args_for_macos_app(argv: list[str]) -> list[str] | None:
    unsupported_legacy_flags = {
        "--config",
        "-c",
        "--init-config",
        "--force",
        "--log-file",
        "--clear-log",
    }
    if any(arg in unsupported_legacy_flags for arg in argv):
        return None

    if not argv:
        return ["--rename-folder", "."]

    if argv[0] in {
        "--rename-folder",
        "--lightroom-export",
        "--undo-last",
        "--dry-run",
        "--config-path",
        "--help",
        "-h",
        "--version",
        "-V",
    }:
        return argv

    if "--undo-last" in argv:
        translated = ["--undo-last"]
        if "--dry-run" in argv:
            translated.append("--dry-run")
        return translated

    path = "."
    dry_run = "--dry-run" in argv
    idx = 0
    while idx < len(argv):
        arg = argv[idx]
        if arg in {"--path", "-p"} and idx + 1 < len(argv):
            path = argv[idx + 1]
            idx += 2
            continue
        idx += 1

    translated = ["--rename-folder", path]
    if dry_run:
        translated.append("--dry-run")
    return translated


def delegate_to_macos_app(argv: list[str]) -> int | None:
    if os.getenv("SDJI_RENAME_TOOL_LEGACY") == "1":
        return None

    app_executable = find_macos_app_executable()
    if app_executable is None:
        return None

    translated = translate_args_for_macos_app(argv)
    if translated is None:
        return None

    result = subprocess.run([str(app_executable), *translated], check=False)
    return result.returncode


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


def confirm_action(message: str) -> bool:
    try:
        answer = input(f"{message} [y/N]: ").strip().lower()
    except EOFError:
        return False
    return answer in {"y", "yes"}


def remove_timestamp_after_prefix(stem: str, prefix: str) -> str:
    # 只要日期前有 prefix_（如 DJI_），就删除日期段，不限制 prefix 前内容
    pattern = re.compile(rf"^(.*{re.escape(prefix)}_)(\d{{14}}|\d{{8}})_(.+)$")
    m = pattern.match(stem)
    if not m:
        return stem
    return f"{m.group(1)}{m.group(3)}"


def has_prefix_token(stem: str, prefix: str) -> bool:
    return f"{prefix}_" in stem


def split_tail_suffix(stem: str) -> tuple[str, str]:
    if "_" not in stem:
        return stem, ""
    head, tail = stem.rsplit("_", 1)
    if re.fullmatch(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*", tail):
        return head, tail
    return stem, ""


def tail_has_removable_underscore_marker(stem: str, remove_markers: set[str]) -> bool:
    if "_" not in stem:
        return False
    tail = stem.rsplit("_", 1)[1]
    if f"_{tail}" in remove_markers:
        return True
    if "-" in tail:
        parts = tail.split("-")
        head = parts[0]
        if f"_{head}" in remove_markers:
            return True
        return any(f"-{part}" in remove_markers for part in parts[1:])
    return False


def strip_hyphen_chain(base: str, keep_markers: set[str], remove_markers: set[str]) -> str:
    if "-" not in base:
        return base

    # 仅处理“最后一个下划线之后”的连字符链，避免误伤前缀分组（如 0815-DJI_...）
    last_us = base.rfind("_")
    search_start = last_us + 1 if last_us >= 0 else 0
    hyphen_pos = base.find("-", search_start)
    if hyphen_pos < 0:
        return base

    core = base[:hyphen_pos]
    hyphen_part = base[hyphen_pos + 1 :]
    chain = hyphen_part.split("-")
    hit_remove = False
    kept_tokens: list[str] = []

    for token in chain:
        marker = f"-{token}"
        if marker in keep_markers:
            kept_tokens.append(token)
            continue
        if marker in remove_markers:
            hit_remove = True
            continue

        # 未命中词表：仅在没有删除命中时保留原链
        if not hit_remove:
            kept_tokens.append(token)

    if not hit_remove:
        return base
    if not kept_tokens:
        return core
    return f"{core}-{'-'.join(kept_tokens)}"


def remove_underscore_markers(
    base: str,
    keep_markers: set[str],
    remove_markers: set[str],
) -> str:
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

        # 处理组合段：_D-T 命中 _D 时，保留 -T 到前一段
        if "-" in token:
            head, rest = token.split("-", 1)
            if f"_{head}" in remove_markers:
                kept_rest = [part for part in rest.split("-") if f"-{part}" in keep_markers]
                if kept_rest:
                    kept[-1] = f"{kept[-1]}-{'-'.join(kept_rest)}"
                continue

        kept.append(token)
    return "_".join(kept)


def normalize_name(stem: str, rules: dict[str, Any]) -> str:
    original_stem = stem
    prefix = str(rules.get("starts_with", "DJI"))
    is_prefix_match = has_prefix_token(stem, prefix)
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

    suffix = ""
    if not tail_has_removable_underscore_marker(stem, remove_markers):
        stem, suffix = split_tail_suffix(stem)
    updated = remove_underscore_markers(stem, keep_markers, remove_markers)
    if updated != stem:
        changed = True
        stem = updated

    updated = strip_hyphen_chain(stem, keep_markers, remove_markers)
    if updated != stem:
        changed = True
        stem = updated

    updated = remove_underscore_markers(stem, keep_markers, remove_markers)
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
) -> Path | None:
    if target == src:
        return target
    if target not in taken and not target.exists():
        return target
    if strategy == "skip":
        return None
    if strategy not in {"append_dash_index", "append_parentheses_index", "append_underscore_index"}:
        raise ValueError(f"Unsupported conflict strategy: {strategy}")

    idx = max(2, start_index)
    while True:
        if strategy == "append_parentheses_index":
            candidate_name = f"{source_serial_stem} ({idx}){target.suffix}"
        elif strategy == "append_underscore_index":
            candidate_name = f"{source_serial_stem}_{idx}{target.suffix}"
        else:
            candidate_name = f"{source_serial_stem}-{idx}{target.suffix}"
        candidate = target.with_name(candidate_name)
        if candidate not in taken and not candidate.exists():
            return candidate
        idx += 1


def load_effective_config(config_path: Path | None) -> dict[str, Any]:
    if config_path is None:
        return load_builtin_default_config()
    if not config_path.exists():
        raise FileNotFoundError(f"未找到配置文件: {config_path}")
    return load_simple_yaml(config_path)


def build_rename_plan(base_dir: Path, config: dict[str, Any]) -> list[RenamePlanItem]:
    scope = config.get("scope", {})
    file_types = config.get("file_types", {})
    dji_rules = config.get("dji_rules", {})
    conflict = config.get("conflict_resolution", {})

    recursive = bool(scope.get("recursive", True))
    exts = {str(e).lower() for e in file_types.get("image_extensions", [])}
    conflict_strategy = str(conflict.get("strategy", "append_dash_index"))
    conflict_start_index = int(conflict.get("start_index", 2))
    dji_enabled = bool(dji_rules.get("enabled", True))

    if not exts:
        return []

    files = list_image_files(base_dir, recursive=recursive, exts=exts)
    if not files:
        return []

    plan: list[RenamePlanItem] = []
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
        if target is None:
            continue
        taken_targets.add(target)

        if target != src:
            plan.append(RenamePlanItem(source=src, target=target))

    return plan


def write_rename_log(base_dir: Path, log_path: Path, plan: list[RenamePlanItem]) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["base_dir", "source", "target"])
        for item in plan:
            writer.writerow(
                [
                    str(base_dir),
                    str(item.source.relative_to(base_dir)),
                    str(item.target.relative_to(base_dir)),
                ]
            )


def apply_rename_plan(plan: list[RenamePlanItem]) -> None:
    for item in plan:
        item.target.parent.mkdir(parents=True, exist_ok=True)
        item.source.rename(item.target)


def run(
    base_dir: Path,
    config_path: Path | None,
    dry_run_override: bool | None = None,
    auto_confirm: bool = False,
) -> int:
    try:
        config = load_effective_config(config_path)
    except FileNotFoundError as e:
        print(str(e))
        return 1

    execution = config.get("execution", {})
    dry_run = bool(execution.get("dry_run", True))
    if dry_run_override is not None:
        dry_run = dry_run_override
    log_enabled = bool(execution.get("create_rename_log", True))
    log_name = str(execution.get("rename_log_file", "rename_log.csv"))

    plan = build_rename_plan(base_dir=base_dir, config=config)

    if not plan:
        print("没有需要改名的文件。")
        return 0

    print(f"待处理: {len(plan)}")
    for item in plan:
        rel_src = item.source.relative_to(base_dir)
        rel_dst = item.target.relative_to(base_dir)
        print(f"{rel_src} -> {rel_dst}")

    if not dry_run and not auto_confirm:
        if not confirm_action(f"确认执行改名 {len(plan)} 个文件吗？"):
            print("已取消改名。")
            return 0

    if log_enabled:
        log_path = (base_dir / log_name).resolve()
        write_rename_log(base_dir=base_dir, log_path=log_path, plan=plan)
        print(f"日志已写入: {log_path}")

    if dry_run:
        print("dry_run=true，未执行实际改名。")
        return 0

    apply_rename_plan(plan)
    print("改名完成。")
    return 0


def resolve_log_path(base_dir: Path, config: dict[str, Any], explicit_log_path: Path | None) -> Path:
    if explicit_log_path is not None:
        return explicit_log_path
    execution = config.get("execution", {})
    log_name = str(execution.get("rename_log_file", "rename_log.csv"))
    return (base_dir / log_name).resolve()


def clear_log_file(log_path: Path, dry_run: bool = False) -> int:
    if dry_run:
        print(f"dry_run=true，未执行日志清空: {log_path}")
        return 0
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["base_dir", "source", "target"])
    print(f"日志已清空: {log_path}")
    return 0


def undo_last(base_dir: Path, log_path: Path, dry_run: bool = False, clear_log: bool = False) -> int:
    if not log_path.exists():
        print(f"未找到日志文件: {log_path}")
        print("可用 --log-file 指定日志路径，或用与改名时相同的 --path。")
        return 1

    rows: list[tuple[Path, Path, str, str]] = []
    with log_path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames or "source" not in reader.fieldnames or "target" not in reader.fieldnames:
            print("日志格式无效，缺少 source/target 列。")
            return 1
        for row in reader:
            row_base_raw = (row.get("base_dir") or "").strip()
            source_raw = (row.get("source") or "").strip()
            target_raw = (row.get("target") or "").strip()
            if not source_raw or not target_raw:
                continue

            row_base = Path(row_base_raw).resolve() if row_base_raw else base_dir
            source = (row_base / source_raw).resolve()
            target = (row_base / target_raw).resolve()
            try:
                source.relative_to(row_base)
                target.relative_to(row_base)
            except ValueError:
                print(f"跳过(日志路径越界): {source_raw} / {target_raw}")
                continue
            rows.append((source, target, source_raw, target_raw))

    if not rows:
        print("日志为空，未执行恢复。")
        return 0

    print(f"待恢复: {len(rows)}")
    for _source, _target, source_raw, target_raw in reversed(rows):
        print(f"{target_raw} -> {source_raw}")

    if dry_run:
        print("dry_run=true，未执行实际恢复。")
        if clear_log:
            print("dry_run=true，未执行日志清空。")
        return 0

    restored = 0
    skipped = 0
    for source, target, source_raw, target_raw in reversed(rows):
        if not target.exists():
            print(f"跳过(目标不存在): {target_raw}")
            skipped += 1
            continue
        if source.exists():
            print(f"跳过(原路径已存在): {source_raw}")
            skipped += 1
            continue
        source.parent.mkdir(parents=True, exist_ok=True)
        target.rename(source)
        restored += 1

    print(f"恢复完成。成功: {restored}，跳过: {skipped}")
    if clear_log:
        clear_log_file(log_path=log_path, dry_run=False)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pic-rename",
        description="按 YAML 配置批量规范化图片文件名（支持内置/用户/外部配置）。",
    )
    parser.add_argument(
        "-p",
        "--path",
        default=".",
        help="要处理的目录（默认当前目录）",
    )
    parser.add_argument(
        "-c",
        "--config",
        default=None,
        help="外部配置路径（最高优先级，默认相对 --path）",
    )
    parser.add_argument(
        "--init-config",
        action="store_true",
        help="初始化用户配置到 ~/.config/pic-rename/config.yaml（Windows: %%APPDATA%%）",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="配合 --init-config 覆盖已有用户配置",
    )
    parser.add_argument(
        "--undo-last",
        action="store_true",
        help="按改名日志恢复上次改名（目标->原名）",
    )
    parser.add_argument(
        "--log-file",
        default=None,
        help="恢复时指定日志文件路径（默认使用配置里的 rename_log_file）",
    )
    parser.add_argument(
        "--clear-log",
        action="store_true",
        help="清空日志；可配合 --undo-last 在恢复后清空",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="跳过改名前确认提示",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="预览模式（改名/恢复都不实际执行）",
    )
    parser.add_argument(
        "-V",
        "--version",
        action="version",
        version=f"%(prog)s {__version__}",
    )
    return parser


def main(argv: list[str] | None = None) -> None:
    if argv is None:
        argv = sys.argv[1:]

    delegated_status = delegate_to_macos_app(argv)
    if delegated_status is not None:
        raise SystemExit(delegated_status)

    parser = build_parser()
    args = parser.parse_args(argv)

    base_dir = Path(args.path).resolve()
    user_config_path = get_user_config_path()

    if args.init_config:
        raise SystemExit(init_user_config(path=user_config_path, force=args.force))

    config_path: Path | None = None
    if args.config:
        config_path = Path(args.config)
        if not config_path.is_absolute():
            config_path = (base_dir / config_path).resolve()

    resolved_config_path, _source = resolve_config_path(config_path)

    if args.undo_last or args.clear_log:
        try:
            config = load_effective_config(resolved_config_path)
        except FileNotFoundError as e:
            print(str(e))
            raise SystemExit(1)

        explicit_log_path: Path | None = None
        if args.log_file:
            explicit_log_path = Path(args.log_file)
            if not explicit_log_path.is_absolute():
                explicit_log_path = (base_dir / explicit_log_path).resolve()

        log_path = resolve_log_path(base_dir, config=config, explicit_log_path=explicit_log_path)

        if args.undo_last:
            raise SystemExit(
                undo_last(
                    base_dir=base_dir,
                    log_path=log_path,
                    dry_run=args.dry_run,
                    clear_log=args.clear_log,
                )
            )

        raise SystemExit(clear_log_file(log_path=log_path, dry_run=args.dry_run))

    raise SystemExit(
        run(
            base_dir=base_dir,
            config_path=resolved_config_path,
            dry_run_override=args.dry_run or None,
            auto_confirm=args.yes,
        )
    )
