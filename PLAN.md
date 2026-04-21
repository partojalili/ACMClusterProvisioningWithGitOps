# ACM Cluster Provisioning with GitOps - Demo Plan

## Context

Build a customer-facing demo showing end-to-end OpenShift cluster provisioning via GitOps using RHACM + OpenShift GitOps (Argo CD) on AWS. The demo covers all 4 phases: Hub setup, Git repo structure, Day 1 provisioning, and Day 2 configuration via ApplicationSets. Includes a Red Hat-branded HTML slide deck.

### Target Versions

| Component | Version | OLM Channel |
|-----------|---------|-------------|
| OpenShift Container Platform | **4.20** (EUS) | -- |
| Red Hat ACM | **2.16** (includes MCE 2.11) | `release-2.16` |
| OpenShift GitOps | **1.20** | `latest` (or `gitops-1.20` to pin) |
| OpenShift Logging | **6.5** | `stable-6.5` |
| Loki Operator | **6.5** | `stable-6.5` |
| Sealed Secrets (Bitnami) | **v0.36.5** | -- (direct manifest) |
| ClusterImageSet | `img4.20.0-x86-64-appsub` | -- |

> **Note on Logging 6.x**: This is a major architecture shift from 5.x. Elasticsearch is replaced by Loki (via the Loki Operator), Kibana is replaced by the Cluster Observability Operator UIPlugin, and Vector is the only supported collector. The Loki Operator must be installed alongside the Logging operator.

---

## Directory Structure

```
ACMClusterProvisioningWithGitOps/
├── README.md
├── .gitignore
├── .github/workflows/validate-manifests.yaml
├── docs/
│   ├── architecture.md
│   └── demo-walkthrough.md
├── presentation/
│   └── deck.html
├── hub-setup/
│   ├── kustomization.yaml
│   ├── namespaces.yaml
│   ├── acm-operator/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── operator-group.yaml
│   │   ├── subscription.yaml
│   │   └── multiclusterhub.yaml
│   ├── openshift-gitops-operator/
│   │   ├── kustomization.yaml
│   │   ├── subscription.yaml
│   │   └── argocd.yaml
│   ├── acm-gitops-integration/
│   │   ├── kustomization.yaml
│   │   ├── gitops-cluster-role.yaml
│   │   ├── gitops-cluster-rolebinding.yaml
│   │   ├── managed-cluster-set.yaml
│   │   ├── managed-cluster-set-binding.yaml
│   │   └── placement.yaml
│   └── sealed-secrets/
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       └── sealed-secrets-controller.yaml
├── clusters/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── cluster-deployment.yaml
│   │   ├── machine-pool.yaml
│   │   ├── managed-cluster.yaml
│   │   ├── klusterlet-addon-config.yaml
│   │   ├── install-config-secret.yaml
│   │   ├── pull-secret.yaml
│   │   ├── ssh-private-key-secret.yaml
│   │   └── aws-credentials-secret.yaml
│   └── overlays/
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   ├── cluster-deployment-patch.yaml
│       │   ├── machine-pool-patch.yaml
│       │   ├── managed-cluster-patch.yaml
│       │   ├── klusterlet-addon-config-patch.yaml
│       │   └── install-config-secret-patch.yaml
│       └── prod/
│           ├── kustomization.yaml
│           ├── cluster-deployment-patch.yaml
│           ├── machine-pool-patch.yaml
│           ├── managed-cluster-patch.yaml
│           ├── klusterlet-addon-config-patch.yaml
│           └── install-config-secret-patch.yaml
├── day2-config/
│   ├── logging/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── operator-group.yaml
│   │   ├── subscription.yaml
│   │   ├── loki-operator-namespace.yaml
│   │   ├── loki-operator-subscription.yaml
│   │   ├── lokistack.yaml
│   │   └── cluster-log-forwarder.yaml
│   ├── network-policies/
│   │   ├── kustomization.yaml
│   │   ├── deny-all-default.yaml
│   │   ├── allow-dns.yaml
│   │   ├── allow-ingress-controller.yaml
│   │   └── allow-monitoring.yaml
│   └── rbac/
│       ├── kustomization.yaml
│       ├── cluster-admin-group.yaml
│       ├── developer-role.yaml
│       ├── developer-rolebinding.yaml
│       ├── sre-clusterrole.yaml
│       └── sre-clusterrolebinding.yaml
├── applicationsets/
│   ├── kustomization.yaml
│   ├── cluster-provisioning-appset.yaml
│   ├── day2-logging-appset.yaml
│   ├── day2-network-policies-appset.yaml
│   └── day2-rbac-appset.yaml
└── app-of-apps/
    ├── kustomization.yaml
    └── root-application.yaml
```

