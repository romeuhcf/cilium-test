# Cilium Cluster Demo

A local Kubernetes environment that demonstrates eBPF-powered networking, traffic observability, and service mesh capabilities using [Cilium](https://cilium.io/) and [Hubble](https://github.com/cilium/hubble).

## Goals

- **eBPF-native Kubernetes cluster** — provision a local cluster (via kind) with Cilium as the CNI, replacing kube-proxy with an eBPF dataplane.
- **Multi-tier application** — deploy purpose-built frontend and backend services capable of forwarding HTTP headers end-to-end across the mesh.
- **Traffic observability** — enable Hubble to capture and visualize live traffic flows between services in real time.
- **Versioned backends with a shared downstream** — run two versions of the backend service (v1 and v2), each consuming a dedicated version of a shared downstream service (downstream-v1 / downstream-v2). Version affinity is enforced at the network layer by Cilium policy.
- **Zero-downtime version switching** — switch the active backend version (v1 ↔ v2) through Kubernetes service selector patching, surfaced as simple shell scripts. The downstream routing follows automatically without redeployment.
- **Replicable artifacts** — all cluster configuration, application source code, Kubernetes manifests, and operational scripts are committed to this repository so the environment can be reproduced from scratch on any compatible machine.

## Architecture

```
Browser
  └─► Frontend  (NodePort :8080)
        └─► backend service  (active version: v1 or v2)
              ├─► Backend-v1  ──► downstream-v1
              └─► Backend-v2  ──► downstream-v2
```

Cilium `CiliumNetworkPolicy` enforces version isolation: backend-v1 pods are permitted to reach downstream-v1 only, and backend-v2 pods are permitted to reach downstream-v2 only.

## Stack

| Component | Technology |
|-----------|-----------|
| Cluster | [kind](https://kind.sigs.k8s.io/) |
| CNI / Service mesh | [Cilium](https://cilium.io/) 1.15 |
| Observability | [Hubble](https://github.com/cilium/hubble) UI + Relay |
| Applications | Python 3.11 / Flask |

## Quickstart

```bash
./setup.sh
```

Requires Docker. Installs `kind`, `kubectl`, and `helm` if not already present.

| Service | URL |
|---------|-----|
| Frontend | http://localhost:8080 |
| Hubble UI | http://localhost:8888 |

In Hubble UI, select the **demo** namespace to watch live traffic flows.

## Switching Backend Versions

```bash
./switch-v1.sh   # route: Frontend → Backend-v1 → Downstream-v1
./switch-v2.sh   # route: Frontend → Backend-v2 → Downstream-v2
```

## Repository Layout

```
cilium-cluster/
├── apps/
│   ├── frontend/          # Web UI + reverse proxy to backend
│   ├── backend/           # Header-forwarding service, calls downstream
│   └── downstream/        # Leaf service (v1 and v2)
├── k8s/
│   ├── namespace.yaml
│   ├── downstream.yaml    # Downstream v1 & v2 deployments and services
│   ├── backend.yaml       # Backend v1, v2 deployments + active "backend" service
│   ├── frontend.yaml      # Frontend deployment + NodePort service
│   └── cilium-policies.yaml  # CiliumNetworkPolicy — enforces version isolation
├── kind-config.yaml       # Kind cluster definition (Cilium-ready)
├── setup.sh               # End-to-end setup script
├── switch-v1.sh           # Patch backend service selector → v1
└── switch-v2.sh           # Patch backend service selector → v2
```

## Teardown

```bash
kind delete cluster --name cilium-cluster
```
