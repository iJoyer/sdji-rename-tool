# Rename Tool

用于按配置批量规范化图片文件名的 CLI（可发布到 PyPI）。

## Install

Python 用户：

```bash
pipx install pic-rename-tool
```

或：

```bash
pip install pic-rename-tool
```

npm/pnpm 用户（需本机有 Python 3.9+）：

```bash
npm install -g pic-rename-tool
```

或：

```bash
pnpm add -g pic-rename-tool
```

## Usage

```bash
pic-rename
```

配置优先级：

1. `--config <path>`（最高）
2. 用户配置：`~/.config/pic-rename/config.yaml`（Windows 为 `%APPDATA%\pic-rename\config.yaml`）
3. 包内默认配置（兜底）

默认日志位置：`/tmp/pic-rename/rename_log.csv`

初始化用户配置：

```bash
pic-rename --init-config
```

常用参数：

```bash
pic-rename --path ./photos --config rename_config.yaml --dry-run
```

改名恢复（按日志回滚）：

```bash
pic-rename --path ./photos --undo-last --clear-log
```

- `--path`: 要处理的目录（默认当前目录）
- `--config`: 外部配置文件路径（相对路径默认基于 `--path`）
- `--init-config`: 写入用户配置
- `--force`: 配合 `--init-config` 覆盖已有配置
- `--undo-last`: 根据日志恢复上次改名
- `--log-file`: 指定恢复日志文件
- `--clear-log`: 清空日志（可配合 `--undo-last`）
- `--yes`: 跳过改名前确认
- `--dry-run`: 强制预览，不实际改名

## Gitea 推送示例

```bash
git remote add origin ssh://git@10.90.1.9:2222/<owner>/<repo>.git
git push -u origin main
```
