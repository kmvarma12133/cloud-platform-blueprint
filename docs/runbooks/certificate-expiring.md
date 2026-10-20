# Runbook: certificate expiring or not renewing

Certificates for the public Gateway's HTTPS listener are issued by
cert-manager from Let's Encrypt (`ClusterIssuer/letsencrypt`, HTTP-01 answered
through the same Gateway). They last 90 days and cert-manager renews them
about 30 days before expiry. A certificate within 14 days of expiry means
renewal has already failed for two weeks.

## Symptoms

- An alert on certificate expiry, using the query below (for example, expiring
  within 14 days).
- `kubectl get certificate -A` shows `READY=False`, or a `NotAfter` date close
  to now.
- After expiry, browsers and clients fail TLS against the gateway hostname.

## Dashboards and queries

cert-manager exports metrics through its ServiceMonitor:

```promql
# Days until expiry, per certificate
(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400
# Certificates that are not Ready
certmanager_certificate_ready_status{condition="False"} == 1
```

```bash
kubectl get certificate,certificaterequest,order,challenge -A
openssl s_client -connect orders.example.com:443 -servername orders.example.com </dev/null 2>/dev/null | openssl x509 -noout -dates
```

## Diagnosis

Follow the chain: Certificate → CertificateRequest → Order → Challenge.

```bash
kubectl -n envoy-gateway-system describe certificate public-gateway-tls
kubectl get challenge -A -o wide
kubectl -n cert-manager logs deploy/cert-manager --since=1h | grep -iE 'error|fail'
```

Common causes:

1. **The HTTP-01 challenge isn't reachable.** Let's Encrypt must fetch
   `http://<host>/.well-known/acme-challenge/<token>` from the internet.
   - Is DNS pointing at the gateway's load balancer?
   - Does the HTTP listener still exist? Removing port 80 breaks renewal.
   - Is a firewall or WAF blocking the path?
2. **Rate limits.** Let's Encrypt allows a limited number of certificates per
   domain per week. Repeated failed attempts can hit them, and the order error
   says so.
3. **The Gateway annotation or issuer changed.** The certificate is created
   from `cert-manager.io/cluster-issuer` on the Gateway. Check that it is still
   there and that the ClusterIssuer is `Ready`.
4. **The ACME account key Secret was deleted**
   (`letsencrypt-account-key`). cert-manager registers a new account, which is
   usually harmless.

## Mitigation

- Fix the reachability problem, then trigger a renewal:
  `kubectl cert-manager renew -n envoy-gateway-system public-gateway-tls`
  (or delete the failing CertificateRequest).
- Rate-limited, with expiry within days: point the issuer at Let's Encrypt
  staging temporarily to confirm the fix works without spending the limit,
  then switch back. If time is short, upload a certificate from another CA as
  the Secret and remove the issuer annotation until things are stable.

## Escalation

- Less than 72 hours to expiry and not renewing: page the platform on-call.
- DNS or edge problems outside the cluster: escalate to whoever owns the DNS
  zone or WAF.
