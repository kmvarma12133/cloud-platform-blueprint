"""orders-api: a small reference service used to exercise the platform.

It is intentionally simple. The point of this repo is the delivery platform
around it: build, scan, sign, deploy (GitOps), progressive rollout, and
SLO-based observability.
"""

from __future__ import annotations

import logging
import os
import random
import time
import uuid

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, Field

from .telemetry import configure_logging, configure_tracing

SERVICE_NAME = os.getenv("SERVICE_NAME", "orders-api")
SERVICE_VERSION = os.getenv("SERVICE_VERSION", "0.0.0-dev")

# Fault injection for the canary rollback demo: scripts/break-canary.sh builds an
# image with this set. Zero by default. Probes and /metrics are exempt, so a
# faulty pod stays Ready and the failure shows up only in the RED metrics, which
# is exactly what the canary analysis has to catch.
FAULT_ERROR_RATE = float(os.getenv("FAULT_ERROR_RATE", "0"))
_FAULT_EXEMPT = {"/healthz", "/readyz", "/metrics"}


def inject_faults(request: Request) -> None:
    # A dependency rather than middleware so it runs after routing and the
    # resulting 500s are still labelled with the real route template.
    if FAULT_ERROR_RATE > 0 and request.url.path not in _FAULT_EXEMPT:
        if random.random() < FAULT_ERROR_RATE:  # noqa: S311 - not used for crypto
            raise HTTPException(status_code=500, detail="injected fault")


configure_logging()
log = logging.getLogger(SERVICE_NAME)

app = FastAPI(title=SERVICE_NAME, version=SERVICE_VERSION, dependencies=[Depends(inject_faults)])
configure_tracing(app, SERVICE_NAME, SERVICE_VERSION)

# RED metrics. Label cardinality is kept low on purpose: route template, not raw path.
REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests processed",
    ["method", "route", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "route"],
    # 0.3 matches the latency SLO threshold so the SLI counts it exactly.
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.3, 0.5, 1.0, 2.5, 5.0),
)


class OrderIn(BaseModel):
    sku: str = Field(min_length=1, max_length=64)
    quantity: int = Field(gt=0, le=1000)


class Order(OrderIn):
    id: str


# In-memory store. A real service would use a database; persistence is out of scope here.
_ORDERS: dict[str, Order] = {}
_READY = {"value": True}


@app.middleware("http")
async def record_metrics(request: Request, call_next):
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        route_path = getattr(route, "path", "unmatched")
        if route_path != "/metrics":
            elapsed = time.perf_counter() - start
            REQUESTS.labels(request.method, route_path, str(status)).inc()
            LATENCY.labels(request.method, route_path).observe(elapsed)


@app.get("/healthz", include_in_schema=False)
def healthz() -> dict:
    """Liveness: the process is up."""
    return {"status": "ok"}


@app.get("/readyz", include_in_schema=False)
def readyz(response: Response) -> dict:
    """Readiness: the pod should receive traffic."""
    if not _READY["value"]:
        response.status_code = 503
        return {"status": "draining"}
    return {"status": "ready"}


@app.get("/metrics", include_in_schema=False)
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/version")
def version() -> dict:
    return {"service": SERVICE_NAME, "version": SERVICE_VERSION}


@app.post("/orders", status_code=201, response_model=Order)
def create_order(order: OrderIn) -> Order:
    created = Order(id=str(uuid.uuid4()), **order.model_dump())
    _ORDERS[created.id] = created
    log.info("order created", extra={"order_id": created.id, "sku": created.sku})
    return created


@app.get("/orders/{order_id}", response_model=Order)
def get_order(order_id: str) -> Order:
    order = _ORDERS.get(order_id)
    if order is None:
        raise HTTPException(status_code=404, detail="order not found")
    return order
