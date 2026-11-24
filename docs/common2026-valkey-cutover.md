# Common-2026 Valkey cutover: preparation only

**This document does not authorize a cutover.** This preparation change contains no
HelmRelease, chart version, Flux dependency, Secret, Job, or RBAC changes. Merging
it cannot start a new Valkey or change an application's running version. Do not
merge/deploy the common-2026 application migration as a single active-app revision.
The current baseline has all three applications active, not `global.stopAll: true`.

## Scope and prerequisites

Rehearsed against repository base `7fe43a15f4cd8ea3c628ee135c49592f4dbad10d`:

| Release / namespace | Old chart | Target chart | Old cache / retained PVC | Target StatefulSet / PVC |
|---|---|---|---|---|
| blocky | 24.3.2 | 25.0.0 | blocky-redis / blocky-redis-data | blocky-valkey-main / blocky-valkey-data |
| immich | 35.7.7 | 36.0.0 | immich-redis / immich-redis-data | immich-valkey-main / immich-valkey-data |
| nextcloud | 49.2.11 | 50.0.0 | nextcloud-redis / nextcloud-redis-data | nextcloud-valkey-main / nextcloud-valkey-data |

Old charts call the dependency `redis`, although the source server is Valkey 9.1.3.
The exact target image in all three rendered charts is:

```text
oci.trueforge.org/containerforge/valkey:9.0.4@sha256:ae7fe6bf2d849a671056ceb99a6ba5ed183c2aaf00e0da70a0821d373b643ff8
```

Target data root is **`/config`**, RDB is **`/config/dump.rdb`**, runtime
UID:GID **568:568**, pod fsGroup **568**, append-only persistence defaults to **yes**.
The old `/bitnami/valkey` mount/layout must not be mounted in place as `/config`.
All three cache PVCs render `ReadWriteOnce`, `100Gi`, with `storageClassName`
**omitted**. Their effective class therefore depends on the cluster default;
read-only preflight observed exactly one default, **longhorn** (`driver.longhorn.io`),
and each existing `*-redis-data` PVC Bound on longhorn at 100Gi. Recheck this and
the **actual new claim** before writing data; stop if the default has changed.
Do not describe a defaulted class as an explicitly pinned rendered field.

Before any later rollout:

- Obtain separate approval and a maintenance window; Blocky loses its DNS service
  while writers are held. Confirm an independent DNS/API/GitOps management path.
- Finish the separately reviewed Barman plugin prerequisite first: cert-manager,
  CNPG and the pinned plugin must be Ready, including the ObjectStore CRD and
  appropriate application Flux dependency ordering. That prerequisite is not added here.
- Rebase/re-render the actual future staged revisions. Proposed target base values
  used here come from the existing common-2026 migration worktree, not a new active
  chart bump in this preparation branch. Preserve its CNPG bridge, backup identity,
  Secret references, schema fixes, and legacy-PVC `extraTpl` retention.
- Inventory live release values, all namespace pods/jobs, external clients, backup
  controllers and direct cache access; fencing the chart's pods alone cannot fence
  an unknown external writer. No secret decryption is required for these renders.
- Confirm backups and rollback access, volume capacity/health and that reconciliation
  is stable. Never advance merely because a revision was merged.

## Compatibility evidence, not a final recovery point

The exact target binary and unmodified target `start.sh` were tested with real
Valkey 9.1.3 exports. After API recovery, fresh exports captured at
**2026-11-24T22:59:05Z** passed complete values/types/absolute-expiry and stream
metadata comparisons against 9.1.3, RDB save/restart, AOF rewrite/restart,
RDB-first startup/AOF restart, and representative command checks:

| Dataset | Keys in fresh compatibility export |
|---|---:|
| Blocky | 1028 |
| Immich | 64 |
| Nextcloud | 64 |

**Writers were not fenced for those exports. They are not final cutover backups.**
Fresh final exports after Stage A are mandatory; do not reuse historical counts
as production acceptance thresholds. Expiration continues at real wall time during
maintenance, so compare absolute expiries and expected surviving content, not an
unqualified fixed key count. Historical compatibility tests froze wall time only
inside isolated local tests, never as a production setting.

