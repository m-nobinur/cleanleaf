#!/bin/zsh
# Runs the frozen A/B/C evaluation on every fixture set that has labels.json.
# Usage: spike/detection/run_accuracy.sh   (writes reports next to the venv in .local/spikes/detection/)
set -u
L=/Users/nobin/Work/beenwise/cleanleaf/.local
PY=$L/venvs/detection/bin/python
MODEL=$L/models/docaligner/lc100_fp16_padzero.tflite
OUT=$L/spikes/detection
cd "${0:A:h}"
for set in detection detection-v0; do
  dir=$L/fixtures/$set
  if [[ ! -f $dir/labels.json ]]; then echo "skip $set: no labels.json"; continue; fi
  $PY evaluate.py $dir $MODEL --json $OUT/$set-results.json 2>&1 | grep -vE '^(W0|I0)|INFO: Created|RuntimeWarning|return rgb' | tee $OUT/$set-report.txt
done
