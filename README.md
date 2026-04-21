# ACM Cluster Provisioning with GitOps

**Declarative OpenShift cluster provisioning at scale using RHACM 2.16 + OpenShift GitOps 1.20**

## Overview

This repository demonstrates a fully GitOps-driven approach to provisioning and managing OpenShift clusters using Red Hat Advanced Cluster Management (RHACM) and OpenShift GitOps (Argo CD). Every resource -- from cluster infrastructure to Day 2 operational configs -- is defined as declarative YAML in Git and automatically reconciled by Argo CD.

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full architecture overview.

```
Git Repo ──→ Argo CD (Hub) ──→ RHACM/Hive ──→ AWS (Spoke Clusters)
                 │                                      │
                 └── ApplicationSets ──────────────────→│
                     (Day 2 configs auto-deployed       │
                      based on ManagedCluster labels)   │
                                                        │
                 ←── Klusterlet agent reports back ─────┘
```

## Target Versions

| Component | Version |
|---|---|
| OpenShift Container Platform | 4.20 |
| Red Hat Advanced Cluster Management | 2.16 |
| OpenShift GitOps (Argo CD) | 1.20 |
| OpenShift Logging | 6.5 |
| Sealed Secrets | v0.36.5 |

## Prerequisites

- OpenShift 4.20 hub cluster (running and accessible)
- AWS account with IAM permissions for EC2, VPC, Route53, ELB, S3, IAM
- `oc` CLI installed and authenticated to the hub cluster
- `kubeseal` CLI installed (matching SealedSecrets v0.36.5)
- `kustomize` CLI (v5.4+)

## Quick Start

```bash
git clone https://github.com/YOUR_ORG/ACMClusterProvisioningWithGitOps.git
cd ACMClusterProvisioningWithGitOps

# Update repo URLs in applicationsets/*.yaml and app-of-apps/root-application.yaml

oc apply -k hub-setup/
# Wait for operators to install (~10 min)

oc apply -k app-of-apps/
```

## Repository Structure

```
.
├── app-of-apps/              # Root Argo CD Application (app-of-apps pattern)
│   └── root-application.yaml
├── applicationsets/           # ApplicationSets for Day 2 config delivery
│   ├── kustomization.yaml
│   └── day2-appset.yaml
├── clusters/
│   ├── base/                 # Base ClusterDeployment, InstallConfig, secrets
│   └── overlays/
│       ├── dev/              # Dev cluster overlay (patches + labels)
│       ├── staging/          # Staging cluster overlay
│       └── prod/             # Production cluster overlay
├── day2-config/              # Day 2 operational configurations
│   ├── logging/              # OpenShift Logging 6.5 (Vector + Loki)
│   └── rbac/                 # Cluster RBAC policies
├── hub-setup/                # Hub cluster operator subscriptions
│   ├── acm-subscription.yaml
│   ├── gitops-subscription.yaml
│   └── kustomization.yaml
├── docs/
│   ├── architecture.md       # Architecture deep-dive
│   └── demo-walkthrough.md   # Step-by-step demo guide
├── presentation/
│   └── deck.html             # HTML slide deck
└── README.md
```

## Demo

For a full step-by-step walkthrough, see [docs/demo-walkthrough.md](docs/demo-walkthrough.md).

For the presentation deck, open [presentation/deck.html](presentation/deck.html) in a browser.

## Key Concepts

### Label Taxonomy

ManagedCluster labels drive all targeting decisions:

| Label | Values | Purpose |
|---|---|---|
| `environment` | `dev`, `staging`, `prod` | Environment-based config targeting |
| `region` | `us-east-1`, `eu-west-1`, etc. | Region-specific configurations |
| `pci-compliant` | `true`, `false` | Compliance-driven policy enforcement |

### ApplicationSet Generators

This repo uses the **Cluster Decision Resource generator**, which reads PlacementDecision resources created by ACM's Placement controller. This is the recommended integration point between ACM and Argo CD -- it ensures Argo CD discovers clusters through ACM's label-based placement engine rather than maintaining a separate cluster list.

### Self-Healing

All ApplicationSets configure `syncPolicy.automated.selfHeal: true`. When a resource on a spoke cluster drifts from the desired state in Git, Argo CD automatically reverts the change. This provides continuous enforcement of the declared configuration.

## Author

**Christopher Bowland**
Associate Principal Specialist Solution Architect, Red Hat
