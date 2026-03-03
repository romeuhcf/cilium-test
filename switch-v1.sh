#!/usr/bin/env bash
# Switch the active backend service to v1
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }

info "Switching 'backend' service selector to version=v1..."
kubectl patch service backend -n demo \
  --type='merge' \
  -p '{"spec":{"selector":{"app":"backend","version":"v1"}},"metadata":{"annotations":{"active-version":"v1"}}}'

success "backend service now points to backend-v1"
echo ""
echo "Traffic flow:"
echo "  Frontend → Backend v1 → Downstream v1"
echo ""
echo "Verify:"
echo "  curl -s http://localhost:8080/api/call | python3 -m json.tool"
