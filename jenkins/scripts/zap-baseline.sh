#!/bin/sh
# Runs INSIDE the ZAP container (started by the Jenkinsfile). $WORKSPACE is passed in with -e.
# ZAP reads its config and writes its report under /zap/wrk, so copy the rules in and the report out.
set -u
mkdir -p /zap/wrk
cp -r "$WORKSPACE/.zap" /zap/wrk/
zap-baseline.py -t "$ZAP_TARGET" -c .zap/rules.tsv -a -I -r zap-report.html
rc=$?
cp /zap/wrk/zap-report.html "$WORKSPACE/reports/" 2>/dev/null || true
exit $rc