**Total: ~71 files**

---

## Implementation Steps

### Step 1: Repository Foundation

| File | Description |
|------|-------------|
| `.gitignore` | Ignore `*.secret.yaml`, `*.key`, `.DS_Store`, `kubeconfig`, IDE files |
| `README.md` | Project overview, architecture diagram, prerequisites (OCP 4.20, RHACM 2.16, AWS account, oc CLI, kubeseal), full demo walkthrough, cleanup instructions |

---

### Step 2: Hub Cluster Setup (Phase 1) -- 19 files

#### ACM Operator (`hub-setup/acm-operator/`)

| File | Description |
|------|-------------|
| `namespace.yaml` | Namespace `open-cluster-management` |
| `operator-group.yaml` | OperatorGroup targeting own namespace |
| `subscription.yaml` | OLM Subscription for `advanced-cluster-management` from `redhat-operators`, channel `release-2.16`, installPlanApproval `Automatic` |
| `multiclusterhub.yaml` | MultiClusterHub CR with `availabilityConfig: High` |
| `kustomization.yaml` | References all above files |

#### OpenShift GitOps Operator (`hub-setup/openshift-gitops-operator/`)

| File | Description |
|------|-------------|
| `subscription.yaml` | OLM Subscription for `openshift-gitops-operator`, channel `latest` (or `gitops-1.20` to pin), installPlanApproval `Automatic`. Install namespace: `openshift-gitops-operator` (default since v1.10+) |
| `argocd.yaml` | ArgoCD CR: route enabled, ApplicationSet enabled, RBAC for cluster-admins group, resource health checks for ACM CRDs (`ClusterDeployment`, `ManagedCluster`) |
| `kustomization.yaml` | References above files |

#### ACM-GitOps Integration (`hub-setup/acm-gitops-integration/`) -- Critical Glue

| File | Description |
|------|-------------|
| `gitops-cluster-role.yaml` | ClusterRole granting Argo CD SA read access to `ManagedCluster`, `ManagedClusterSet`, `Placement`, `PlacementDecision` |
| `gitops-cluster-rolebinding.yaml` | ClusterRoleBinding for `openshift-gitops-argocd-application-controller` SA |
| `managed-cluster-set.yaml` | ManagedClusterSet named `gitops-clusters` |
| `managed-cluster-set-binding.yaml` | ManagedClusterSetBinding in `openshift-gitops` namespace, binding `gitops-clusters` set |
| `placement.yaml` | Placement CR in `openshift-gitops` namespace selecting clusters from `gitops-clusters` set by label `vendor: OpenShift` |
| `kustomization.yaml` | References all above files |

#### Sealed Secrets (`hub-setup/sealed-secrets/`)

| File | Description |
|------|-------------|
| `namespace.yaml` | Namespace `sealed-secrets` |
| `sealed-secrets-controller.yaml` | Bitnami SealedSecrets v0.36.5 controller Deployment, Service, RBAC. Comment block explains External Secrets Operator alternative for production |
| `kustomization.yaml` | References above files |

#### Top-level Hub

