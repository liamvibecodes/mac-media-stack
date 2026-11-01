#!/bin/bash
# Runs every tests/test_*.sh in its own shell. Usage: bash tests/run.sh
set -u
cd "$(dirname "$0")" || exit 1
status=0
for t in test_*.sh; do
    bash "$t" || status=1
done
if [[ $status -eq 0 ]]; then echo "All tests passed."; else echo "Some tests failed."; fi
exit $status
