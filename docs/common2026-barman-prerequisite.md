# Barman plugin prerequisite (no database cutover)

## Scope and reconciliation order

This change installs the official CloudNativePG `plugin-barman-cloud` chart
**0.9.0**, application **v0.16.0**, into the existing `cloudnative-pg` namespace,
using the existing `cloudnative-pg` OCI HelmRepository. It does not change any
application chart, PostgreSQL image, Cluster, backup configuration, credentials,
or cache. Production clusters keep their existing backup mechanism. Installing
the plugin does not switch them to plugin-based archiving.

The ordering is:

1. `cert-manager` and `cloudnative-pg` Flux Kustomizations wait for their existing
   HelmReleases to become healthy (`wait: true`, `timeout: 35m`). Their release
   timeouts remain 30m; there are no operator upgrades in this change.
2. `plugin-barman-cloud` Kustomization depends on both and waits for its own
   HelmRelease (`timeout: 35m`, longer than the release's 30m timeout).
3. The plugin HelmRelease independently depends on both operator HelmReleases,
   installs the ObjectStore CRD, and requests client/server TLS certificates and
   an Issuer through cert-manager. The chart mounts both TLS Secrets and deploys
   the `barman-cloud` discovery Service in the CNPG operator namespace.
4. Stop after prerequisite verification. No production application Kustomization
   is gated on this plugin yet, and no production Cluster is modified.

These timeouts bound a reconciliation/action, not all remediation retries.
Readiness of a HelmRelease is not proof of an S3 backup, successful TLS discovery
by CNPG, or a restore. Those require the later isolated canary.

## Pre-merge verification (read-only or server dry-run)

Use a clean worktree based on the intended main revision. Never decrypt or apply
the full root render: it contains SOPS-managed objects and Flux substitutions.
Keep chart archives, rendered manifests, schemas, scripts, and evidence outside
Git in a private scratch directory. Do not commit recovery Jobs or temporary RBAC.

```sh
git diff --check
kubectl config current-context
kubectl --request-timeout=15s get --raw='/readyz?verbose'
kubectl --request-timeout=15s get nodes
kubectl --request-timeout=15s -n cert-manager get deployments
kubectl --request-timeout=15s -n cloudnative-pg get deployments
kubectl --request-timeout=15s -n flux-system get kustomizations cert-manager cloudnative-pg
kubectl --request-timeout=15s -n cert-manager get helmrelease cert-manager
kubectl --request-timeout=15s -n cloudnative-pg get helmrelease cloudnative-pg
```

Repeat bounded health observations over the owner-agreed recovery window. One
successful API response or two Ready nodes is not sustained health. Require
cert-manager, cainjector, webhook, and CNPG deployments available; investigate
unavailable controllers separately, not by adding recovery machinery here.

Fetch and render the exact chart with only the proposed plugin release values:

```sh
# EVIDENCE must name a private directory outside this repository.
helm pull oci://ghcr.io/cloudnative-pg/charts/plugin-barman-cloud \
  --version 0.9.0 --destination "$EVIDENCE"
# Extract spec.values from system/plugin-barman-cloud/app/helm-release.yaml
# into "$EVIDENCE/values.yaml" using a YAML parser (no credentials needed).
helm template plugin-barman-cloud "$EVIDENCE/plugin-barman-cloud-0.9.0.tgz" \
  --namespace cloudnative-pg --include-crds \
  --values "$EVIDENCE/values.yaml" > "$EVIDENCE/plugin-render.yaml"
sha256sum "$EVIDENCE/plugin-barman-cloud-0.9.0.tgz"
kubectl kustomize clusters/main/kubernetes/system/plugin-barman-cloud/app \
  > "$EVIDENCE/plugin-gitops.yaml"
```

Expected chart archive SHA-256:
`7fb78e89f25c18737e5649ae3c5e840065052f89757d541eaf310a1706ebd7dd`.
OCI manifest digest (different object):
`sha256:d34ada2eedffaee9153c6ae31e0e5b93fd28765cc8fba7c5fb45d4ed6b60df1a`.
The chart renders 12 objects: the ObjectStore CRD, plugin Deployment, discovery
Service, ServiceAccount, ConfigMap, chart RBAC, two Certificates, and one Issuer.
There must be no Cluster, ObjectStore instance, Backup, ScheduledBackup, PVC,
or Job. Both plugin and sidecar image references must be `v0.16.0`.

Validate all 12 rendered objects against Kubernetes/cert-manager/CRD schemas,
including the ObjectStore CRD's embedded OpenAPI schema. Validate the three
changed/new Flux Kustomizations and plugin HelmRelease against installed Flux
CRDs. Server-side dry-run those four GitOps objects and all 12 chart objects
individually; this must not install the CRD or create workloads:

```sh
kubectl --request-timeout=20s apply --dry-run=server \
  -f "$EVIDENCE/plugin-gitops.yaml"
kubectl --request-timeout=20s apply --dry-run=server \
  -f "$EVIDENCE/plugin-render.yaml"
# Also dry-run cert-manager/ks.yaml, cloudnative-pg/ks.yaml,
# and plugin-barman-cloud/ks.yaml from clusters/main/kubernetes/system.
```

Compare parsed root renders from the exact base and proposed tree by
`apiVersion/kind/namespace/name`, without printing secret bodies. Require only
one new root object (`flux-system/plugin-barman-cloud` Kustomization), and only
`wait: true` plus `timeout: 35m` changes on the existing cert-manager and CNPG
Kustomizations. All remaining root objects must be identical. Verify the entire
Flux dependency graph has no cycles or unresolved edges. Compare all tracked
file changes as well: the root render does not descend into each Flux app path.
Check encrypted files remain byte-identical; do not decrypt them for this test.

## After owner merge: prerequisite acceptance

Keep the PR draft until independent review and API-health clearance. Only the
owner merges; an agent must not merge or enable auto-merge. No live creation or
reconciliation is authorized by this runbook's preparation steps.

After the owner merges and stable API/controller health is established, observe
normal GitOps reconciliation. Require current-generation Ready=True conditions,
not stale readiness, on all three Kustomizations and HelmReleases. Confirm the
plugin HelmRelease used chart 0.9.0, then verify:

```sh
kubectl wait --for=condition=Established crd/objectstores.barmancloud.cnpg.io --timeout=2m
kubectl -n cloudnative-pg rollout status deployment/plugin-barman-cloud --timeout=5m
kubectl -n cloudnative-pg wait --for=condition=Ready \
  certificate/barman-cloud-client certificate/barman-cloud-server \
  issuer/plugin-barman-cloud-selfsigned-issuer --timeout=5m
kubectl -n cloudnative-pg get service barman-cloud
kubectl -n cloudnative-pg get endpointslices -l kubernetes.io/service-name=barman-cloud
```

Require a ready endpoint on port 9090, the Service label
`cnpg.io/pluginName=barman-cloud.cloudnative-pg.io`, and TLS Secret references
`barman-cloud-client-tls` / `barman-cloud-server-tls`. Do not print Secret data.
Verify CNPG still runs the intended operator image and every existing production
Cluster retains its original image and backup/plugin configuration. Record
non-secret evidence outside Git. Do not call this a proven backup migration.

## Later isolated canary gate (not created by this change)

Live canary creation still requires owner merge, sustained API health, and
explicit operational approval. Use a disposable namespace/Cluster, a compatible
pinned PostgreSQL image, and a unique S3 prefix **and server name** that cannot
collide with production or earlier tests. Never run retention/deletion tests
against a production prefix. Supply only scoped credentials through approved
memory-only authentication/import; no plaintext secret files, shell tracing,
command-line credential arguments, or secret-bearing logs/evidence.

A separate operational procedure must prove plugin discovery/TLS, base backup,
WAL archiving, restore into a second disposable cluster, and SQL data integrity
before any production backup switch is proposed. Keep production writers and
backup settings unchanged throughout this prerequisite. Stop on any failed
readiness, backup, or restore check. Clean up only isolated canary resources
under explicit approval. Never uninstall/prune the plugin or its CRD after any
consumer exists without a separately reviewed retention and rollback plan.