Local detailed evidence: original migration worktree
`.hermes/reports/valkey-downgrade-verification.md` (including its fresh-export
follow-up), and protected scratch
`valkey-downgrade-fresh-1795561145/{capture.json,compatibility-results.json,entrypoint-results.json}`.
Those local artifacts are not automatically published by this docs-only change.
The encrypted rehearsal archive remains protected; task-generated plaintext was
removed. These tests do not prove Kubernetes PVC ownership/attachment or full
application integration.

## Verified chart-native gates

Use these as **overrides merged into each stage's complete HelmRelease values**,
not replacement values that discard credentials, storage or database settings.
Keep `global.stopAll: false` throughout. It stops the cache/database too and is
not a writer-only gate. Do not use an imperative `kubectl scale`: Helm can undo it.

Numerical native `workload.<name>.replicas: 0` rendered **exactly zero** in both
old and target charts: it was not default/coalesced to one. There are no rendered
HPAs or other autoscalers in these releases. Prefer this verified gate over
`enabled: false`: an attempted all-workload disable failed Immich's selected-pod
Service validation and Nextcloud's primary-workload validation. Cron workloads
are generated from `cronjobs`; changing their `workload.*.enabled` alone is not
a reliable gate because Nextcloud regenerates that map.

### Writer hold, common to Stages A, B and C

Blocky:

```yaml
global:
  stopAll: false
workload:
  main:
    replicas: 0
```

Immich (API, background microservices **and** machine learning):

```yaml
global:
  stopAll: false
workload:
  main:
    replicas: 0
  microservices:
    replicas: 0
  machinelearning:
    replicas: 0
```

Nextcloud (hold every app workload, including currently disabled clamav):

```yaml
global:
  stopAll: false
workload:
  main:
    replicas: 0
  nginx:
    replicas: 0
  notify:
    replicas: 0
  imaginary:
    replicas: 0
  clamav:
    replicas: 0
  collabora:
    replicas: 0
cronjobs:
  - name: nextcloud-cron
    enabled: false
    schedule: '*/5 * * * *'
    cmd:
      - echo "Running [php -f /var/www/html/cron.php] ..."
      - php -f /var/www/html/cron.php
      - echo "Finished [php -f /var/www/html/cron.php]"
  - name: preview-cron
    enabled: false
    schedule: '{{ .Values.nextcloud.previews.schedule }}'
    cmd:
      - echo "Running [occ preview:pre-generate] ..."
      - occ preview:pre-generate
      - echo "Finished [occ preview:pre-generate]"
```

Helm replaces lists: retain the full cron entries/commands. This exact list
rendered **no CronJobs** with either chart version. If future values add a cron,
include and disable it too. Removal does not prove an already-created Job or
orphaned Pod has exited: explicitly wait for those before export.

### Stage B cache hold (target chart only)

Add to each writer hold above, **in the same revision as the chart upgrade**:

```yaml
dependencies:
  valkey:
    enabled: true
    workload:
      main:
        replicas: 0
```

Do not disable the dependency: its credential generation and PVC must exist.
This renders `<release>-valkey-main` at zero while creating
`<release>-valkey-data`, preserving old application PVCs. The target migration's
`extraTpl` must also preserve the exact old claim, for each release:

```yaml
extraTpl:
  - apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: <release>-redis-data
      namespace: <release>
      annotations:
        helm.sh/resource-policy: keep
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 100Gi
```

Replace `<release>` literally with blocky, immich or nextcloud. Merge with any
other existing `extraTpl` entries. This is the observed old chart claim template
(no explicit storage class), not permission to recreate/delete a Bound claim.
Retain its live binding. A new unrelated keep-annotated PVC does not protect the
old PVC. The tested renders retain every old PVC name/spec, adding keep on this
legacy claim, and do not mount it into the new target cache.

### Stage C cache-only start

Keep **all writer holds and disabled crons**, changing only:

```yaml
dependencies:
  valkey:
    enabled: true
    workload:
      main:
        replicas: 1
```

This starts the restored cache only. CNPG remains running as in the source
revision; “cache-only” here means no application writer pods, not a stopped DB.

### Stage D application start, after verification

Keep the Stage C cache replica at one. Restore Blocky's main replicas to **2**;
Immich main/microservices/machinelearning to **1** each; Nextcloud
main/nginx/notify/imaginary/clamav/collabora to **1** each (clamav remains absent
because its application feature is disabled). Restore both Nextcloud cron entries
above with **`enabled: true`**, preserving their exact schedules/commands.
A later split may enable frontends before crons, but must be separately rendered;
the tested Stage D enables the normal workloads and both crons.

