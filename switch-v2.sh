#!/usr/bin/env bash
# Switch the active backend service to v2
set -euo pipefail

YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${YELLOW}[OK]${NC}    $*"; }

info "Switching 'backend' service selector to version=v2..."
kubectl patch service backend -n demo \
  --type='merge' \
  -p '{"spec":{"selector":{"app":"backend","version":"v2"}},"metadata":{"annotations":{"active-version":"v2"}}}'

success "backend service now points to backend-v2"
echo ""
echo "Traffic flow:"
echo "  Frontend → Backend v2 → Downstream v2"
echo ""
echo "Verify:"
echo "  curl -s http://localhost:8080/api/call | python3 -m json.tool"
