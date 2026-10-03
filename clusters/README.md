# Cluster layout proposal

This tree separates future cluster-specific configuration without moving or changing `services/*/prod`.

| Cluster | API | Application namespace | Current application sources |
| --- | --- | --- | --- |
| main | https://kubernetes.default.svc | prod (plus existing platform namespaces) | Existing `services/*/prod` and platform Applications |
| voice | https://10.250.0.2:6443 | voice | Future `clusters/voice/apps/chota-va`, not created yet |

Nothing under this tree is connected to an Application or ApplicationSet. Example manifests have `.example` extensions and must not be applied automatically. There is no root Kustomization that could deploy this tree by accident.

The existing `prod-services` ApplicationSet drift is a separate follow-up: live discovers `services/*/prod` excluding payment-service; Git explicitly lists outsors, atlas, and repetly. This proposal changes neither side. Restore that desired state through a separate reviewed GitOps change before designing a multi-cluster generator.

Do not add voice to an unrestricted cluster generator. Existing production destinations remain main. Voice applications require the explicit private destination and namespace documented here.