## Offline render results

Helm **v3.17.3**, no `--skip-schema-validation`, exact cached OCI chart archives,
release names/namespaces as above, `--kube-version 1.37.2`, and
`--api-versions barmancloud.cnpg.io/v1/ObjectStore`. Flux environment substitutions
were dummy-only. The original Immich storage-marker shell variables were left
as shell variables, not accidentally replaced as cluster substitutions.
All six archives contain application schemas and bundled common schemas.
Six negative controls (old/new for each app, string instead of boolean
`global.stopAll`) were rejected with schema errors, proving validation ran.

| Render | App Deployment replicas | CronJobs | Cache replicas |
|---|---|---|---|
| old active baseline | Blocky 2; Immich 1/1/1; Nextcloud 1/1/1/1/1 | Nextcloud 2 | old 1 |
| A: old chart, writer hold | every app workload 0 | none | old 1 |
| B: target, restore hold | every app workload 0 | none | new 0 |
| C: target, cache start | every app workload 0 | none | new 1 |
| D: target, app start | normal replicas as baseline | Nextcloud 2 | new 1 |

Nextcloud's rendered Deployments are main, nginx, notify, imaginary, collabora;
clamav is configured off and absent in every phase. Blocky's k8s-gateway sidecar
is inside main and is therefore also held. No standalone Pod, Job, DaemonSet,
or Helm hook job is rendered in any phase. Database/cache wait helpers and
Nextcloud install-permissions helpers are **init containers inside held pods**,
not independent Jobs. Target Immich has PostgreSQL/Valkey wait init containers,
storage-marker initialization on main and wait-server on ML/microservices;
Nextcloud has PostgreSQL/Valkey waits, main init-perms, and nginx/notify
wait-nextcloud. Zero parent replicas prevents these helpers from executing.
CNPG's operator-created init/recovery/backup pods and VolSync movers are **not**
Helm-rendered workload evidence: inventory and coordinate them operationally.
Do not claim filesystem backups or database backups are globally suspended by
these writer-only gates. New cache PVCs have no VolSync population source.

**No PostgreSQL major, minor, OS, extension or image change in this sequence:**
old and every target stage render identical CNPG cluster names/images:

```text
immich-cnpg-main:
  ghcr.io/tensorchord/cloudnative-vectorchord:16.15-1.1.1@sha256:f5a17fa05faf25e81304ee95e9f920d8ae077ac4a4ef0a1251e09c7197cbb236
nextcloud-cnpg-main:
  ghcr.io/cloudnative-pg/postgresql:15.19@sha256:11274300143f02d369ea2ff6082b028b6b662915f06bf59f26b808b53823475a
```

Retain the proposed target values `dependencies.postgresql.operator.pgVersion`
**16** / **15** and `operator.cluster.imageName` **exactly** as above. Nextcloud
must not default to 16. Blocky renders no CNPG Cluster; preserve
`dependencies.postgresql.enabled: false` and `secret.datasource.enabled: false`.
The CNPG backup mechanism changes to the plugin despite the image pin: its
independent prerequisites/admission checks still apply.

Operational evidence is outside Git at
`/home/hermes/.hermes/cache/scratch/valkey-staging/`:

- `rehearse.py`, `validate.py`, `results.json`, `validation.txt`;
- `<app>/{baseline,A,B,C,D,zero-probe}/` with exact `overlay.yaml`,
  dummy effective values, render, stderr, and command JSON;
- six negative schema results under `<app>/{A,B}/negative-schema.stderr`;
- `<app>/restore-pod.yaml` (temporary helper, **not applied**), generated by
  `materialize-helpers.py`; all three pass strict kubeconform Pod validation.

There are **18 successful renders**: baseline + A/B/C/D + explicit zero-replica
probe for each release, with assertions for gates, old PVC retention/specs,
new PVCs, target image/UID/mount, DB image equality, and absence of jobs/hooks/
autoscalers. Re-run using the saved commands; for example:

```sh
/home/hermes/.hermes/cache/scratch/common2026-cnpg/venv/bin/python \
  /home/hermes/.hermes/cache/scratch/valkey-staging/rehearse.py
/home/hermes/.hermes/cache/scratch/common2026-cnpg/venv/bin/python \
  /home/hermes/.hermes/cache/scratch/valkey-staging/validate.py
# Individual command shape (substitute app/version/phase):
helm template blocky /protected/charts/blocky-25.0.0.tgz -n blocky \
  -f /protected/operations/blocky/B/values-dummy.yaml \
  --kube-version 1.37.2 --api-versions barmancloud.cnpg.io/v1/ObjectStore
```