| File | Description |
|------|-------------|
| `hub-setup/namespaces.yaml` | Creates namespaces: `open-cluster-management`, `openshift-gitops`, `sealed-secrets` |
| `hub-setup/kustomization.yaml` | References all subdirectories |

---

### Step 3: Cluster Provisioning Base (Phase 3 -- Day 1) -- 9 files

All files in `clusters/base/`. Secrets use `REPLACE_ME` placeholders with comments directing to SealedSecrets.

| File | Description |
|------|-------------|
| `cluster-deployment.yaml` | Hive ClusterDeployment: `baseDomain: example.com`, `platform.aws.region: us-east-1`, refs to credential secrets, `imageSetRef: img4.20.0-x86-64-appsub` |
| `machine-pool.yaml` | MachinePool: `platform.aws.type: m5.xlarge`, `replicas: 3`, `rootVolume: gp3/120GB` |
| `managed-cluster.yaml` | ManagedCluster: labels `cloud: Amazon`, `vendor: OpenShift`, `environment: base`, `region: us-east-1`, `hubAcceptsClient: true` |
| `klusterlet-addon-config.yaml` | KlusterletAddonConfig: enables applicationManager, policyController, searchCollector, certPolicyController, iamPolicyController |
| `install-config-secret.yaml` | Secret with `install-config.yaml`: 3 control plane `m5.2xlarge`, 3 compute `m5.xlarge`, OVNKubernetes networking, cluster/service network CIDRs |
| `pull-secret.yaml` | Secret type `kubernetes.io/dockerconfigjson` with placeholder. Comment: "Replace with pull secret from cloud.redhat.com" |
| `ssh-private-key-secret.yaml` | Secret with `ssh-privatekey` placeholder |
| `aws-credentials-secret.yaml` | Secret with `aws_access_key_id` and `aws_secret_access_key` as `stringData`, `REPLACE_ME` values |
| `kustomization.yaml` | References all above, applies `commonLabels: managed-by: gitops` |

---

### Step 4: Cluster Overlays -- Dev & Prod -- 12 files

Strategic merge patches for readability. Each overlay in `clusters/overlays/{dev,prod}/`.

| | Dev | Prod |
|---|---|---|
| Cluster name | `dev-cluster` | `prod-cluster` |
| Region | `us-east-1` | `us-west-2` |
| Base domain | `dev.example.com` | `prod.example.com` |
| Worker instance | `m5.xlarge` | `m5.2xlarge` |
| Worker replicas | 2 | 5 (autoscale 3-8) |
| Control plane | `m5.2xlarge` | `m5.4xlarge` |
| PCI compliant | `false` | `true` |

Each overlay contains:

| File | Description |
|------|-------------|
| `kustomization.yaml` | Base ref `../../base`, namePrefix, commonLabels (`environment: dev/prod`), patch refs |
| `cluster-deployment-patch.yaml` | Patch: cluster name, base domain, AWS region |
| `machine-pool-patch.yaml` | Patch: instance type, replica count, autoscaling (prod) |
| `managed-cluster-patch.yaml` | Patch: cluster name, environment/region/pci-compliant labels |
| `klusterlet-addon-config-patch.yaml` | Patch: cluster name reference |
| `install-config-secret-patch.yaml` | Patch: dev/prod-specific install-config values |

---

### Step 5: Day 2 Configurations (Phase 4) -- 17 files

#### Logging (`day2-config/logging/`) -- Logging 6.5 Architecture

Logging 6.x replaces Elasticsearch with Loki and uses ClusterLogForwarder as the primary CR (ClusterLogging CR is deprecated). Requires both the Logging Operator and the Loki Operator.

