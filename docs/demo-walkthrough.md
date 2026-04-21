# Demo Walkthrough

## 1. Prerequisites

- **OpenShift Container Platform 4.20** hub cluster (running and accessible)
- **RHACM 2.16** operator available in OperatorHub
- **oc** CLI installed and authenticated to the hub cluster
- **kubeseal** CLI installed (matching SealedSecrets v0.36.5)
- **AWS account** with IAM permissions for EC2, VPC, Route53, ELB, S3, IAM
- **Route53 hosted zone** for your base domain (e.g., `demo.example.com`)
- This Git repo forked/cloned to your own GitHub org

## 2. Pre-Demo Setup

Complete these steps **before** the live demo (they take time):

### Fork and configure the repo

```bash
git clone https://github.com/YOUR_ORG/ACMClusterProvisioningWithGitOps.git
cd ACMClusterProvisioningWithGitOps
```

Update all Git repo URLs in:
- `applicationsets/*.yaml`
- `app-of-apps/root-application.yaml`

### Install hub operators

```bash
oc apply -k hub-setup/
# Wait ~10 minutes for ACM and GitOps operators to install
oc get csv -n open-cluster-management
oc get csv -n openshift-gitops
```

### Seal secrets

```bash
# Fetch the SealedSecrets public cert from the hub
kubeseal --fetch-cert --controller-namespace sealed-secrets > pub-cert.pem

# Seal your AWS credentials
kubeseal --format yaml --cert pub-cert.pem \
  < clusters/base/aws-creds.secret.yaml \
  > clusters/base/aws-creds-sealed.yaml

# Seal the pull secret
kubeseal --format yaml --cert pub-cert.pem \
  < clusters/base/pull-secret.secret.yaml \
  > clusters/base/pull-secret-sealed.yaml
```

### Pre-provision the dev cluster

```bash
oc apply -k clusters/overlays/dev/
# This takes 30-45 minutes -- start it well before the demo
oc get clusterdeployment -n dev-cluster -w
```

## 3. Demo Flow

### Step 1: Show Git repo structure

Walk through the directory layout. Emphasize that everything is declarative YAML managed in Git -- no ClickOps.

### Step 2: Walk through ClusterDeployment

Show `clusters/base/` and explain the base ClusterDeployment, InstallConfig, and secret references. Then show `clusters/overlays/dev/` and how Kustomize patches the base for a dev environment (instance types, worker count, labels).

### Step 3: Show Argo CD UI

Open the Argo CD console on the hub. Show the root Application (app-of-apps) and its children. Highlight sync status and health.

### Step 4: Show ACM console

Open the RHACM console. Navigate to the ManagedCluster list. Show the dev cluster with its labels:
- `environment: dev`
- `region: us-east-1`
- `vendor: OpenShift`

### Step 5: Show ApplicationSets auto-detecting the cluster

In Argo CD, show the ApplicationSets. Explain how the Cluster Decision Resource generator discovered the dev cluster via Placement/PlacementDecision. Show that Day 2 Applications were automatically created.

### Step 6: Show Day 2 configs deployed

On the spoke cluster, verify Day 2 configs:

```bash
# RBAC
oc get clusterrolebinding -l managed-by=gitops

# Logging
oc get clusterlogforwarder -n openshift-logging
oc get pods -n openshift-logging
```

### Step 7: Demo drift remediation

Manually edit a resource on the spoke to simulate drift:

```bash
oc edit clusterrolebinding demo-admins-binding
# Change a field or remove a subject
```

Watch Argo CD detect the drift and revert it (within the sync interval, typically 3 minutes). Show the diff in the Argo CD UI before it self-heals.

## 4. Cleanup

```bash
# Delete the cluster (Hive will deprovision AWS resources)
oc delete -k clusters/overlays/dev/
# Or let Argo CD prune if the overlay is removed from Git

# Wait for Hive to fully deprovision (~15 minutes)
oc get clusterdeployment -n dev-cluster -w

# Remove hub operators (optional)
oc delete -k hub-setup/
```

## 5. Troubleshooting

### ClusterDeployment stuck provisioning

```bash
oc get clusterdeployment -n dev-cluster -o yaml
# Check .status.conditions for errors
oc get pods -n dev-cluster
# Look at the provisioning pod logs
oc logs -n dev-cluster -l hive.openshift.io/cluster-deployment-name=dev-cluster
```

Common causes: invalid AWS credentials, insufficient IAM permissions, Route53 zone mismatch, quota limits.

### ApplicationSet not targeting a cluster

```bash
# Verify the Placement is selecting the cluster
oc get placement -n openshift-gitops -o yaml
oc get placementdecisions -n openshift-gitops -o yaml
# Check that ManagedCluster labels match the Placement predicates
oc get managedcluster dev-cluster -o yaml | grep -A 20 labels
```

### Secrets issues

```bash
# Verify SealedSecrets controller is running
oc get pods -n sealed-secrets
oc get sealedsecrets -A
# Check for decryption errors in the controller logs
oc logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
```
