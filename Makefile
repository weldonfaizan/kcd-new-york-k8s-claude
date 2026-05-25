# Makefile for KCD New York K8s Claude Demo
#
# Quick start:
#   make all          # build images, create cluster, load images
#   make run-03       # run concept 03 (sidecar proxy)
#   make logs-03      # tail claude-code logs for 03
#   make help         # list all targets
#
# Prerequisites: docker, kind, kubectl, jq, envsubst
# Credentials:   .env file with ANTHROPIC_API_KEY, GH_TOKEN, TESTING_REPO

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
CLUSTER_NAME   ?= claude-demo
GOPROXY        ?= direct

CLAUDE_IMAGE   := claude-code:latest
PROXY_IMAGE    := credential-proxy:latest

# ---------------------------------------------------------------------------
# Phony targets
# ---------------------------------------------------------------------------
.PHONY: help all cluster \
	build build-claude build-proxy \
	load load-claude load-proxy \
	deploy-02 deploy-03 deploy-04 deploy-05 \
	run-02 run-03 run-04 run-05 \
	logs-02 logs-03 logs-04 logs-05 \
	proxy-logs-03 proxy-logs-04 proxy-logs-05 \
	clean-02 clean-03 clean-04 clean-05 clean \
	test test-02 test-03 test-06 test-07

# ---------------------------------------------------------------------------
# Default target
# ---------------------------------------------------------------------------
help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) \
		| awk -F ':.*## ' '{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
all: build cluster load ## Build images, create cluster, load images

cluster: ## Create/refresh Kind cluster, namespaces, and secrets from .env
	@bash 01-kind-cluster/scripts/create-cluster.sh

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build: build-claude build-proxy ## Build both Docker images

build-claude: ## Build claude-code image
	docker build -t $(CLAUDE_IMAGE) 02-claude-k8s-job/

build-proxy: ## Build credential-proxy image
	docker build -t $(PROXY_IMAGE) \
		$(if $(GOPROXY),--build-arg GOPROXY=$(GOPROXY)) \
		proxy/

# ---------------------------------------------------------------------------
# Load images into Kind
# ---------------------------------------------------------------------------
load: load-claude load-proxy ## Load both images into Kind cluster

load-claude: ## Load claude-code image into Kind
	kind load docker-image $(CLAUDE_IMAGE) --name $(CLUSTER_NAME)

load-proxy: ## Load credential-proxy image into Kind
	kind load docker-image $(PROXY_IMAGE) --name $(CLUSTER_NAME)

# ---------------------------------------------------------------------------
# Deploy (apply manifests without deleting old jobs)
# ---------------------------------------------------------------------------
ENVSUBST_VARS := $$CLAUDE_CODE_USE_BEDROCK $$AWS_REGION $$ANTHROPIC_API_KEY_PLACEHOLDER $$ANTHROPIC_MODEL $$TESTING_REPO

deploy-02: ## Apply 02-claude-k8s-job manifests
	@set -a && source .env && set +a && \
		envsubst '$(ENVSUBST_VARS)' < 02-claude-k8s-job/manifests/job.yaml \
		| kubectl apply -f -

deploy-03: ## Apply 03-sidecar-proxy manifests
	kubectl apply -f 03-sidecar-proxy/manifests/configmap.yaml
	@set -a && source .env && set +a && \
		envsubst '$(ENVSUBST_VARS)' < 03-sidecar-proxy/manifests/job.yaml \
		| kubectl apply -f -

deploy-04: ## Apply 04-code-reviewer manifests
	@set -a && source .env && set +a && \
		envsubst '$(ENVSUBST_VARS)' < 04-code-reviewer/manifests/configmap.yaml \
		| kubectl apply -f -
	kubectl apply -f 04-code-reviewer/manifests/proxy-configmap.yaml
	@set -a && source .env && set +a && \
		envsubst '$(ENVSUBST_VARS)' < 04-code-reviewer/manifests/job.yaml \
		| kubectl apply -f -

