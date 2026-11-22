#!/bin/sh
# Runs the headless self-tests (jobs, weapons, vehicles, secrets) on every installed world.
cd "$(dirname "$0")/.." || exit 1
found=0
fail=0
for m in data/*.bin; do
  [ -f "$m" ] || continue
  found=1
  out=$(PAVE_MAP=$m ./pave --selftest 2>&1; PAVE_MAP=$m ./pave --secretstest 2>&1)
  good=$(echo "$out" | grep -cE 'passed=TRUE|^ok')
  bad=$(echo "$out" | grep -cE 'passed=FALSE|^FAIL|raised')
  echo "$m: $good checks passed, $bad failed"
  [ "$bad" -eq 0 ] || { echo "$out" | grep -E 'passed=FALSE|^FAIL|raised'; fail=1; }
done
if [ "$found" -eq 0 ]; then
  echo "No world installed yet - download one first, e.g.: make map-small"
  exit 1
fi
exit $fail
