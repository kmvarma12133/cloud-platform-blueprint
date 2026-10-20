# 0007: Keyless Cosign signing and SBOM attestation

- Status: accepted
- Date: 2026-10-20

## Context and problem statement

Before an image goes to prod we want proof of where it came from: built by
this repository's CI, from `main`, from a known commit, with a known list of
contents. A tag in a registry proves none of that, because anyone who can
push to the registry can overwrite it.

## Decision drivers

- No long-lived signing key to store, rotate or leak.
- Verification tied to an identity a reviewer understands: this workflow file,
  in this repository, on this branch.
- An SBOM bound to the exact image digest, for vulnerability response ("are we
  running the affected library anywhere?").

## Considered options

1. No signing; trust the registry.
2. Cosign with a long-lived key, ideally held in a KMS.
3. Keyless Cosign: a short-lived certificate from Fulcio, issued against the
   GitHub Actions OIDC token, with the signature recorded in the Rekor
   transparency log.
4. GitHub artifact attestations (also Sigstore-based).
5. Notation (Notary v2) with certificates from a private CA.

## Decision outcome

Option 3. In `app-ci.yml` on `main`:

1. Build the image once.
2. Scan it with Trivy.
3. Generate an SPDX SBOM with Syft.
4. Push the image, then sign its digest with `cosign sign`.
5. Attach the SBOM with `cosign attest --type spdxjson`.

The job has `id-token: write` and no other secrets.

`promote-prod.yml` verifies both before opening a PR. The certificate identity
must be exactly `https://github.com/<owner>/cloud-platform-blueprint/.github/workflows/app-ci.yml@refs/heads/main`,
issued by `token.actions.githubusercontent.com`. The PR then pins
`values-prod.yaml` to `tag@digest`, so the kubelet pulls exactly the verified
bytes.

### Consequences

Good:

- There is no signing key anywhere: nothing to rotate, nothing to steal from
  CI secrets.
- A signature can't be produced by a fork, another workflow or another branch.
  The identity check rejects it.
- Every signature is publicly logged in Rekor and can be audited after the
  fact.

Bad:

- Signing and verification depend on the public Sigstore services (Fulcio and
  Rekor). An outage blocks publishing. Organisations with stricter needs run
  private Sigstore instances.
- Rekor entries are public and reveal the repository and workflow names.
  That's fine for a public repo; it's a consideration for private ones.
- Renaming or moving `app-ci.yml` changes the identity. The verification
  string in `promote-prod.yml` has to change in the same PR.
- Verification happens at promotion, not at admission. Enforcing signatures
  in the cluster (Sigstore policy-controller, Kyverno `verifyImages`, or
  Ratify with Gatekeeper) is listed under production hardening in the README.

## Pros and cons of the other options

**Long-lived key.** Works offline and needs no public infrastructure, but the
key becomes the most valuable secret in CI, and every rotation or compromise
means re-signing.

**GitHub artifact attestations.** Same Sigstore foundation and tighter GitHub
integration (`gh attestation verify`). Cosign was chosen because it works the
same way with any registry and CI system, which matters for a multi-cloud
platform whose images may also live in ECR or ACR.

**Notation.** Fits organisations with an existing PKI and private CA. It brings
back certificate lifecycle management, which keyless signing avoids.
