#!/usr/bin/env bash
set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR]${NC}   $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="cilium-cluster"
CILIUM_VERSION="1.15.6"

# ── WSL2 notice ──────────────────────────────────────────────────────────────
if grep -qi microsoft /proc/version 2>/dev/null; then
  warn "WSL2 detected — eBPF datapath works; some advanced XDP features may not."
fi

# ── Prerequisite checkers ────────────────────────────────────────────────────
need_docker() {
  if ! command -v docker &>/dev/null; then
    error "Docker not found. Install Docker Desktop (WSL2) or 'sudo apt install docker.io && sudo usermod -aG docker \$USER'"
  fi
  if ! docker info &>/dev/null; then
    error "Docker daemon is not running. Start Docker Desktop or 'sudo service docker start'"
  fi
  success "Docker is available"
}

install_kind() {
  if command -v kind &>/dev/null; then
    success "kind already installed: $(kind version)"
    return
  fi
  info "Installing kind..."
  local url="https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64"
  curl -fsSL "$url" -o /tmp/kind
  chmod +x /tmp/kind
  sudo mv /tmp/kind /usr/local/bin/kind
  success "kind installed"
}

install_kubectl() {
  if command -v kubectl &>/dev/null; then
    success "kubectl already installed"
    return
  fi
  info "Installing kubectl..."
  local stable
  stable=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  curl -fsSL "https://dl.k8s.io/release/${stable}/bin/linux/amd64/kubectl" -o /tmp/kubectl
  chmod +x /tmp/kubectl
  sudo mv /tmp/kubectl /usr/local/bin/kubectl
  success "kubectl installed"
}

install_helm() {
  if command -v helm &>/dev/null; then
    success "helm already installed: $(helm version --short)"
    return
  fi
  info "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  success "helm installed"
}

# ── Cluster ──────────────────────────────────────────────────────────────────
create_cluster() {
  if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    warn "Cluster '${CLUSTER_NAME}' already exists — skipping creation"
  else
    info "Creating kind cluster '${CLUSTER_NAME}'..."
    kind create cluster --config "${SCRIPT_DIR}/kind-config.yaml"
    success "Cluster created"
  fi
  kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null
}

# ── Cilium ───────────────────────────────────────────────────────────────────
install_cilium() {
  if ! helm repo list 2>/dev/null | grep -q "^cilium"; then
    info "Adding cilium Helm repo..."
    helm repo add cilium https://helm.cilium.io/
    helm repo update
  fi

  # Get the control-plane container IP (used for kubeProxyReplacement)
  local api_ip
  api_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
           "${CLUSTER_NAME}-control-plane")
  info "API server IP: ${api_ip}"

  if helm status cilium -n kube-system &>/dev/null; then
    info "Cilium already installed — upgrading to ensure settings are current..."
    local helm_cmd="upgrade"
  else
    local helm_cmd="install"
  fi

  info "Running helm ${helm_cmd} for Cilium ${CILIUM_VERSION}..."
  helm "${helm_cmd}" cilium cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --namespace kube-system \
    --set image.pullPolicy=IfNotPresent \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost="${api_ip}" \
    --set k8sServicePort=6443 \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set hubble.ui.service.type=NodePort \
    --set hubble.ui.service.nodePort=30888 \
    --wait --timeout 5m

  info "Waiting for Cilium pods to be Ready..."
  kubectl wait --for=condition=ready pod \
    -l k8s-app=cilium \
    -n kube-system \
    --timeout=120s
  success "Cilium + Hubble installed"
}

# ── Images ───────────────────────────────────────────────────────────────────
build_and_load() {
  local apps=("frontend" "backend" "downstream")
  info "Building Docker images..."
  for app in "${apps[@]}"; do
    docker build -t "demo/${app}:latest" "${SCRIPT_DIR}/apps/${app}/"
    success "Built demo/${app}:latest"
  done

  info "Loading images into kind cluster..."
  for app in "${apps[@]}"; do
    kind load docker-image "demo/${app}:latest" --name "${CLUSTER_NAME}"
    success "Loaded demo/${app}:latest"
  done
}

# ── Deploy ───────────────────────────────────────────────────────────────────
deploy_apps() {
  info "Deploying applications..."
  kubectl apply -f "${SCRIPT_DIR}/k8s/namespace.yaml"
  kubectl apply -f "${SCRIPT_DIR}/k8s/downstream.yaml"
  kubectl apply -f "${SCRIPT_DIR}/k8s/backend.yaml"
  kubectl apply -f "${SCRIPT_DIR}/k8s/frontend.yaml"
  kubectl apply -f "${SCRIPT_DIR}/k8s/cilium-policies.yaml"

  info "Waiting for pods to become Ready (this may take ~60 s)..."
  for label in "app=downstream" "app=backend" "app=frontend"; do
    kubectl wait --for=condition=ready pod \
      -l "${label}" -n demo \
      --timeout=120s
  done
  success "All application pods are Ready"
}

# ── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Setup complete!${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
  echo ""
  echo "  Frontend (demo app):  http://localhost:8080"
  echo "  Hubble UI:            http://localhost:8888"
  echo ""
  echo "  In Hubble UI → select namespace 'demo' to watch traffic."
  echo ""
  echo "  Switch active backend version:"
  echo "    ./switch-v1.sh   (backend → v1, downstream → v1)"
  echo "    ./switch-v2.sh   (backend → v2, downstream → v2)"
  echo ""
  echo "  Verify Cilium policies are enforced:"
  echo "    kubectl exec -n demo deploy/backend-v1 -- curl -s http://downstream-v2:8080/  # blocked"
  echo "    kubectl exec -n demo deploy/backend-v2 -- curl -s http://downstream-v1:8080/  # blocked"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  need_docker
  install_kind
  install_kubectl
  install_helm
  create_cluster
  install_cilium
  build_and_load
  deploy_apps
  print_summary
}

main "$@"