| File | Description |
|------|-------------|
| `namespace.yaml` | Namespace `openshift-logging` |
| `operator-group.yaml` | OperatorGroup in `openshift-logging` |
| `subscription.yaml` | OLM Subscription for `cluster-logging`, channel `stable-6.5` |
| `loki-operator-namespace.yaml` | Namespace `openshift-operators-redhat` (required for Loki Operator) |
| `loki-operator-subscription.yaml` | OLM Subscription for `loki-operator` in `openshift-operators-redhat`, channel `stable-6.5` |
| `lokistack.yaml` | LokiStack CR: S3-backed storage (AWS), `1x.demo` size for dev / `1x.medium` for prod, retention 7 days app / 14 days infra |
| `cluster-log-forwarder.yaml` | ClusterLogForwarder CR (replaces ClusterLogging in 6.x): Vector collector, forwards application/infrastructure/audit logs to LokiStack |
| `kustomization.yaml` | References all above |

#### Network Policies (`day2-config/network-policies/`)

| File | Description |
|------|-------------|
| `deny-all-default.yaml` | NetworkPolicy denying all ingress/egress by default |
| `allow-dns.yaml` | NetworkPolicy allowing egress to kube-dns (UDP/TCP 53) |
| `allow-ingress-controller.yaml` | NetworkPolicy allowing ingress from `openshift-ingress` namespace |
| `allow-monitoring.yaml` | NetworkPolicy allowing ingress from `openshift-monitoring` for Prometheus scraping (ports 8443, 8080) |
| `kustomization.yaml` | References all above |

#### RBAC (`day2-config/rbac/`)

| File | Description |
|------|-------------|
| `cluster-admin-group.yaml` | Group `cluster-admins` with placeholder users |
| `developer-role.yaml` | ClusterRole `developer`: get/list/watch most resources, CRUD on Deployments/Services/ConfigMaps/Secrets/Routes |
| `developer-rolebinding.yaml` | ClusterRoleBinding binding `developer` to `developers` group |
| `sre-clusterrole.yaml` | ClusterRole `sre-operations`: nodes (get/list/cordon/drain), pods (get/list/delete/exec), events, logs, PVs |
| `sre-clusterrolebinding.yaml` | ClusterRoleBinding binding `sre-operations` to `sre-team` group |
| `kustomization.yaml` | References all above |

---

### Step 6: ApplicationSets & App of Apps -- 7 files

Two generator types to demonstrate breadth:

| File | Generator Type | Description |
|------|---------------|-------------|
| `applicationsets/cluster-provisioning-appset.yaml` | **Git directory** | Points to `clusters/overlays/*`, creates an Application per directory. Destination: Hub cluster (Hive runs on Hub). `selfHeal: true`, `prune: true`, `CreateNamespace=true` |
| `applicationsets/day2-logging-appset.yaml` | **Cluster Decision Resource** | Uses ACM Placement, targets all managed clusters. Source: `day2-config/logging`. Destination namespace: `openshift-logging`. `requeueAfterSeconds: 180` |
| `applicationsets/day2-network-policies-appset.yaml` | **Cluster Decision Resource** | Same generator, additional label filter `pci-compliant: "true"`. Source: `day2-config/network-policies` |
| `applicationsets/day2-rbac-appset.yaml` | **Cluster Decision Resource** | Same generator, no additional label filter (all clusters). Source: `day2-config/rbac` |
| `applicationsets/kustomization.yaml` | -- | References all above |
| `app-of-apps/root-application.yaml` | -- | Bootstrap Argo CD Application: source path `applicationsets/`, destination Hub cluster, `selfHeal: true`, `prune: true`. This is the single manifest applied manually to start the entire flow |
| `app-of-apps/kustomization.yaml` | -- | References above |

---

### Step 7: CI Pipeline -- 1 file

`.github/workflows/validate-manifests.yaml` -- GitHub Actions on PRs:
1. Install `kustomize` v5.x and `kube-linter` v0.6+
2. `kustomize build` on each overlay and day2-config directory
3. `kube-linter lint` on rendered output
4. `yamllint` for YAML syntax
5. Fail PR if any step fails

---

### Step 8: Documentation -- 2 files

