# Voice connection-check recovery: image provenance

This record describes a promotion candidate for Main Chota Platform. It does not establish the observed running revision or successful carrier acceptance.

| Evidence | Exact value |
| --- | --- |
| Source repository | [chotabyorg/ai-agent-service](https://github.com/chotabyorg/ai-agent-service) |
| Merged source | [`38f7ceb80cf683655dc934e3351cb1a28a2debcf`](https://github.com/chotabyorg/ai-agent-service/commit/38f7ceb80cf683655dc934e3351cb1a28a2debcf) |
| Source change | [PR 89](https://github.com/chotabyorg/ai-agent-service/pull/89) |
| Reviewed and tested head | `fdc1eb8f666cff73341257a7397a2d8d662d0d90`; its Git tree equals the merged source tree |
| Image | `ghcr.io/chotabyorg/ai-agent-service:38f7ceb@sha256:0e1f65a2c944a85ec3f292ca70ea21ba89bd105c9b1ec459b91b3099611d1915` |
| Publishing workflow | [Deploy run 39146985887](https://github.com/chotabyorg/ai-agent-service/actions/runs/39146985887), successful, `head_sha` equals the merged source |
| Digest evidence | [Build-and-deploy job 117732712398](https://github.com/chotabyorg/ai-agent-service/actions/runs/39146985887/job/117732712398): BuildKit `containerimage.digest` reports the digest above |
| Full source checks | [Quality 39145726547](https://github.com/chotabyorg/ai-agent-service/actions/runs/39145726547), successful |
| Native source checks | [39145726577](https://github.com/chotabyorg/ai-agent-service/actions/runs/39145726577): all four jobs successful |
| Targeted native PostgreSQL checks | 96 passed in 124.84 seconds on the reviewed head |

The immutable digest, rather than the short tag alone, identifies the artifact. The successful publishing job links that digest to the full source commit; this is CI provenance evidence, not an independent reproducible-build claim.

Kustomize validation changes exactly three rendered AI image references (application and init containers). No other rendered object changes. This release does not modify Conversation `3f0669156c016cbdcdea53e9a62c0bf15090c686`, Voice `d39914e57967805325addbf880093d6d7baa4a62`, AI PR 82, or Conversation PR 23.

Before promotion, close admission and wait for existing calls, open call reports, authorized responses and active turns to finish. ArgoCD remains the deployment mechanism. After rollout, separately retain the observed pod image IDs, routing evidence and audio/CRM acceptance results. Three real playback interruptions must resume booking without another connection check; a real incoming carrier call and CRM readback remain acceptance gates.
