# Production read-only preflight

This is a checklist for the owner/operator after the local blocker in
`README.md` is resolved. It is not an execution authorization. Use the actual
production context supplied by the owner and record output without secret
values.

Every Kubernetes command below is read-only: current-context, cluster/version
identity, GET/LIST/DESCRIBE, or metrics/statistical reads. Do not substitute
`apply`, `patch`, `edit`, `rollout`, `exec` with a mutating command, or any
license/IAM/bucket write.

Set only non-secret placeholders out of band:

```sh
NS='__PRODUCTION_NAMESPACE__'
BLUE_DEPLOYMENT='repetly-minio'
BLUE_SERVICE='repetly-minio'
BLUE_PVC='__BLUE_PVC_NAME__'
AIStorAlias='__PRECONFIGURED_READ_ONLY_MC_ALIAS__'
BUCKET='__BUCKET_NAME__'
```

## Cluster, node architecture, namespace, and labels

```sh
kubectl config current-context
kubectl cluster-info
kubectl version --output=yaml
kubectl get --raw=/version
kubectl get nodes -o custom-columns=NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,OS:.status.nodeInfo.operatingSystem,KERNEL:.status.nodeInfo.kernelVersion
kubectl get namespace "$NS" --show-labels
kubectl get namespace "$NS" -o yaml
kubectl get pods -n "$NS" --show-labels
kubectl get pods -n "$NS" -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase,READY:.status.conditions[?(@.type=="Ready")].status
```

If the target nodes are amd64, retain the reviewed amd64 child image digests.
If they are arm64, stop and repeat scans/rehearsal for the arm64 children.

## BLUE image, Deployment, Pod, and Service

```sh
kubectl get deployment "$BLUE_DEPLOYMENT" -n "$NS" -o yaml
kubectl get pods -n "$NS" -l app=minio -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[*].image,IMAGE_ID:.status.containerStatuses[*].imageID,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount
kubectl get service "$BLUE_SERVICE" -n "$NS" -o yaml
kubectl describe deployment "$BLUE_DEPLOYMENT" -n "$NS"
kubectl describe pod -n "$NS" -l app=minio
```

Record the actual BLUE image and imageID/digest, selectors, endpoints, node
placement, restart history, and readiness. Do not change the BLUE workload.

## PVC, capacity, usage, StorageClass, reclaim policy

```sh
kubectl get pvc "$BLUE_PVC" -n "$NS" -o yaml
kubectl describe pvc "$BLUE_PVC" -n "$NS"
kubectl get pvc "$BLUE_PVC" -n "$NS" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.status.capacity.storage,REQUEST:.spec.resources.requests.storage,SC:.spec.storageClassName,VOLUME:.spec.volumeName,FINALIZERS:.metadata.finalizers
kubectl get storageclass -o yaml
kubectl get pv -o custom-columns=NAME:.metadata.name,CLAIM:.spec.claimRef.namespace/.spec.claimRef.name,CAPACITY:.spec.capacity.storage,SC:.spec.storageClassName,RECLAIM:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase
kubectl top nodes
kubectl top pods -n "$NS"
```

For actual object-store usage, use only the preconfigured read-only AIStor
client alias below. Filesystem usage not exposed by the cluster metrics API
must be supplied by the owner from an approved read-only node/CSI metric; do
not use an interactive shell or write a probe object.

## Object count and bytes — read-only client

```sh
mc ls --recursive --json "$AIStorAlias/$BUCKET"
mc du --recursive --json "$AIStorAlias/$BUCKET"
mc stat --json "$AIStorAlias/$BUCKET"
```

The alias must already be scoped for read-only inspection. Do not run `mb`,
`cp`, `mv`, `rm`, `mirror`, `share`, `admin`, or any command that changes
objects, policies, users, or configuration.

## AIStor CR, Services, PVCs, and placement

```sh
kubectl get objectstore -n "$NS" -o yaml
kubectl describe objectstore -n "$NS"
kubectl get pods,statefulsets,services,pvc -n "$NS" -o wide
kubectl get pods -n "$NS" -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IMAGE_ID:.status.containerStatuses[*].imageID,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount
kubectl get events -n "$NS" --sort-by=.metadata.creationTimestamp
```

Record `currentState`, `healthStatus`, `setup`, pool state/running counts,
health endpoints and errors. No `exec` is part of this production checklist.

## IAM policies, attachments, and anonymous policy

Use a preconfigured read-only AIStor client identity and only inspection calls:

```sh
mc admin policy ls "$AIStorAlias"
mc admin policy info "$AIStorAlias" __POLICY_NAME__
mc admin user info "$AIStorAlias" __USER_NAME__
mc anonymous get "$AIStorAlias/$BUCKET"
```

Record policy names, user/group/service-account attachments, and anonymous
access result only. Do not add/remove users, attach/detach policies, or set
anonymous access.

## TLS, Ingress, NetworkPolicy, and endpoints

```sh
kubectl get ingress,httproute,gateway -n "$NS" -o yaml
kubectl get service -n "$NS" -o yaml
kubectl get networkpolicy -n "$NS" -o yaml
kubectl get endpoints,endpointslices -n "$NS" -o yaml
kubectl get secret -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range $k,$v := .data}{$k}{" "}{end}{"\n"}{end}'
```

The last command prints Secret names and key names only; never print `.data`
values. Review SANs/trust references from Secret metadata and approved
TLS/Ingress objects, not by exporting private key or certificate values.

## Argo/Kustomize and ownership state

```sh
kubectl get applications.argoproj.io -A -o yaml
kubectl get applicationsets.argoproj.io -A -o yaml
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A -o yaml
kubectl get helmreleases.helm.toolkit.fluxcd.io -A -o yaml
kubectl get configmap -n "$NS" -o yaml
```

Confirm whether GREEN is referenced, which controller owns each object, and
whether any drift, suspended reconciliation, or pending health state exists.

## Owner hand-off data required before the next step

The owner must provide or authorize a read-only session that returns:

1. cluster/context identity and actual production node architecture;
2. BLUE image plus every Pod imageID/digest and node placement;
3. namespace labels, Deployment/Pod/Service selectors and endpoints;
4. PVC capacity, actual usage metric, StorageClass, PV reclaim policy, and
   finalizers;
5. object count/bytes and read-only IAM/anonymous-policy results;
6. TLS/Ingress trust and NetworkPolicy source/destination paths; and
7. Argo/Kustomize ownership and Secret names/key names only.

No production install, restart, migration, Service cutover, IAM change, bucket
write, license action, or rollback change is authorized by this checklist.
