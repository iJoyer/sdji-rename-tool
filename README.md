# Rename Tool

用于按配置批量规范化图片文件名的本地工具。

## Files

- `rename_by_config.py`: 主脚本，读取 YAML 规则并执行重命名。
- `rename_config.yaml`: 规则配置文件。
- `rename_log.csv`: 历史改名日志样例。

## Usage

```bash
python3 rename_by_config.py
```

运行前请先按需修改 `rename_config.yaml` 中的范围、规则与执行参数。
