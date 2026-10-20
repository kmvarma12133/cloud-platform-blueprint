# 0008: Envoy Gateway and Gateway API instead of ingress-nginx

- Status: accepted
- Date: 2026-10-20

## Context and problem statement

The original plan for this platform used ingress-nginx. In November 2025 the
Kubernetes project announced its retirement: best-effort maintenance ended in
March 2026, and the `kubernetes/ingress-nginx` repository is now archived. A
public entry point that no longer receives security fixes is not acceptable,
even in a reference platform.

## Decision drivers

- Maintained, with security releases.
- The same API and behaviour on EKS, AKS and kind.
- A standard API rather than controller-specific annotations, so the next
  migration is cheaper.
- A clear split between what the platform team owns (listeners, TLS) and what
  an application team owns (its routes).

## Considered options

1. Keep ingress-nginx, unmaintained.
2. F5 NGINX Ingress Controller (a different project, with different annotations).
3. Traefik.
4. Envoy Gateway, implementing Gateway API.
5. Cloud load balancer controllers (AWS Load Balancer Controller with ALB,
   Application Gateway for Containers on Azure).

## Decision outcome

Option 4, Envoy Gateway 1.9 with Gateway API `v1` resources:

- **One `Gateway` per cluster** (`platform/gateway`), owned by the platform
  team, in `envoy-gateway-system`. Routes can attach to it only from namespaces
  labelled `platform.cpb.io/gateway: public`. The orders-api ApplicationSet
  adds that label to the namespaces it creates.
- **The app owns its `HTTPRoute`**, rendered by the chart from `httpRoute`
  values with a hostname per environment.
- **TLS.** Cloud overlays add an HTTPS listener whose certificate cert-manager
  issues and renews from Let's Encrypt. It reads the issuer annotation on the
  Gateway, with Gateway API support enabled in cert-manager.
- **NetworkPolicy.** The orders-api policy admits traffic from the
  `envoy-gateway-system` namespace instead of an ingress controller's.

### Consequences

Good:

- A maintained, standards-based data plane, identical on all three platforms.
- Gateway API's role separation replaces annotation sprawl.
- Argo Rollouts has a Gateway API traffic-router plugin, which opens the door
  to precise canary weights later (see ADR 0003).

Bad:

- **Teams migrating from ingress-nginx have to translate their annotations.**
  Some nginx-specific behaviour (snippets, certain rewrites) has no direct
  equivalent.
- **On AWS, the Envoy Service needs AWS Load Balancer Controller annotations to
  get an NLB.** The legacy in-tree controller only creates a Classic Load
  Balancer. That controller isn't installed by this repo yet; see "Production
  hardening not covered" in the README.
- **Envoy runs as its own Deployment per Gateway**, which needs sizing and a
  PodDisruptionBudget in prod.

## Pros and cons of the other options

**Unmaintained ingress-nginx.** Familiar, but no further security fixes.

**F5 NGINX Ingress.** Maintained, but still the Ingress API plus
vendor-specific CRDs. It doesn't move the platform toward the standard.

**Traefik.** Mature and supports Gateway API. A reasonable alternative.
Envoy Gateway was chosen because Envoy is also the data plane of most service
meshes. That matters if mTLS between services is added later.

**Cloud LB controllers.** Very good on their own cloud, but different
resources on each, and nothing for kind.
