#!/bin/bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/lib/ui.sh
source "$REPO_DIR/scripts/lib/ui.sh"

for code in 200 301 302 307 308 401 403; do
    assert_ok "$code answers" http_status_answers "$code"
done
for code in 000 404 500 ""; do
    assert_fails "'$code' does not answer" http_status_answers "$code"
done

finish
