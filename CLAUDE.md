# Cilium Cluster Demo

A local Kubernetes cluster with Cilium CNI, Hubble observability, and a multi-version microservice demo.

## Stack
- **Cluster**: kind (Kubernetes in Docker)
- **CNI**: Cilium (eBPF-based, replaces kube-proxy)
- **Observability**: Hubble (built into Cilium)
- **Apps**: Python 3.11 / Flask

## Project Structure
```
cilium-cluster/
├── apps/
│   ├── frontend/      # Serves UI + proxies to backend
│   ├── backend/       # Forwards headers, calls downstream
│   └── downstream/    # Leaf service (v1 and v2)
├── k8s/
│   ├── namespace.yaml
│   ├── downstream.yaml   # downstream-v1 and downstream-v2 deployments + services
│   ├── backend.yaml      # backend-v1, backend-v2, and active "backend" service
│   ├── frontend.yaml     # NodePort 30080 → host 8080
│   └── cilium-policies.yaml  # CiliumNetworkPolicy — enforces version isolation
├── kind-config.yaml   # Kind cluster (no default CNI, no kube-proxy)
├── setup.sh           # Full setup: prereqs → cluster → Cilium → images → deploy
├── switch-v1.sh       # Patch backend service selector to v1
└── switch-v2.sh       # Patch backend service selector to v2
```

## Traffic Flow
```
Browser → Frontend (NodePort 30080) → backend service → Backend-v1 or v2 → Downstream-v1 or v2
```
CiliumNetworkPolicy enforces: backend-v1 may ONLY reach downstream-v1, and backend-v2 may ONLY reach downstream-v2.

## Setup
```bash
./setup.sh
```
Requires Docker to be running. Installs kind, kubectl, helm if not present.

## Access
| Service   | URL                   |
|-----------|-----------------------|
| Frontend  | http://localhost:8080 |
| Hubble UI | http://localhost:8888 |

In Hubble UI, select namespace **demo** to visualize traffic flows.

## Version Switching
```bash
./switch-v1.sh   # route traffic to backend-v1 → downstream-v1
./switch-v2.sh   # route traffic to backend-v2 → downstream-v2
```

## Verify Policy Enforcement
```bash
# These should be BLOCKED by Cilium (cross-version)
kubectl exec -n demo deploy/backend-v1 -- curl -s http://downstream-v2:8080/
kubectl exec -n demo deploy/backend-v2 -- curl -s http://downstream-v1:8080/

# These should SUCCEED
kubectl exec -n demo deploy/backend-v1 -- curl -s http://downstream-v1:8080/
kubectl exec -n demo deploy/backend-v2 -- curl -s http://downstream-v2:8080/
```

## Teardown
```bash
kind delete cluster --name cilium-cluster
```
