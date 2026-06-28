from __future__ import annotations

import copy
import importlib.resources as pkg_resources
import sys
from pathlib import Path
from typing import Any

from pic_rename_tool.cli import (
    apply_rename_plan,
    build_rename_plan,
    get_user_config_path,
    load_effective_config,
    resolve_config_path,
    resolve_log_path,
    undo_last,
    write_rename_log,
)

try:
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QCloseEvent, QFontDatabase
    from PySide6.QtWidgets import (
        QApplication,
        QCheckBox,
        QComboBox,
        QFileDialog,
        QFrame,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QMainWindow,
        QMessageBox,
        QPlainTextEdit,
        QPushButton,
        QSpinBox,
        QTableWidget,
        QTableWidgetItem,
        QTabWidget,
        QVBoxLayout,
        QWidget,
    )
except ImportError as exc:  # pragma: no cover - exercised by packaging/runtime only
    raise SystemExit("缺少 GUI 依赖，请先安装: pip install 'pic-rename-tool[gui]'") from exc


def _format_scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if not text or any(ch in text for ch in [":", "#", "[", "]", "{", "}", ","]):
        return repr(text)
    return text


def dump_simple_yaml(data: dict[str, Any], indent: int = 0) -> str:
    lines: list[str] = []
    prefix = " " * indent
    for key, value in data.items():
        if isinstance(value, dict):
            lines.append(f"{prefix}{key}:")
            lines.append(dump_simple_yaml(value, indent + 2))
        elif isinstance(value, list):
            lines.append(f"{prefix}{key}:")
            for item in value:
                lines.append(f"{prefix}  - {_format_scalar(item)}")
        else:
            lines.append(f"{prefix}{key}: {_format_scalar(value)}")
    return "\n".join(line for line in lines if line is not None)


def load_bundled_fonts() -> None:
    font_names = [
        "Oxanium-Regular.ttf",
        "Oxanium-SemiBold.ttf",
        "Oxanium-Bold.ttf",
    ]
    font_dir = pkg_resources.files("pic_rename_tool").joinpath("assets/fonts/Oxanium")
    for font_name in font_names:
        with pkg_resources.as_file(font_dir.joinpath(font_name)) as font_path:
            QFontDatabase.addApplicationFont(str(font_path))


class PicRenameWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("SDJI Rename Tool")
        self.resize(980, 680)
        self.setAcceptDrops(True)
        self.setObjectName("MainWindow")

        resolved_config_path, _source = resolve_config_path(None)
        self.config = load_effective_config(resolved_config_path)
        self.current_plan = []

        self.path_input = QLineEdit()
        self.path_input.setPlaceholderText("拖入图片文件夹，或点击选择...")
        self.path_input.textChanged.connect(self.preview)

        self.browse_button = QPushButton("选择文件夹")
        self.browse_button.clicked.connect(self.choose_folder)

        self.ext_input = QLineEdit()
        self.ext_input.setPlaceholderText("jpg, jpeg, png, dng...")
        self.ext_input.setText(", ".join(self._configured_extensions()))
        self.ext_input.textChanged.connect(self.preview)

        self.recursive_checkbox = QCheckBox("包含子文件夹")
        self.recursive_checkbox.setChecked(
            bool(self.config.get("scope", {}).get("recursive", True))
        )
        self.recursive_checkbox.stateChanged.connect(self.preview)

        dji_rules = self.config.get("dji_rules", {})

        self.dji_enabled_checkbox = QCheckBox("启用 DJI 规则")
        self.dji_enabled_checkbox.setChecked(bool(dji_rules.get("enabled", True)))
        self.dji_enabled_checkbox.stateChanged.connect(self.preview)

        self.prefix_input = QLineEdit()
        self.prefix_input.setText(str(dji_rules.get("starts_with", "DJI")))
        self.prefix_input.textChanged.connect(self.preview)

        self.remove_timestamp_checkbox = QCheckBox("删除前缀后的时间戳")
        self.remove_timestamp_checkbox.setChecked(
            bool(dji_rules.get("remove_middle_timestamp", True))
        )
        self.remove_timestamp_checkbox.stateChanged.connect(self.preview)

        self.timestamp_after_prefix_checkbox = QCheckBox("只删除紧跟前缀的时间戳")
        self.timestamp_after_prefix_checkbox.setChecked(
            bool(dji_rules.get("timestamp_must_follow_prefix", True))
        )
        self.timestamp_after_prefix_checkbox.stateChanged.connect(self.preview)

        self.remove_trailing_number_checkbox = QCheckBox("清理后删除末尾 -数字")
        self.remove_trailing_number_checkbox.setChecked(
            bool(dji_rules.get("remove_existing_trailing_dash_number", True))
        )
        self.remove_trailing_number_checkbox.stateChanged.connect(self.preview)

        self.keep_markers_edit = QPlainTextEdit()
        self.keep_markers_edit.setPlaceholderText("-T\n-L")
        self.keep_markers_edit.setPlainText(
            "\n".join(str(item) for item in dji_rules.get("keep_markers", []))
        )
        self.keep_markers_edit.textChanged.connect(self.preview)

        self.remove_markers_edit = QPlainTextEdit()
        self.remove_markers_edit.setPlaceholderText("_D\n-D\n-HDR")
        self.remove_markers_edit.setPlainText(
            "\n".join(str(item) for item in dji_rules.get("remove_markers", []))
        )
        self.remove_markers_edit.textChanged.connect(self.preview)

        conflict = self.config.get("conflict_resolution", {})
        self.conflict_strategy_combo = QComboBox()
        self.conflict_strategy_combo.addItem("追加编号（-2, -3...）", "append_dash_index")
        self.conflict_strategy_combo.addItem("追加括号编号（2）", "append_parentheses_index")
        self.conflict_strategy_combo.addItem("追加下划线编号（_2）", "append_underscore_index")
        self.conflict_strategy_combo.addItem("跳过冲突文件", "skip")
        strategy_index = self.conflict_strategy_combo.findData(
            str(conflict.get("strategy", "append_dash_index"))
        )
        self.conflict_strategy_combo.setCurrentIndex(max(0, strategy_index))
        self.conflict_strategy_combo.currentIndexChanged.connect(self.preview)
        self.conflict_strategy_combo.currentIndexChanged.connect(
            self._update_conflict_start_state
        )

        self.conflict_start_spin = QSpinBox()
        self.conflict_start_spin.setRange(2, 9999)
        self.conflict_start_spin.setValue(int(conflict.get("start_index", 2)))
        self.conflict_start_spin.valueChanged.connect(self.preview)
        self._update_conflict_start_state()

        self.preview_button = QPushButton("预览")
        self.preview_button.setProperty("variant", "secondary")
        self.preview_button.clicked.connect(self.preview)

        self.apply_button = QPushButton("应用改名")
        self.apply_button.setProperty("variant", "primary")
        self.apply_button.clicked.connect(self.apply_changes)

        self.undo_button = QPushButton("撤销上次")
        self.undo_button.setProperty("variant", "secondary")
        self.undo_button.clicked.connect(self.undo_changes)

        self.save_button = QPushButton("保存配置")
        self.save_button.setProperty("variant", "primary")
        self.save_button.clicked.connect(self.save_config)

        self.table = QTableWidget(0, 2)
        self.table.setHorizontalHeaderLabels(["原文件名", "新文件名"])
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.verticalHeader().setDefaultSectionSize(42)
        self.table.verticalHeader().setVisible(False)
        self.table.setAlternatingRowColors(True)
        self.table.setShowGrid(False)

        self.status = QLabel("未选择文件夹")
        self.status.setAlignment(Qt.AlignmentFlag.AlignLeft)
        self.status.setObjectName("StatusLabel")

        root = QWidget()
        root.setObjectName("Root")
        layout = QVBoxLayout(root)
        layout.setContentsMargins(24, 22, 24, 20)
        layout.setSpacing(14)

        header = QFrame()
        header.setObjectName("Header")
        header_layout = QVBoxLayout(header)
        header_layout.setContentsMargins(0, 0, 0, 4)
        title = QLabel("SDJI Rename Tool")
        title.setObjectName("TitleLabel")
        header_layout.addWidget(title)

        tabs = QTabWidget()
        tabs.setObjectName("Tabs")
        rename_tab = QWidget()
        rename_layout = QVBoxLayout(rename_tab)
        rename_layout.setContentsMargins(0, 14, 0, 0)
        rename_layout.setSpacing(14)
        rules_tab = QWidget()
        rules_layout = QVBoxLayout(rules_tab)
        rules_layout.setContentsMargins(0, 14, 0, 0)
        rules_layout.setSpacing(14)

        drop_card = self._make_card()
        drop_layout = QVBoxLayout(drop_card)
        drop_layout.setContentsMargins(18, 16, 18, 16)
        drop_layout.setSpacing(10)
        drop_title = QLabel("图片文件夹")
        drop_title.setObjectName("SectionTitle")

        path_row = QHBoxLayout()
        path_row.setSpacing(10)
        path_row.addWidget(self.path_input, 1)
        path_row.addWidget(self.browse_button)
        drop_layout.addWidget(drop_title)
        drop_layout.addLayout(path_row)

        option_card = self._make_card()
        option_layout = QVBoxLayout(option_card)
        option_layout.setContentsMargins(18, 16, 18, 16)
        option_layout.setSpacing(10)
        option_title = QLabel("扫描范围")
        option_title.setObjectName("SectionTitle")

        option_row = QHBoxLayout()
        option_row.setSpacing(10)
        option_row.addWidget(QLabel("文件格式"))
        option_row.addWidget(self.ext_input, 1)
        option_row.addWidget(self.recursive_checkbox)
        option_layout.addWidget(option_title)
        option_layout.addLayout(option_row)

        action_row = QHBoxLayout()
        action_row.setSpacing(10)
        action_row.addWidget(self.preview_button)
        action_row.addWidget(self.apply_button)
        action_row.addWidget(self.undo_button)
        action_row.addStretch(1)

        table_card = self._make_card()
        table_layout = QVBoxLayout(table_card)
        table_layout.setContentsMargins(12, 12, 12, 12)
        table_layout.addWidget(self.table)

        rename_layout.addWidget(drop_card)
        rename_layout.addWidget(option_card)
        rename_layout.addLayout(action_row)
        rename_layout.addWidget(table_card, 1)

        rules_top_card = self._make_card()
        rules_top_layout = QVBoxLayout(rules_top_card)
        rules_top_layout.setContentsMargins(18, 16, 18, 16)
        rules_top_layout.setSpacing(10)
        rules_top_title = QLabel("命名规则")
        rules_top_title.setObjectName("SectionTitle")

        prefix_row = QHBoxLayout()
        prefix_row.setSpacing(10)
        prefix_row.addWidget(QLabel("识别前缀"))
        prefix_row.addWidget(self.prefix_input, 1)

        conflict_row = QHBoxLayout()
        conflict_row.setSpacing(10)
        conflict_row.addWidget(QLabel("重复文件名"))
        conflict_row.addWidget(self.conflict_strategy_combo, 1)
        conflict_row.addWidget(QLabel("起始编号"))
        conflict_row.addWidget(self.conflict_start_spin)

        rules_top_layout.addWidget(rules_top_title)
        rules_top_layout.addWidget(self.dji_enabled_checkbox)
        rules_top_layout.addLayout(prefix_row)
        rules_top_layout.addWidget(self.remove_timestamp_checkbox)
        rules_top_layout.addWidget(self.timestamp_after_prefix_checkbox)
        rules_top_layout.addWidget(self.remove_trailing_number_checkbox)
        rules_top_layout.addLayout(conflict_row)

        marker_row = QHBoxLayout()
        marker_row.setSpacing(14)
        keep_card = self._make_card()
        keep_layout = QVBoxLayout(keep_card)
        keep_layout.setContentsMargins(18, 16, 18, 16)
        keep_title = QLabel("保留标记")
        keep_title.setObjectName("SectionTitle")
        keep_hint = QLabel("每行一个，例如 -T、-L")
        keep_hint.setObjectName("HintLabel")
        keep_layout.addWidget(keep_title)
        keep_layout.addWidget(keep_hint)
        keep_layout.addWidget(self.keep_markers_edit, 1)

        remove_card = self._make_card()
        remove_layout = QVBoxLayout(remove_card)
        remove_layout.setContentsMargins(18, 16, 18, 16)
        remove_title = QLabel("删除标记")
        remove_title.setObjectName("SectionTitle")
        remove_hint = QLabel("每行一个，例如 _D、-HDR")
        remove_hint.setObjectName("HintLabel")
        remove_layout.addWidget(remove_title)
        remove_layout.addWidget(remove_hint)
        remove_layout.addWidget(self.remove_markers_edit, 1)
        marker_row.addWidget(keep_card, 1)
        marker_row.addWidget(remove_card, 1)

        save_row = QHBoxLayout()
        save_row.addStretch(1)
        save_row.addWidget(self.save_button)

        rules_layout.addWidget(rules_top_card)
        rules_layout.addLayout(marker_row, 1)
        rules_layout.addLayout(save_row)

        tabs.addTab(rename_tab, "改名")
        tabs.addTab(rules_tab, "规则")

        layout.addWidget(header)
        layout.addWidget(tabs, 1)
        layout.addWidget(self.status)

        self.setCentralWidget(root)
        self._apply_style()

    def _make_card(self) -> QFrame:
        card = QFrame()
        card.setObjectName("GlassCard")
        card.setFrameShape(QFrame.Shape.NoFrame)
        return card

    def _apply_style(self) -> None:
        self.setStyleSheet(
            """
            #Root {
                background: qlineargradient(
                    x1: 0, y1: 0, x2: 1, y2: 1,
                    stop: 0 #f7f8fb,
                    stop: 0.55 #eef2f7,
                    stop: 1 #f7f7f9
                );
            }
            #TitleLabel {
                color: #111827;
                font-family: "Oxanium";
                font-size: 28px;
                font-weight: 700;
            }
            #StatusLabel, #HintLabel {
                color: #6b7280;
                font-size: 13px;
            }
            #SectionTitle {
                color: #111827;
                font-size: 13px;
                font-weight: 700;
            }
            #GlassCard {
                background-color: rgba(255, 255, 255, 188);
                border: 1px solid rgba(255, 255, 255, 210);
                border-radius: 18px;
            }
            QTabWidget::pane {
                border: 0;
                background: transparent;
            }
            QTabBar::tab {
                font-family: "Oxanium";
                min-width: 72px;
                padding: 8px 18px;
                margin-right: 6px;
                color: #4b5563;
                background: rgba(255, 255, 255, 120);
                border: 1px solid rgba(255, 255, 255, 160);
                border-radius: 13px;
            }
            QTabBar::tab:selected {
                color: #111827;
                background: rgba(255, 255, 255, 230);
            }
            QLabel {
                color: #374151;
                font-size: 13px;
            }
            QLineEdit, QComboBox, QSpinBox, QPlainTextEdit {
                color: #111827;
                background: rgba(255, 255, 255, 220);
                border: 1px solid rgba(209, 213, 219, 190);
                border-radius: 10px;
                padding: 8px 10px;
                selection-background-color: #0a84ff;
            }
            QPlainTextEdit {
                min-height: 118px;
                font-family: "SF Mono", Menlo, monospace;
                font-size: 13px;
            }
            QLineEdit:focus, QComboBox:focus, QSpinBox:focus, QPlainTextEdit:focus {
                border: 1px solid #0a84ff;
                background: rgba(255, 255, 255, 245);
            }
            QPushButton {
                font-family: "Oxanium";
                padding: 8px 16px;
                border-radius: 10px;
                font-weight: 600;
                min-height: 20px;
            }
            QPushButton[variant="primary"] {
                color: white;
                background: #0a84ff;
                border: 1px solid #0a84ff;
            }
            QPushButton[variant="primary"]:hover {
                background: #0071e3;
            }
            QPushButton[variant="secondary"], QPushButton {
                color: #111827;
                background: rgba(255, 255, 255, 210);
                border: 1px solid rgba(209, 213, 219, 190);
            }
            QPushButton[variant="secondary"]:hover {
                background: rgba(255, 255, 255, 245);
            }
            QCheckBox {
                color: #374151;
                spacing: 8px;
            }
            QTableWidget {
                background: transparent;
                alternate-background-color: rgba(248, 250, 252, 150);
                border: 0;
                color: #111827;
                gridline-color: transparent;
                selection-background-color: #0a84ff;
                selection-color: white;
            }
            QHeaderView::section {
                font-family: "Oxanium";
                color: #6b7280;
                background: transparent;
                border: 0;
                border-bottom: 1px solid rgba(209, 213, 219, 180);
                padding: 8px 10px;
                font-weight: 700;
            }
            QTableWidget::item {
                border-bottom: 1px solid rgba(229, 231, 235, 150);
                padding: 8px 10px;
            }
            """
        )

    def _update_conflict_start_state(self, *_args: object) -> None:
        strategy = self.conflict_strategy_combo.currentData()
        self.conflict_start_spin.setEnabled(strategy == "append_dash_index")

    def dragEnterEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        urls = event.mimeData().urls()
        if not urls:
            return
        path = Path(urls[0].toLocalFile())
        if path.is_file():
            path = path.parent
        self.path_input.setText(str(path))

    def closeEvent(self, event: QCloseEvent) -> None:
        event.accept()

    def choose_folder(self) -> None:
        folder = QFileDialog.getExistingDirectory(self, "选择图片文件夹", self.path_input.text())
        if folder:
            self.path_input.setText(folder)

    def preview(self, *_args: object) -> None:
        base_dir = self._base_dir()
        if base_dir is None:
            self._set_plan([])
            self.status.setText("未选择文件夹")
            return

        try:
            plan = build_rename_plan(base_dir=base_dir, config=self._current_config())
        except Exception as exc:  # noqa: BLE001
            self._set_plan([])
            self.status.setText(f"预览失败: {exc}")
            return

        self._set_plan(plan)
        self.status.setText(f"待处理 {len(plan)} 个文件。")

    def apply_changes(self) -> None:
        base_dir = self._base_dir()
        if base_dir is None:
            self.status.setText("请先选择文件夹。")
            return
        if not self.current_plan:
            self.preview()
        if not self.current_plan:
            self.status.setText("没有需要改名的文件。")
            return

        answer = QMessageBox.question(
            self,
            "确认改名",
            f"确认执行改名 {len(self.current_plan)} 个文件吗？",
        )
        if answer != QMessageBox.StandardButton.Yes:
            return

        config = self._current_config()
        if bool(config.get("execution", {}).get("create_rename_log", True)):
            log_path = resolve_log_path(base_dir, config, None)
            write_rename_log(base_dir=base_dir, log_path=log_path, plan=self.current_plan)

        try:
            apply_rename_plan(self.current_plan)
        except Exception as exc:  # noqa: BLE001
            self.status.setText(f"改名失败: {exc}")
            return

        changed = len(self.current_plan)
        self.preview()
        self.status.setText(f"改名完成: {changed} 个文件。")

    def undo_changes(self) -> None:
        base_dir = self._base_dir()
        if base_dir is None:
            self.status.setText("请先选择文件夹。")
            return

        answer = QMessageBox.question(self, "确认撤销", "按日志撤销上次改名吗？")
        if answer != QMessageBox.StandardButton.Yes:
            return

        config = self._current_config()
        log_path = resolve_log_path(base_dir, config, None)
        code = undo_last(base_dir=base_dir, log_path=log_path, dry_run=False, clear_log=False)
        self.preview()
        self.status.setText("撤销完成。" if code == 0 else "撤销失败，请检查日志。")

    def save_config(self) -> None:
        config = self._current_config()
        user_config_path = get_user_config_path()
        user_config_path.parent.mkdir(parents=True, exist_ok=True)
        user_config_path.write_text(dump_simple_yaml(config) + "\n", encoding="utf-8")
        self.config = config
        self.status.setText(f"已保存格式配置: {user_config_path}")

    def _configured_extensions(self) -> list[str]:
        file_types = self.config.get("file_types", {})
        return [str(ext) for ext in file_types.get("image_extensions", [])]

    def _current_extensions(self) -> list[str]:
        raw = self.ext_input.text().replace("，", ",")
        exts: list[str] = []
        for token in raw.split(","):
            ext = token.strip().lower().lstrip(".")
            if ext and ext not in exts:
                exts.append(ext)
        return exts

    def _current_marker_list(self, text: str) -> list[str]:
        markers: list[str] = []
        for raw in text.replace("，", "\n").replace(",", "\n").splitlines():
            marker = raw.strip()
            if marker and marker not in markers:
                markers.append(marker)
        return markers

    def _current_config(self) -> dict[str, Any]:
        config = copy.deepcopy(self.config)
        config.setdefault("scope", {})["recursive"] = self.recursive_checkbox.isChecked()
        config.setdefault("file_types", {})["image_extensions"] = self._current_extensions()
        dji_rules = config.setdefault("dji_rules", {})
        dji_rules["enabled"] = self.dji_enabled_checkbox.isChecked()
        dji_rules["starts_with"] = self.prefix_input.text().strip() or "DJI"
        dji_rules["remove_middle_timestamp"] = self.remove_timestamp_checkbox.isChecked()
        dji_rules["timestamp_must_follow_prefix"] = (
            self.timestamp_after_prefix_checkbox.isChecked()
        )
        dji_rules["remove_existing_trailing_dash_number"] = (
            self.remove_trailing_number_checkbox.isChecked()
        )
        dji_rules["keep_markers"] = self._current_marker_list(
            self.keep_markers_edit.toPlainText()
        )
        dji_rules["remove_markers"] = self._current_marker_list(
            self.remove_markers_edit.toPlainText()
        )
        conflict = config.setdefault("conflict_resolution", {})
        conflict["strategy"] = str(self.conflict_strategy_combo.currentData())
        conflict["start_index"] = self.conflict_start_spin.value()
        return config

    def _base_dir(self) -> Path | None:
        raw = self.path_input.text().strip()
        if not raw:
            return None
        path = Path(raw).expanduser()
        if not path.exists():
            return None
        if path.is_file():
            path = path.parent
        return path.resolve()

    def _set_plan(self, plan) -> None:  # type: ignore[no-untyped-def]
        self.current_plan = plan
        self.table.setRowCount(len(plan))
        base_dir = self._base_dir()
        for row, item in enumerate(plan):
            if base_dir is not None:
                source = str(item.source.relative_to(base_dir))
                target = str(item.target.relative_to(base_dir))
            else:
                source = str(item.source)
                target = str(item.target)
            self.table.setItem(row, 0, QTableWidgetItem(source))
            self.table.setItem(row, 1, QTableWidgetItem(target))
        self.table.resizeColumnsToContents()


def main() -> None:
    app = QApplication(sys.argv)
    load_bundled_fonts()
    window = PicRenameWindow()
    window.show()
    raise SystemExit(app.exec())


if __name__ == "__main__":
    main()
