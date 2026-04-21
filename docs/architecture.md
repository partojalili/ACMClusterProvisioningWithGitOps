# Architecture Overview

## Hub-and-Spoke Model

The hub cluster runs RHACM 2.16 (which includes MCE 2.11) and OpenShift GitOps 1.20 (Argo CD). All cluster lifecycle management and policy enforcement originates from this single hub. Spoke clusters are provisioned on AWS using the Installer-Provisioned Infrastructure (IPI) method and are automatically imported back into ACM as ManagedClusters.

## How Provisioning Works

The Hive operator, deployed by ACM, watches for ClusterDeployment custom resources. When a ClusterDeployment CR is created (via Argo CD syncing from this Git repo), Hive:

1. Reads the InstallConfig, platform credentials, and pull secret from referenced Secrets.
2. Launches a provisioning pod that runs the OpenShift installer against AWS.
3. Creates VPCs, subnets, load balancers, EC2 instances, Route53 records, and bootstraps the cluster.
4. Imports the new cluster as a ManagedCluster and installs the Klusterlet agent.

End-to-end provisioning takes **30-45 minutes**.

## ACM-GitOps Integration

ACM and Argo CD are integrated through three resources:

| Resource | Purpose |
|---|---|
| **ManagedClusterSet** | Groups clusters logically (e.g., by environment or region) |
| **ManagedClusterSetBinding** | Grants a namespace (e.g., `openshift-gitops`) access to the cluster set |
| **Placement** | Selects clusters from the set using label-based predicates |

The Placement resource produces PlacementDecisions, which Argo CD's ApplicationSet controller reads via the Cluster Decision Resource generator.

## Day 2 via ApplicationSets

ApplicationSets use the **Cluster Decision Resource generator** to discover spoke clusters dynamically:

- The generator reads PlacementDecisions created by ACM's Placement controller.
- Labels on ManagedCluster resources (`environment`, `region`, `pci-compliant`) drive targeting.
- Each ApplicationSet template produces one Argo CD Application per matched cluster.
- `syncPolicy.automated.selfHeal: true` ensures drift is reverted automatically.

This means adding a new cluster with the right labels automatically triggers Day 2 config deployment -- no manual Application creation needed.

## Secrets Management

Two supported approaches:

1. **SealedSecrets v0.36.5** -- Encrypt secrets client-side with `kubeseal`. Only the SealedSecrets controller on the hub can decrypt. Encrypted SealedSecret resources are safe to commit to Git.
2. **External Secrets Operator** -- Syncs secrets from AWS Secrets Manager or HashiCorp Vault into Kubernetes Secrets at runtime. Preferred for production.

Cloud credentials and pull secrets must never be committed in plaintext.

## Logging 6.5

OpenShift Logging 6.5 replaces the legacy Elasticsearch-based stack:

- **Loki** replaces Elasticsearch as the log store.
- **Vector** is the only supported collector (Fluentd is removed).
- **ClusterLogForwarder** is now the primary CR (replaces the old ClusterLogging CR).

The Day 2 logging configuration in this repo deploys Vector + ClusterLogForwarder to forward logs to a Loki instance.

## Architecture Diagram

```
Git Repo ──→ Argo CD (Hub) ──→ RHACM/Hive ──→ AWS (Spoke Clusters)
                 │                                      │
                 └── ApplicationSets ──────────────────→│
                     (Day 2 configs auto-deployed       │
                      based on ManagedCluster labels)   │
                                                        │
                 ←── Klusterlet agent reports back ─────┘
```