Scratch is not a permanent distribution mechanism. Archive the non-secret
operational evidence and exact chart archives outside Git before maintenance;
rebuild it for the final reviewed values, rather than applying dummy manifests.

## Operator sequence — later, separately approved revisions

Perform one application at a time, never queue A/B/C/D for unattended Flux
progression. Every revision must be reviewed, reconcile successfully, and pass
its observed-state gate before preparing/approving the next. Recheck Helm
remediation: A must be Ready before capture; rollback of B must return to the
**held A**, C to held B, and D to held C, never an active baseline. Freeze
unrelated automation/chart updates during the window. Do not resume a suspended
HelmRelease until its Git values contain the correct hold.

### A. Stop writers on the old chart, then capture final data

1. Apply only the old-chart writer holds via the approved GitOps revision. Leave
   source Valkey running. Check the reconciled generation/version and Helm Ready.
2. Inspect `kubectl -n "$app" get deploy,sts,cronjob,job,pod -o wide`.
   Require every named app Deployment's desired **and observed** replicas to be
   zero; no nonterminal writer Pod (including terminating or initializing ones),
   no active/orphan cron Job/Pod, and no external cache client able to mutate data.
   CNPG and source cache pods may remain; review every other pod explicitly.
   Do not use `Running` alone: init/terminating pods can still write. If any
   controller or client cannot be fenced, **stop: no final export**.
3. Inspect authenticated client activity without printing credentials or key
   contents; account for monitoring and the export connection. Confirm queues/
   sessions/locks and maintenance semantics with application owners. Capture
   timestamp, source server version, database inventory, and a semantic manifest
   of all databases (not only DB 0) in protected storage. TTLs still expire.
4. Capture a new RDB after the fence. The following later-use command takes the
   password from the existing source container env, never an argument or host
   plaintext variable. Source CLI path and presence of `VALKEY_PASSWORD` were
   read-only checked for Blocky; repeat for each source before maintenance.

```sh
set -eu
set +x
umask 077
set -C # refuse existing output files, including symlinks
app=blocky # repeat for immich, nextcloud; never run all blindly
case "$app" in blocky|immich|nextcloud) ;; *) exit 1 ;; esac
# HOME must be a real, operator-owned directory, not a symlinked path.
test "$(realpath -e -- "$HOME")" = "$HOME"
test "$(stat -c %u -- "$HOME")" = "$(id -u)"
test -z "$(find "$HOME" -maxdepth 0 -perm /022 -print)"
base="$HOME/protected-valkey-cutover"
if test ! -e "$base" && test ! -L "$base"; then
  mkdir -m 700 -- "$base" # no -p: creation must not reuse an existing path
fi
test -d "$base" && test ! -L "$base"
test "$(stat -c %u:%a -- "$base")" = "$(id -u):700"
# Always allocate a NEW private directory; never select an old capture for export.
backup=$(mktemp -d -- "$base/$app.XXXXXXXXXX")
test -d "$backup" && test ! -L "$backup"
test "$(stat -c %u:%a -- "$backup")" = "$(id -u):700"
printf 'Retain this exact Stage B capture path: %s\n' "$backup"
# Require the successful Stage A fence above BEFORE running this command.
kubectl --request-timeout=2m -n "$app" exec "${app}-redis-0" -- \
  /bin/sh -ec '
    export REDISCLI_AUTH="$VALKEY_PASSWORD"
    p=/tmp/valkey-cutover-final.rdb
    test ! -e "$p"
    trap '\''rm -f "$p"'\'' EXIT
    /opt/bitnami/valkey/bin/valkey-cli --rdb "$p" >/dev/null 2>/dev/null
    test -s "$p"
    cat "$p"
  ' > "$backup/final.rdb.partial"
test -s "$backup/final.rdb.partial"
# Hard-link publication refuses any existing destination; retain partial evidence.
ln -T -- "$backup/final.rdb.partial" "$backup/final.rdb"
(cd "$backup" && sha256sum final.rdb > final.rdb.sha256)
# Do not remove this directory or its partial output after a failed attempt.
```

