#!/bin/bash
# =============================================================================
# ACM GitOps Troubleshooting Script
# Diagnoses "acm-placement configmap not found" and related issues
# Compatible with: macOS (requires oc or kubectl)
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Config ────────────────────────────────────────────────────────────────────
GITOPS_NS="${GITOPS_NS:-openshift-gitops}"
ACM_NS="${ACM_NS:-open-cluster-management}"
LOG_FILE="acm-gitops-troubleshoot-$(date +%Y%m%d-%H%M%S).log"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()    { echo -e "$*" | tee -a "$LOG_FILE"; }
header() { log "\n${BOLD}${BLUE}══════════════════════════════════════════════${NC}"; \
           log "${BOLD}${BLUE}  $*${NC}"; \
           log "${BOLD}${BLUE}══════════════════════════════════════════════${NC}"; }
ok()     { log "  ${GREEN}✔ $*${NC}"; }
warn()   { log "  ${YELLOW}⚠ $*${NC}"; }
fail()   { log "  ${RED}✘ $*${NC}"; }
info()   { log "  ${CYAN}ℹ $*${NC}"; }
run()    { log "\n  ${BOLD}$ $*${NC}"; eval "$*" 2>&1 | tee -a "$LOG_FILE" | sed 's/^/    /'; }

# ── Prerequisite: CLI tool ─────────────────────────────────────────────────────
check_cli() {
  header "1. CLI Tool Check"
  if command -v oc &>/dev/null; then
    ok "oc found: $(oc version --client 2>/dev/null | head -1)"
    CMD="oc"
  elif command -v kubectl &>/dev/null; then
    warn "oc not found — falling back to kubectl (some checks may be limited)"
    ok "kubectl found: $(kubectl version --client --short 2>/dev/null)"
    CMD="kubectl"
  else
    fail "Neither 'oc' nor 'kubectl' found on PATH."
    log "\n  Install options:"
    log "    brew install openshift-cli   # for oc"
    log "    brew install kubectl         # for kubectl"
    exit 1
  fi
}

# ── Cluster connectivity ───────────────────────────────────────────────────────
check_connectivity() {
  header "2. Cluster Connectivity"
  if $CMD cluster-info &>/dev/null; then
    ok "Connected to cluster"
    info "Server: $($CMD cluster-info 2>/dev/null | head -1 | sed 's/.*at //')"
    info "Current context: $($CMD config current-context 2>/dev/null)"
    info "Current user: $($CMD whoami 2>/dev/null || echo 'unknown')"
  else
    fail "Cannot reach cluster. Check your kubeconfig / VPN."
    exit 1
  fi
}

