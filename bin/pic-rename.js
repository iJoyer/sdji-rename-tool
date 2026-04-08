#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const path = require("node:path");

const packageRoot = path.resolve(__dirname, "..");
const args = process.argv.slice(2);

function runWithPython(pythonBin) {
  const env = { ...process.env };
  env.PYTHONPATH = env.PYTHONPATH
    ? `${packageRoot}${path.delimiter}${env.PYTHONPATH}`
    : packageRoot;

  return spawnSync(pythonBin, ["-m", "pic_rename_tool", ...args], {
    stdio: "inherit",
    env,
  });
}

const candidates = ["python3", "python"];
for (const pythonBin of candidates) {
  const probe = spawnSync(pythonBin, ["--version"], { stdio: "ignore" });
  if (probe.status !== 0) {
    continue;
  }

  const result = runWithPython(pythonBin);
  if (typeof result.status === "number") {
    process.exit(result.status);
  }
}

console.error("pic-rename 需要 Python 3.9+，请先安装 python3。");
process.exit(1);
