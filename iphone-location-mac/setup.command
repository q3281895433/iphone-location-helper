#!/bin/zsh
set -eu
task_dir="${0:A:h}"
task_python="${PYTHON:-python3}"
"$task_python" -c 'import sys; assert sys.version_info >= (3, 11), "Python 3.11 or newer is required"'
"$task_python" -m venv "$task_dir/.venv"
"$task_dir/.venv/bin/python3" -m pip install --prefer-binary --only-binary=cryptography -r "$task_dir/requirements.txt"
print "运行环境已准备好。接下来运行：$task_dir/build.command"
