# Zot backup and restore contract

Status: **design placeholder — production values and RPO/RTO require owner
approval after read-only preflight**.

The registry data PVC is independent from BLUE MinIO, GREEN AIStor, and
Repetly storage. The production plan must name the storage backend, snapshot
mechanism, retention, encryption, restore owner, and tested RPO/RTO. A backup
of only the Kubernetes manifests is insufficient; the OCI blobs, manifests,
tags, ACL/auth configuration, and TLS/identity metadata required to restore
the registry must be covered.

## Failure model

- Existing Pods with cached layers may continue while Zot is unavailable.
- A new Pod, reschedule, or node without the cached image may fail to pull.
- A failed PVC or corrupted registry store is a release blocker until restore
  is proven.
- HA is not selected in this P0 scaffold. Decide it only after preflight
  reveals node topology, storage behavior, and the acceptable single-replica
  window.

## Required restore test

1. Restore to disposable infrastructure using the approved backup artifact.
2. Verify the unique immutable tag, exact manifest digest, ACLs, and TLS path.
3. Repeat puller/anonymous/publisher negative tests.
4. Pull the image and verify the resulting Pod `imageID`.
5. Record elapsed restore time and evidence before any production approval.