deploy-05: ## Apply 05-developer-agent manifests
	@set -a && source .env && set +a && \
		envsubst '$(ENVSUBST_VARS)' < 05-developer-agent/manifests/configmap.yaml \
		| kubectl apply -f -
	kubectl apply -f 05-developer-agent/manifests/proxy-configmap.yaml
	kubectl apply -f 05-developer-agent/manifests/pvc.yaml
	@set -a && source .env && set +a && \
		envsubst '$(ENVSUBST_VARS)' < 05-developer-agent/manifests/job.yaml \
		| kubectl apply -f -

# ---------------------------------------------------------------------------
# Run (delete old job, then deploy fresh)
# ---------------------------------------------------------------------------
run-02: ## Run 02: delete old job, apply manifests
	-kubectl delete job claude-hello -n 02-claude-k8s-job --ignore-not-found
	@$(MAKE) deploy-02

run-03: ## Run 03: delete old job, apply manifests
	-kubectl delete job claude-hello-secure -n 03-sidecar-proxy --ignore-not-found
	@$(MAKE) deploy-03

run-04: ## Run 04: delete old job, apply manifests
	-kubectl delete job claude-reviewer -n 04-code-reviewer --ignore-not-found
	@$(MAKE) deploy-04

run-05: ## Run 05: delete old job, apply manifests
	-kubectl delete job claude-developer -n 05-developer-agent --ignore-not-found
	@$(MAKE) deploy-05

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
logs-02: ## Tail claude-code logs for 02
	kubectl logs -f job/claude-hello -n 02-claude-k8s-job

logs-03: ## Tail claude-code logs for 03
	kubectl logs -f job/claude-hello-secure -c claude-code -n 03-sidecar-proxy

logs-04: ## Tail claude-code logs for 04
	kubectl logs -f job/claude-reviewer -c claude-code -n 04-code-reviewer

logs-05: ## Tail claude-code logs for 05
	kubectl logs -f job/claude-developer -c claude-code -n 05-developer-agent

proxy-logs-03: ## Tail proxy-sidecar logs for 03
	kubectl logs job/claude-hello-secure -c proxy-sidecar -n 03-sidecar-proxy

proxy-logs-04: ## Tail proxy-sidecar logs for 04
	kubectl logs job/claude-reviewer -c proxy-sidecar -n 04-code-reviewer

proxy-logs-05: ## Tail proxy-sidecar logs for 05
	kubectl logs job/claude-developer -c proxy-sidecar -n 05-developer-agent

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
clean-02: ## Delete job in 02
	-kubectl delete job claude-hello -n 02-claude-k8s-job --ignore-not-found

clean-03: ## Delete job in 03
	-kubectl delete job claude-hello-secure -n 03-sidecar-proxy --ignore-not-found

clean-04: ## Delete job in 04
	-kubectl delete job claude-reviewer -n 04-code-reviewer --ignore-not-found

clean-05: ## Delete job in 05
	-kubectl delete job claude-developer -n 05-developer-agent --ignore-not-found

clean: clean-02 clean-03 clean-04 clean-05 ## Delete all jobs across concepts

# ---------------------------------------------------------------------------
# Tests (run job, wait for success, verify output)
# ---------------------------------------------------------------------------
TIMEOUT ?= 120s

test: test-02 test-03 test-06 test-07 ## Run e2e tests for all concepts

test-02: ## Test concept 02: simple job
	@echo "=== Test 02: Simple Job ==="
	@$(MAKE) run-02
	@kubectl wait --for=condition=complete job/claude-hello -n 02-claude-k8s-job --timeout=$(TIMEOUT)
	@echo "PASS: 02 job completed"
	@kubectl logs -l job-name=claude-hello -n 02-claude-k8s-job | tail -3
	@echo ""

