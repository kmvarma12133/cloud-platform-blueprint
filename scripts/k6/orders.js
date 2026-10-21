// Steady traffic for the local demos (scripts/load-test.sh runs it in-cluster).
// A constant arrival rate keeps requests per second fixed however slow the
// service gets, which is what makes KEDA scaling and canary analysis visible.
import http from "k6/http";
import { check } from "k6";

const BASE = __ENV.TARGET || "http://orders-api.orders-dev.svc";

export const options = {
  scenarios: {
    orders: {
      executor: "constant-arrival-rate",
      rate: Number(__ENV.RATE || 40),
      timeUnit: "1s",
      duration: __ENV.DURATION || "5m",
      preAllocatedVUs: 20,
      maxVUs: 100,
    },
  },
  // A new connection per request. kube-proxy balances connections, not
  // requests, and the canary is weighted by replica count: reused keep-alive
  // connections stay on the pods that existed when k6 started, so a canary
  // created later would receive no traffic and its analysis nothing to judge.
  noConnectionReuse: true,
  // No thresholds: the rollback demo expects errors, and judging them is the
  // canary analysis's job, not the load generator's.
};

export default function () {
  const created = http.post(
    `${BASE}/orders`,
    JSON.stringify({ sku: "DEMO-1", quantity: 1 }),
    { headers: { "Content-Type": "application/json" }, tags: { name: "POST /orders" } },
  );
  check(created, { "order created": (r) => r.status === 201 });
  // Orders live in each pod's memory, so read an endpoint every pod can answer.
  http.get(`${BASE}/version`, { tags: { name: "GET /version" } });
}
