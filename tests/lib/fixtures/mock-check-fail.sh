#!/usr/bin/env sh
printf '{"check_id":"mock-fail","title":"Mock Fail","category":"secrets","status":"FAIL","severity":"high","evidence":[{"type":"file","path":"/tmp/x","detail":"found","redacted":false}],"remediation":{"description":"fix","argv":["echo"],"risk":"safe"}}\n'