| File | Description |
|------|-------------|
| `docs/architecture.md` | Hub-and-Spoke model, Hive provisioning flow, ACM-GitOps integration loop, ApplicationSet generator patterns, label-driven Day 2 targeting |
| `docs/demo-walkthrough.md` | Step-by-step presenter script: pre-demo checklist, commands per phase, expected outcomes to show audience, talking points, troubleshooting tips |

---

### Step 9: Presentation Deck -- 1 file

`presentation/deck.html` -- Red Hat-branded HTML slide deck (via `red-hat-quick-deck` skill):
- Architecture overview (Hub + Spoke + GitOps loop)
- Phase-by-phase walkthrough with diagrams
- Live demo transition slides
- Best practices summary
- Next steps / call to action

---

## Key Design Decisions

1. **Kustomize over Helm** -- strategic merge patches are more readable for demos and align with Red Hat docs
2. **Two ApplicationSet generator types** -- Git directory generator (Day 1) + Cluster Decision Resource generator (Day 2) shows real-world versatility
3. **ManagedCluster label taxonomy** -- `environment`, `region`, `pci-compliant`, `vendor`, `cloud` -- these labels drive all Day 2 targeting and are the "aha moment" of the demo
4. **Placeholder secrets** -- `REPLACE_ME` values with comments directing to SealedSecrets; never commit real credentials
5. **selfHeal: true everywhere** -- drift remediation is both a best practice and a powerful live demo moment

---

## Infrastructure Requirements

The demo requires **2 OpenShift clusters** on AWS:

| Cluster | Role | Control Plane | Workers | Region | Est. Cost |
|---------|------|--------------|---------|--------|-----------|
| Hub | RHACM 2.16 + GitOps 1.20 | 3x m5.2xlarge | 3x m5.2xlarge | us-east-1 | ~$2,500/mo |
| Dev Spoke | Provisioned by demo | 3x m5.2xlarge | 2x m5.xlarge | us-east-1 | ~$1,500/mo |

The **prod overlay remains in the repo** as a reference artifact to show the base/overlay pattern (different region, instance sizes, PCI labels) but is **not provisioned** during the demo.

**AWS prerequisites per cluster:** VPC with public/private subnets across 3 AZs, ELBs (API + Ingress), Route53 hosted zone, S3 bucket (for Loki), IAM user/role with EC2/ELB/Route53/S3/VPC permissions, EBS volumes (gp3, 120 GB/worker).

---

## Demo Flow for Presenter

1. **Show the Git repo structure** -- explain the separation of concerns
2. **Apply hub-setup** -- `oc apply -k hub-setup/` (pre-install for live demos; ACM takes ~10 min)
3. **Walk through a ClusterDeployment** -- show base + overlay pattern, contrast dev vs prod overlays
4. **Merge a PR adding `clusters/overlays/dev/`** -- Argo CD syncs, Hive provisions (~30-45 min on AWS)
5. **Show ManagedCluster labels** -- explain how they drive Day 2 targeting
6. **Show ApplicationSets auto-detecting the new cluster** -- Day 2 configs deploy automatically
7. **Demo drift remediation** -- manually change something on managed cluster, watch Argo CD revert it

> **Tip**: Pre-provision the dev spoke cluster before the live demo. Show the PR merge + Argo CD sync in real time, then switch to the pre-provisioned cluster for Day 2 content. The prod overlay is shown as YAML only -- no need to provision it.

---

## Verification Checklist

- [ ] `kustomize build clusters/overlays/dev` renders cleanly
- [ ] `kustomize build clusters/overlays/prod` renders cleanly
- [ ] `kustomize build day2-config/logging` renders cleanly
- [ ] `kustomize build day2-config/network-policies` renders cleanly
- [ ] `kustomize build day2-config/rbac` renders cleanly
- [ ] `kustomize build applicationsets` renders cleanly
- [ ] `presentation/deck.html` opens and renders correctly in browser
- [ ] `oc apply -k hub-setup/` creates all expected resources on Hub cluster
- [ ] ApplicationSets appear in Argo CD UI after applying root app
