#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="SDJI Rename Tool"
ACTION_NAME="SDJI Rename Tool Export Action"
APP_EXECUTABLE="${1:-}"

if [ -z "$APP_EXECUTABLE" ]; then
  if [ -x "dist-swift/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]; then
    APP_EXECUTABLE="$(pwd)/dist-swift/$APP_NAME.app/Contents/MacOS/$APP_NAME"
  elif [ -x "/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]; then
    APP_EXECUTABLE="/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME"
  else
    echo "未找到 $APP_NAME.app，请先运行 swift/SDJIRenameTool/build_app.sh" >&2
    exit 1
  fi
fi

if [ ! -x "$APP_EXECUTABLE" ]; then
  echo "app 执行文件不可用: $APP_EXECUTABLE" >&2
  exit 1
fi

EXPORT_ACTIONS_DIR="$HOME/Library/Application Support/Adobe/Lightroom/Export Actions"
mkdir -p "$EXPORT_ACTIONS_DIR"

TMP_SCRIPT="$(mktemp -t sdji-lightroom-export-action.XXXXXX.applescript)"
trap 'rm -f "$TMP_SCRIPT"' EXIT

cat > "$TMP_SCRIPT" <<APPLESCRIPT
on open exportedFiles
    set fileArgs to ""
    repeat with exportedFile in exportedFiles
        set fileArgs to fileArgs & " " & quoted form of POSIX path of exportedFile
    end repeat

    do shell script quoted form of "$APP_EXECUTABLE" & " --lightroom-export" & fileArgs
end open

on run
    do shell script quoted form of "$APP_EXECUTABLE" & " --help"
end run
APPLESCRIPT

osacompile -o "$EXPORT_ACTIONS_DIR/$ACTION_NAME.app" "$TMP_SCRIPT"

echo "Installed: $EXPORT_ACTIONS_DIR/$ACTION_NAME.app"