test-03: ## Test concept 03: sidecar proxy
	@echo "=== Test 03: Sidecar Proxy ==="
	@$(MAKE) run-03
	@kubectl wait --for=condition=complete job/claude-hello-secure -n 03-sidecar-proxy --timeout=$(TIMEOUT)
	@echo "PASS: 03 job completed"
	@kubectl logs -l job-name=claude-hello-secure -c claude-code -n 03-sidecar-proxy | tail -3
	@echo "Proxy: $$(kubectl logs -l job-name=claude-hello-secure -c proxy-sidecar -n 03-sidecar-proxy | grep -c 'ALLOWED') allowed, $$(kubectl logs -l job-name=claude-hello-secure -c proxy-sidecar -n 03-sidecar-proxy | grep -c 'BLOCKED') blocked"
	@echo ""

test-06: ## Test concept 06: KRO agent (requires KRO installed)
	@echo "=== Test 06: KRO Agent ===" && \
	if ! kubectl get crd resourcegraphdefinitions.kro.run >/dev/null 2>&1; then \
		echo "SKIP: KRO not installed"; echo ""; \
	else \
		kubectl apply -f 06-kro-agent/manifests/rgd.yaml && \
		echo "Waiting for CRD to be established..." && \
		for i in $$(seq 1 20); do kubectl get crd claudecodeagents.kro.run >/dev/null 2>&1 && break || sleep 2; done && \
		(kubectl patch claudecodeagent kro-test -n 06-kro-agent --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true) && \
		(kubectl delete claudecodeagent kro-test -n 06-kro-agent --ignore-not-found --timeout=10s 2>/dev/null || true) && \
		(kubectl delete job kro-test -n 06-kro-agent --ignore-not-found 2>/dev/null || true) && \
		(kubectl delete pvc kro-test-workspace kro-test-memory -n 06-kro-agent --ignore-not-found 2>/dev/null || true) && \
		(kubectl delete pods -l job-name=kro-test -n 06-kro-agent --ignore-not-found 2>/dev/null || true) && \
		sleep 3 && \
		set -a && source .env && set +a && \
		envsubst '$(ENVSUBST_VARS)' < 06-kro-agent/manifests/test-instance.yaml \
			| kubectl apply -f - && \
		echo "Waiting for job to be created by KRO..." && \
		(for i in $$(seq 1 30); do kubectl get job kro-test -n 06-kro-agent >/dev/null 2>&1 && break || sleep 2; done) && \
		kubectl wait --for=condition=complete job/kro-test -n 06-kro-agent --timeout=$(TIMEOUT) && \
		echo "PASS: 06 KRO job completed" && \
		kubectl logs -l job-name=kro-test -c claude-code -n 06-kro-agent | tail -5 && \
		echo ""; \
	fi

test-07: ## Test concept 07: sandbox (requires KRO + agent-sandbox CRD)
	@echo "=== Test 07: Sandbox ===" && \
	if ! kubectl get crd sandboxes.agents.x-k8s.io >/dev/null 2>&1; then \
		echo "SKIP: agent-sandbox CRD not installed"; echo ""; \
	else \
		kubectl apply -f 07-sandbox/manifests/rgd-runner.yaml && \
		kubectl apply -f 07-sandbox/manifests/rgd.yaml && \
		echo "Waiting for CRDs to be established..." && \
		for i in $$(seq 1 20); do kubectl get crd claudecodeagentsandboxes.kro.run >/dev/null 2>&1 && break || sleep 2; done && \
		(kubectl delete claudecodeagentsandbox sandbox-test -n 07-sandbox --ignore-not-found 2>/dev/null || true) && \
		sleep 3 && \
		(set -a && source .env && set +a && \
			envsubst '$(ENVSUBST_VARS)' < 07-sandbox/manifests/test-standalone.yaml \
			| kubectl apply -f -) && \
		echo "Waiting for sandbox to be created by KRO..." && \
		(for i in $$(seq 1 30); do kubectl get sandbox sandbox-test-sandbox -n 07-sandbox >/dev/null 2>&1 && break || sleep 2; done) && \
		kubectl wait --for=condition=Finished sandbox/sandbox-test-sandbox -n 07-sandbox --timeout=300s && \
		echo "PASS: 07 sandbox completed" && \
		kubectl logs sandbox-test-sandbox -c claude-code -n 07-sandbox | tail -5 && \
		echo ""; \
	fi