Record the printed **exact capture directory** with the application and fence
evidence; paste that same path into Stage B, even when using a fresh shell. Each
attempt gets a new private directory. Never reuse an earlier directory or remove
failed partial outputs to retry; keep them for investigation. The successful
`final.rdb.partial` is retained as a hard link to the published RDB.

Record and encrypt final data plus its semantic manifest using the established
backup process; verify encrypted readback and retain protected access for restore.
Do not log values, passwords, RDB bytes or decrypted manifests. An export/CLI
failure is fatal, not a reason to proceed with a partial file. Reconfirm the
writer fence immediately after capture and keep it through Stage C.

### B. Upgrade held, populate the new PVC before first cache start

1. Approve target chart + correct migration base + writer holds + cache replicas
   zero **atomically in one revision**. Confirm old PVC retention, unchanged DB
   image, plugin readiness and the exact rendered target before approval.
2. Wait for the target revision to be applied. Require target StatefulSet desired
   and observed replicas zero, no target cache Pod, every writer still zero,
   no cron/active writer Job, and old source cache fully stopped. Inspect actual
   new PVC name/class/size/binding. Never restore to `*-redis-data`.
3. Attach **only** the temporary operational restore helper to the new PVC. Its
   command is `/bin/sh -ec 'sleep 86400'`, not the image entrypoint/start script;
   it has no Service, service-account token or RBAC, uses the exact pinned image,
   UID/GID/fsGroup 568, read-only root filesystem, and drops all capabilities.
   Helpers and one-time recovery tooling stay outside production GitOps paths.
   Inability to write as 568 is a blocker, not permission to bypass it silently.
4. The target must be a clean root. **Even an empty `/config/appendonlydir`
   bypasses RDB-first loading and can boot an empty database.** If this target
   has ever started, stop and quarantine/snapshot the entire target contents
   before preparing a clean root; do not delete AOF casually. Never clean the
   legacy PVC. A fresh filesystem's `lost+found` is harmless. Reject any other
   preexisting target file before the one-time copy.

Later-use commands with the reviewed external helper, after the B gate:

```sh
set -eu
set +x
umask 077
set -C
app=blocky # set independently, even in a fresh shell
case "$app" in blocky|immich|nextcloud) ;; *) exit 1 ;; esac
# Paste the EXACT successful Stage A capture path; never guess the newest one.
backup="$HOME/protected-valkey-cutover/blocky.REPLACE_WITH_CAPTURE_SUFFIX"
test "$(realpath -e -- "$HOME")" = "$HOME"
test "$(stat -c %u -- "$HOME")" = "$(id -u)"
test -z "$(find "$HOME" -maxdepth 0 -perm /022 -print)"
base="$HOME/protected-valkey-cutover"
test -d "$base" && test ! -L "$base"
test "$(stat -c %u:%a -- "$base")" = "$(id -u):700"
case "$backup" in "$base/$app."*) ;; *) exit 1 ;; esac
test "$(dirname -- "$backup")" = "$base"
test -d "$backup" && test ! -L "$backup"
test "$(realpath -e -- "$backup")" = "$backup"
test "$(stat -c %u:%a -- "$backup")" = "$(id -u):700"
for file in final.rdb final.rdb.sha256; do
  test -f "$backup/$file" && test ! -L "$backup/$file"
  test "$(stat -c %u:%a -- "$backup/$file")" = "$(id -u):600"
done
# Validate only the expected local filename, not arbitrary checksum-file paths.
expected=$(sha256sum -- "$backup/final.rdb")
expected=${expected%% *}
test "$(cat -- "$backup/final.rdb.sha256")" = "$expected  final.rdb"
(cd "$backup" && sha256sum -c final.rdb.sha256)
ops=/home/hermes/.hermes/cache/scratch/valkey-staging
kubectl -n "$app" apply -f "$ops/$app/restore-pod.yaml"
kubectl -n "$app" wait --for=condition=Ready pod/valkey-cutover-restore --timeout=180s
kubectl -n "$app" exec valkey-cutover-restore -- /bin/sh -ec '
  test -w /config
  test -z "$(find /config -mindepth 1 -maxdepth 1 ! -name lost+found -print -quit)"
'
kubectl -n "$app" exec -i valkey-cutover-restore -- /bin/sh -ec '
  set -C
  for p in /config/appendonlydir /config/dump.rdb /config/dump.rdb.partial; do
    test ! -e "$p" && test ! -L "$p"
  done
  umask 077
  cat > /config/dump.rdb.partial
  test -s /config/dump.rdb.partial
  valkey-check-rdb /config/dump.rdb.partial >/dev/null
  ln /config/dump.rdb.partial /config/dump.rdb
  test "$(stat -c %u:%g /config/dump.rdb)" = 568:568
  test -w /config/dump.rdb
  rm /config/dump.rdb.partial
' < "$backup/final.rdb"
restored=$(kubectl -n "$app" exec valkey-cutover-restore -- \
  sha256sum /config/dump.rdb)
test "$restored" = "$expected  /config/dump.rdb"
kubectl -n "$app" delete pod valkey-cutover-restore --wait=true
```

