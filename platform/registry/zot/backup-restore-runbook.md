# Zot backup and restore contract

Status: **owner-approved P0 design — deterministic rehydration primary; no
production restore was executed**.

## Scope and targets

The Zot PVC is independent from BLUE MinIO, GREEN AIStor, and every Repetly
storage bucket. The selected P0 shape is one `10Gi` `local-path` RWO PVC on the
single production node. This is a documented single-failure-domain tradeoff;
replicated/multi-node storage and off-host snapshots are follow-up technical
debt, not a reason to introduce Ceph or Longhorn in this P0.

Target recovery objectives:

- RPO: **24 hours** for the registry mirror ledger and content set.
- RTO: **2 hours** to restore the registry endpoint and make the approved
  immutable tag pullable.

No existing Velero, restic, snapshot, or off-host registry backup path was
found during the read-only production inspection. The P0 recovery source is
therefore deterministic rehydration:

1. Recreate the inert manifests with the exact Zot amd64 digest.
2. Recreate the `registry` namespace, PVC, auth contract, and Traefik route.
3. Re-mirror the exact approved OCI artifacts from their public source using
   digest-preserving tooling.
4. Recreate the content-identifying immutable tags from the release ledger.
5. Verify digest equality, ACL negatives, health probes, and an AIStor pull.

The release ledger must retain source digest, destination digest, source image,
content tag, scan evidence, mirror timestamp, and publisher identity. A
manifest-only backup is insufficient.

## Restore acceptance

Restore succeeds only when, within the RTO:

- `registry.chota.by` resolves and Traefik presents a publicly trusted ACME
  certificate;
- `/startupz`, `/readyz`, and `/livez` are healthy;
- publisher can create a new content tag but cannot overwrite or delete it;
- puller can read the approved tag but cannot create/update/delete;
- anonymous access is denied;
- destination manifest digest equals the official source digest; and
- a disposable amd64 Pod pulls the tag and reports the expected imageID.

Add an off-host snapshot/backup destination, retention, encryption, and a
periodic restore drill before expanding beyond this single-node topology.
