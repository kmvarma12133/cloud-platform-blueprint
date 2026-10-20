# Run `make` for the list of targets. Tools are expected on PATH; their exact
# versions are pinned in CI (.github/workflows) and listed in the README.
.DEFAULT_GOAL := help
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --no-print-directory

PYTHON ?= python3
# Interpreter with app/requirements-dev.txt installed (defaults to PYTHON).
APP_PYTHON ?= $(PYTHON)
IMAGE ?= ghcr.io/OWNER/orders-api
TAG ?= $(shell git rev-parse --short HEAD)
TF_DIRS := $(wildcard infra/modules/*) infra/bootstrap

##@ Develop

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} \
	  /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } \
	  /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

.PHONY: setup
setup: ## Create .venv with the app and tooling dependencies
	$(PYTHON) -m venv .venv
	.venv/bin/pip install -r app/requirements-dev.txt -r scripts/requirements.txt
	@echo "Now run: source .venv/bin/activate"

.PHONY: lint
lint: ## Ruff, yamllint, terraform/terragrunt fmt, opa fmt
	cd app && $(APP_PYTHON) -m ruff check . && $(APP_PYTHON) -m ruff format --check .
	$(APP_PYTHON) -m ruff check --config app/pyproject.toml scripts
	$(APP_PYTHON) -m ruff format --check --config app/pyproject.toml scripts
	$(PYTHON) -m yamllint .
	terraform fmt -check -recursive infra
	cd infra/live && terragrunt hcl format --check
	opa fmt --list --fail platform/policies/rego

.PHONY: test
test: ## App unit tests with coverage (fails under 80%)
	cd app && $(APP_PYTHON) -m pytest --cov=orders_api --cov-report=term-missing --cov-fail-under=80

.PHONY: build
build: ## Build the orders-api image as $(IMAGE):$(TAG)
	docker build --build-arg VERSION=$(TAG) -t $(IMAGE):$(TAG) app

##@ Validate

.PHONY: tf-validate
tf-validate: ## terraform validate, tflint, Terragrunt inputs, terraform-docs drift, checkov
	@for dir in $(TF_DIRS); do \
	  echo "== $$dir"; \
	  (cd $$dir && terraform init -backend=false -input=false >/dev/null && terraform validate); \
	done
	tflint --init >/dev/null && tflint --recursive
	cd infra/live && TG_TF_PATH=terraform terragrunt hcl validate --inputs --strict
	@for dir in infra/modules/*/; do \
	  terraform-docs -c .terraform-docs.yml --output-check $$dir >/dev/null || { echo "stale docs in $$dir: run make docs"; exit 1; }; \
	done
	checkov --directory infra --framework terraform --compact --quiet

.PHONY: k8s-validate
k8s-validate: ## Charts and manifests (kubeconform), Gatekeeper drift, Prometheus rule tests
	scripts/validate-k8s.sh
	$(PYTHON) scripts/build-gatekeeper.py --check
	PYTHON=$(PYTHON) scripts/check-prometheus-rules.sh

.PHONY: k8s-validate-addons
k8s-validate-addons: ## Render every upstream add-on chart with our values (needs network)
	$(PYTHON) scripts/render-addons.py

.PHONY: policy-test
policy-test: ## Rego unit tests
	opa fmt --list --fail platform/policies/rego
	opa check --strict platform/policies/rego
	opa test platform/policies/rego -v

.PHONY: docs
docs: ## Regenerate module READMEs and Gatekeeper templates
	@for dir in infra/modules/*/; do terraform-docs -c .terraform-docs.yml $$dir; done
	$(PYTHON) scripts/build-gatekeeper.py

##@ Local demo (kind)

.PHONY: local-up
local-up: ## Create the kind cluster and let Argo CD install the platform
	scripts/local-up.sh

.PHONY: local-down
local-down: ## Delete the kind cluster
	scripts/local-down.sh

.PHONY: load-test
load-test: ## Steady traffic at orders-api in dev (RATE, DURATION)
	FOLLOW=1 scripts/load-test.sh

.PHONY: demo-canary
demo-canary: ## Roll a healthy new version through the canary steps
	scripts/demo-canary.sh

.PHONY: demo-rollback
demo-rollback: ## Roll a broken version and watch the analysis abort it
	scripts/break-canary.sh

.PHONY: demo-reset
demo-reset: ## Put the dev Rollout back on its stable version
	scripts/demo-reset.sh
