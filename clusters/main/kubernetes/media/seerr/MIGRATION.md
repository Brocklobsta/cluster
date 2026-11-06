# Ombi → Seerr cutover

This PR stages Seerr at `https://seerr.brocklobsta.net` alongside Ombi at
`https://request.brocklobsta.net`. It does not switch the existing request URL
or delete Ombi's namespace, PVC, or backups. The applications use different
databases; Seerr's automatic migration applies to Overseerr/Jellyseerr, not Ombi
(see https://github.com/seerr-team/seerr/issues/2434). Do not mount Ombi's
config PVC into Seerr or assume request history is imported.

After this PR is merged and Flux reconciles:

1. Verify the Seerr HelmRelease, pod, CNPG cluster (both members on different
   nodes), config PVC, VolSync destination, Ingress and certificate are ready.
   Confirm `/api/v1/status` responds through an authenticated ingress session
   or a local port-forward. If the Authentik forward-auth policy prevents
   initial setup, use a temporary local
   `kubectl -n seerr port-forward svc/seerr 10241:10241` instead of weakening the
   public ingress policy.
2. Complete Seerr's first-run setup, connect the existing Emby server and
   Sonarr/Radarr instances, configure user access, and submit a test request.
   Verify it reaches the intended automation service. Recreate any important
   open Ombi requests manually; audit request history before deciding whether
   to retire Ombi. Existing Ombi backups remain the rollback source.
3. In a separate cutover PR, move Seerr's ingress to `request.${DOMAIN_0}` and
   disable Ombi's ingress before applying the new host. Remove the obsolete
   Homepage Ombi API key/widget integration only after a Seerr API key is
   available and its widget works. Validate ingress admission and TLS, then
   test login and a request through the original URL.
4. Retire Ombi only after history/rollback requirements are satisfied. Pruning
   the Ombi namespace would delete its PVCs and stored data; retain an explicit
   backup and recovery plan before doing so.