# ── ACM operator ──────────────────────────────────────────────────────────────
check_acm_operator() {
  header "3. ACM Operator"

  if $CMD get namespace "$ACM_NS" &>/dev/null; then
    ok "Namespace '$ACM_NS' exists"
  else
    fail "Namespace '$ACM_NS' not found — is ACM installed?"
    return
  fi

  local mch
  mch=$($CMD get multiclusterhub -n "$ACM_NS" --no-headers 2>/dev/null || true)
  if [[ -n "$mch" ]]; then
    ok "MultiClusterHub found"
    run "$CMD get multiclusterhub -n $ACM_NS"
    local phase
    phase=$($CMD get multiclusterhub -n "$ACM_NS" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$phase" == "Running" ]]; then
      ok "MultiClusterHub phase: $phase"
    else
      warn "MultiClusterHub phase: $phase (expected: Running)"
    fi
  else
    fail "No MultiClusterHub found in '$ACM_NS'"
  fi

  log "\n  ${BOLD}ACM Pods:${NC}"
  run "$CMD get pods -n $ACM_NS --no-headers | grep -v Running | grep -v Completed || echo '  All pods Running/Completed'"
}

# ── OpenShift GitOps operator ──────────────────────────────────────────────────
check_gitops_operator() {
  header "4. OpenShift GitOps Operator"

  if $CMD get namespace "$GITOPS_NS" &>/dev/null; then
    ok "Namespace '$GITOPS_NS' exists"
  else
    fail "Namespace '$GITOPS_NS' not found — is OpenShift GitOps installed?"
    return
  fi

  local pods_not_ready
  pods_not_ready=$($CMD get pods -n "$GITOPS_NS" --no-headers 2>/dev/null | grep -v Running | grep -v Completed | grep -v Terminating || true)
  if [[ -z "$pods_not_ready" ]]; then
    ok "All GitOps pods are Running"
  else
    warn "Some GitOps pods are not Running:"
    log "$pods_not_ready" | sed 's/^/    /'
  fi

  run "$CMD get pods -n $GITOPS_NS"
}

# ── The acm-placement ConfigMap (the main error) ───────────────────────────────
check_acm_placement_configmap() {
  header "5. acm-placement ConfigMap  ← Root cause check"

  if $CMD get configmap acm-placement -n "$GITOPS_NS" &>/dev/null; then
    ok "ConfigMap 'acm-placement' EXISTS in '$GITOPS_NS'"
    run "$CMD get configmap acm-placement -n $GITOPS_NS -o yaml"
  else
    fail "ConfigMap 'acm-placement' NOT FOUND in '$GITOPS_NS'"
    warn "This is the root cause of your degraded ApplicationSet."
    info "ACM creates this ConfigMap automatically once the full prerequisite"
    info "chain is in place: ManagedClusterSet → ManagedClusterSetBinding"
    info "→ Placement → GitOpsCluster  (all in namespace: $GITOPS_NS)"
  fi
}

# ── ManagedClusterSets ─────────────────────────────────────────────────────────
check_managedclustersets() {
  header "6. ManagedClusterSets (cluster-scoped)"

  local sets
  sets=$($CMD get managedclusterset --no-headers 2>/dev/null || true)
  if [[ -n "$sets" ]]; then
    ok "ManagedClusterSets found:"
    run "$CMD get managedclusterset"
  else
    fail "No ManagedClusterSets found"
    info "Create one and add your managed clusters to it."
  fi
}

# ── ManagedClusterSetBindings ──────────────────────────────────────────────────
check_managedclustersetbindings() {
  header "7. ManagedClusterSetBindings in '$GITOPS_NS'"

  local bindings
  bindings=$($CMD get managedclustersetbinding -n "$GITOPS_NS" --no-headers 2>/dev/null || true)
  if [[ -n "$bindings" ]]; then
    ok "ManagedClusterSetBinding(s) found in '$GITOPS_NS':"
    run "$CMD get managedclustersetbinding -n $GITOPS_NS"

    # Validate that the bound clusterSets actually exist
    local bound_sets
    bound_sets=$($CMD get managedclustersetbinding -n "$GITOPS_NS" \
      -o jsonpath='{.items[*].spec.clusterSet}' 2>/dev/null || true)
    for cs in $bound_sets; do
      if $CMD get managedclusterset "$cs" &>/dev/null; then
        ok "Bound clusterSet '$cs' exists"
      else
        fail "Bound clusterSet '$cs' does NOT exist — binding is broken"
      fi
    done
  else
    fail "No ManagedClusterSetBinding found in '$GITOPS_NS'"
    warn "Fix: apply a ManagedClusterSetBinding pointing to your ManagedClusterSet"
    log "\n  Example:"
    log "    apiVersion: cluster.open-cluster-management.io/v1beta2"
    log "    kind: ManagedClusterSetBinding"
    log "    metadata:"
    log "      name: <YOUR_CLUSTERSET_NAME>"
    log "      namespace: $GITOPS_NS"
    log "    spec:"
    log "      clusterSet: <YOUR_CLUSTERSET_NAME>"
  fi
}

# ── Placements ────────────────────────────────────────────────────────────────
check_placements() {
  header "8. Placements in '$GITOPS_NS'"

  local placements
  placements=$($CMD get placement -n "$GITOPS_NS" --no-headers 2>/dev/null || true)
  if [[ -n "$placements" ]]; then
    ok "Placement(s) found in '$GITOPS_NS':"
    run "$CMD get placement -n $GITOPS_NS"

    # Check placement decisions
    local decisions
    decisions=$($CMD get placementdecision -n "$GITOPS_NS" --no-headers 2>/dev/null || true)
    if [[ -n "$decisions" ]]; then
      ok "PlacementDecision(s) exist (clusters are being selected):"
      run "$CMD get placementdecision -n $GITOPS_NS"
    else
      warn "No PlacementDecisions found — no clusters match the Placement predicates"
      info "Check that your managed clusters have the expected labels (e.g. vendor=OpenShift)"
    fi
  else
    fail "No Placement found in '$GITOPS_NS'"
    warn "Fix: create a Placement in namespace '$GITOPS_NS'"
    log "\n  Example:"
    log "    apiVersion: cluster.open-cluster-management.io/v1beta1"
    log "    kind: Placement"
    log "    metadata:"
    log "      name: acm-gitops-placement"
    log "      namespace: $GITOPS_NS"
    log "    spec:"
    log "      predicates:"
    log "        - requiredClusterSelector:"
    log "            labelSelector:"
    log "              matchExpressions:"
    log "                - key: vendor"
    log "                  operator: In"
    log "                  values:"
    log "                    - OpenShift"
  fi
}

# ── GitOpsCluster ─────────────────────────────────────────────────────────────
check_gitopscluster() {
  header "9. GitOpsCluster in '$GITOPS_NS'"

  local clusters
  clusters=$($CMD get gitopscluster -n "$GITOPS_NS" --no-headers 2>/dev/null || true)
  if [[ -n "$clusters" ]]; then
    ok "GitOpsCluster(s) found:"
    run "$CMD get gitopscluster -n $GITOPS_NS"

    # Check status
    local status
    status=$($CMD get gitopscluster -n "$GITOPS_NS" \
      -o jsonpath='{.items[0].status.conditions[?(@.type=="Conditions")].message}' 2>/dev/null || true)
    run "$CMD get gitopscluster -n $GITOPS_NS -o yaml"

    # Verify the placementRef points to an existing Placement
    local placement_ref
    placement_ref=$($CMD get gitopscluster -n "$GITOPS_NS" \
      -o jsonpath='{.items[0].spec.placementRef.name}' 2>/dev/null || true)
    if [[ -n "$placement_ref" ]]; then
      if $CMD get placement "$placement_ref" -n "$GITOPS_NS" &>/dev/null; then
        ok "placementRef '$placement_ref' exists"
      else
        fail "placementRef '$placement_ref' NOT FOUND in '$GITOPS_NS'"
      fi
    fi
  else
    fail "No GitOpsCluster found in '$GITOPS_NS'"
    warn "Fix: create a GitOpsCluster resource"
    log "\n  Example:"
    log "    apiVersion: apps.open-cluster-management.io/v1beta1"
    log "    kind: GitOpsCluster"
    log "    metadata:"
    log "      name: argo-acm-clusters"
    log "      namespace: $GITOPS_NS"
    log "    spec:"
    log "      argoServer:"
    log "        cluster: local-cluster"
    log "        argoNamespace: $GITOPS_NS"
    log "      placementRef:"
    log "        kind: Placement"
    log "        apiVersion: cluster.open-cluster-management.io/v1beta1"
    log "        name: acm-gitops-placement"
    log "        namespace: $GITOPS_NS"
  fi
}

# ── Managed clusters ──────────────────────────────────────────────────────────
check_managed_clusters() {
  header "10. Managed Clusters"

  local clusters
  clusters=$($CMD get managedcluster --no-headers 2>/dev/null || true)
  if [[ -n "$clusters" ]]; then
    ok "Managed cluster(s) found:"
    run "$CMD get managedcluster"

    # Warn if none are available/joined
    local available
    available=$($CMD get managedcluster --no-headers 2>/dev/null | grep -c "True" || true)
    if [[ "$available" -gt 0 ]]; then
      ok "$available cluster(s) are Available"
    else
      warn "No clusters show as Available — check cluster import status"
    fi
  else
    warn "No ManagedClusters found"
  fi
}

# ── ArgoCD ApplicationSets ────────────────────────────────────────────────────
check_applicationsets() {
  header "11. ArgoCD ApplicationSets in '$GITOPS_NS'"

  local appsets
  appsets=$($CMD get applicationset -n "$GITOPS_NS" --no-headers 2>/dev/null || true)
  if [[ -n "$appsets" ]]; then
    ok "ApplicationSet(s) found:"
    run "$CMD get applicationset -n $GITOPS_NS"

    # Show status/conditions for each
    local names
    names=$($CMD get applicationset -n "$GITOPS_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    for name in $names; do
      log "\n  ${BOLD}ApplicationSet: $name${NC}"
      local conditions
      conditions=$($CMD get applicationset "$name" -n "$GITOPS_NS" \
        -o jsonpath='{.status.conditions}' 2>/dev/null || true)
      if [[ -n "$conditions" ]]; then
        log "    Conditions: $conditions"
      fi
    done
  else
    warn "No ApplicationSets found in '$GITOPS_NS'"
  fi
}

# ── ArgoCD Applications ───────────────────────────────────────────────────────
check_applications() {
  header "12. ArgoCD Applications (degraded/error only)"

  local degraded
  degraded=$($CMD get application -n "$GITOPS_NS" --no-headers 2>/dev/null | \
    grep -iE "Degraded|Error|Unknown" || true)
  if [[ -n "$degraded" ]]; then
    warn "Degraded/Error applications:"
    log "$degraded" | sed 's/^/    /'
  else
    ok "No degraded applications found"
  fi
}

# ── Cluster secrets in openshift-gitops ──────────────────────────────────────
check_cluster_secrets() {
  header "13. Cluster Secrets in '$GITOPS_NS' (created by GitOpsCluster)"

  local secrets
  secrets=$($CMD get secret -n "$GITOPS_NS" \
    -l "apps.open-cluster-management.io/acm-cluster=true" \
    --no-headers 2>/dev/null || \
    $CMD get secret -n "$GITOPS_NS" --no-headers 2>/dev/null | \
    grep "cluster-secret" || true)

  if [[ -n "$secrets" ]]; then
    ok "Cluster secret(s) found (ACM → ArgoCD registration succeeded):"
    log "$secrets" | sed 's/^/    /'
  else
    warn "No cluster secrets found — ACM has not yet registered clusters with ArgoCD"
    info "This will be created automatically once GitOpsCluster reconciles successfully"
  fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  header "SUMMARY & NEXT STEPS"

  local cm_ok=false plc_ok=false binding_ok=false gitops_ok=false

  $CMD get configmap acm-placement -n "$GITOPS_NS" &>/dev/null && cm_ok=true
  $CMD get placement -n "$GITOPS_NS" --no-headers &>/dev/null && \
    [[ -n "$($CMD get placement -n "$GITOPS_NS" --no-headers 2>/dev/null)" ]] && plc_ok=true
  $CMD get managedclustersetbinding -n "$GITOPS_NS" --no-headers &>/dev/null && \
    [[ -n "$($CMD get managedclustersetbinding -n "$GITOPS_NS" --no-headers 2>/dev/null)" ]] && binding_ok=true
  $CMD get gitopscluster -n "$GITOPS_NS" --no-headers &>/dev/null && \
    [[ -n "$($CMD get gitopscluster -n "$GITOPS_NS" --no-headers 2>/dev/null)" ]] && gitops_ok=true

  log ""
  $binding_ok && ok "ManagedClusterSetBinding ✔" || fail "ManagedClusterSetBinding ✘  ← apply 1-managedclustersetbinding.yaml"
  $plc_ok      && ok "Placement               ✔" || fail "Placement               ✘  ← apply 2-placement.yaml"
  $gitops_ok   && ok "GitOpsCluster           ✔" || fail "GitOpsCluster           ✘  ← apply 3-gitopscluster.yaml"
  $cm_ok       && ok "acm-placement ConfigMap ✔" || fail "acm-placement ConfigMap ✘  ← will appear after above 3 are fixed"

  if $cm_ok; then
    log "\n  ${GREEN}${BOLD}Prerequisites are satisfied. If ArgoCD is still degraded:${NC}"
    info "Hard-refresh the ApplicationSet in ArgoCD UI, or run:"
    info "  oc rollout restart deployment/openshift-gitops-applicationset-controller -n $GITOPS_NS"
  fi

  log "\n  Full log saved to: ${BOLD}$LOG_FILE${NC}\n"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  log "${BOLD}${CYAN}"
  log "╔══════════════════════════════════════════════════════╗"
  log "║   ACM GitOps Troubleshooter — $(date '+%Y-%m-%d %H:%M:%S')    ║"
  log "╚══════════════════════════════════════════════════════╝"
  log "${NC}"
  log "  GitOps namespace : $GITOPS_NS"
  log "  ACM namespace    : $ACM_NS"
  log "  Log file         : $LOG_FILE"

  check_cli
  check_connectivity
  check_acm_operator
  check_gitops_operator
  check_acm_placement_configmap
  check_managedclustersets
  check_managedclustersetbindings
  check_placements
  check_gitopscluster
  check_managed_clusters
  check_applicationsets
  check_applications
  check_cluster_secrets
  print_summary
}

main "$@"