If checksum/ownership/check-rdb fails, stay in B and investigate. Do not overwrite
an existing partial file on retry without reviewing the failure. Confirm helper
absence and RWO volume detach as necessary before C. `valkey-check-rdb` is only
structural checking: it does not replace content/persistence verification.
These helper operations were validated offline, **not exercised on production PVCs**.

### C. Start only restored Valkey; verify before any writer starts

Approve only the cache replicas change 0 → 1. Require `*-valkey-main-0` Ready,
correct imageID/digest, `/config` mounted from the intended claim, no app pods,
no crons/active writer jobs, and helper absent. Use the injected container env,
which renders from Secret **`<release>-valkeycreds`**, key **`valkey-password`**:

```sh
kubectl -n "$app" exec "${app}-valkey-main-0" -- /bin/sh -ec '
  export REDISCLI_AUTH="$VALKEY_PASSWORD"
  valkey-cli -h 127.0.0.1 -p 6379 PING
  valkey-cli -h 127.0.0.1 -p 6379 INFO persistence
  valkey-cli -h 127.0.0.1 -p 6379 CONFIG GET appendonly
  valkey-cli -h 127.0.0.1 -p 6379 CONFIG GET dir
'
```

Require `loading:0`, `aof_enabled:1`, `aof_rewrite_in_progress:0`,
`aof_rewrite_scheduled:0`, `aof_last_bgrewrite_status:ok`,
`aof_last_write_status:ok`, appendonly yes, dir `/config`. Verify semantic content
against the final export across every logical database with real-time expiry
handling, including stream groups/consumer metadata. Healthy PING or matching
key count alone is insufficient. Test a namespaced expiring canary, atomic lock
and Lua behavior, and explicitly clean test keys; record only pass/fail, never
production values. Then perform a separately approved cache-only restart while
writers remain held, and repeat content/persistence checks to prove AOF restart.
A zero-then-one cache replica revision is a chart-native restart option; do not
use a global stop or accidentally clear writer holds. If any check fails, stay
held; do not reset to an empty cache or enable writers to “test it.”

### D. Start application, canary, then release normal operation

Approve the tested D replica/cron settings only after C acceptance. Verify
rollouts and application logs without secrets. Exercise Blocky DNS/cache use;
Immich upload, background worker/queue and existing-media access; Nextcloud
login/session, upload/download, locking, cron, notify and Collabora. Verify CNPG
stayed on the exact image, normal backups and storage health, and new cache
persistence. Only then conclude the cutover. Retain old PVCs, final encrypted
exports and rollback evidence until a separately approved retention deadline.
Remove operational helpers and task plaintext after protected archive/readback
verification; never commit them.

## Failure and rollback boundaries

- Before D, writers remain held. Diagnose in that stage. A failed B/C Helm
  rollback must preserve that hold; inspect its actual values and pods.
- To roll back before app writes, stop new Valkey through the native gate, verify
  no target pod, then return to the **held old-chart A** configuration and intact
  legacy PVC. Verify source data and only then separately restore writers.
- After D, new cache state and application/DB mutations may exist. The legacy
  PVC is stale. Do not blindly revert versions or reconnect it. Fence writers
  again, export target state, assess application/database rollback and establish
  an approved recovery point before choosing restore/reset/roll-forward.
- No final capture, restore, live scale/write, chart upgrade, commit, push or PR
  creation was performed in this preparation task. The preparation PR must remain
  docs-only; publishing it as a draft is the reviewer's later action, not rollout
  authorization. Stage approvals, live fencing, final export, storage ownership,
  semantic/AOF production verification, plugin readiness and app canaries remain
  explicit execution blockers.
