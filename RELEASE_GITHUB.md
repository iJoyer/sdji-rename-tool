# GitHub 发布流程

目标仓库：

```bash
git@github.com:iJoyer/sdji-rename-tool.git
```

本地默认 `origin` 是 Gitea，发布到 GitHub 时使用 `github` 远端。

## 首次配置

```bash
git remote add github git@github.com:iJoyer/sdji-rename-tool.git
git fetch github main
```

如果 GitHub 仓库已有不同历史，先合并一次：

```bash
git merge github/main --allow-unrelated-histories
```

冲突处理原则：

- 以当前本地项目结构为准。
- 不保留根目录旧 Swift 布局：`Package.swift`、`Sources/`、`build_app.sh`。
- 不提交构建产物：`.build/`、`dist/`、`dist-swift/`、`release/`、`.DS_Store`、`*.spec`。

## 日常发布

```bash
git status -sb
git add <需要发布的文件>
git commit -m "简短中文提交信息"
python3 - <<'PY'
from pathlib import Path
from tempfile import TemporaryDirectory
from pic_rename_tool.cli import build_rename_plan, load_builtin_default_config

with TemporaryDirectory() as d:
    base = Path(d)
    (base / "DSCF4696-Enhanced-NR.JPG").touch()
    plan = build_rename_plan(base, load_builtin_default_config())
    for item in plan:
        print(item.source.name, "->", item.target.name)
PY
swift build --package-path swift/SDJIRenameTool
git push github main
```

推送后确认：

```bash
git ls-remote github refs/heads/main
git rev-parse HEAD
```

两边 commit hash 一致即可。
