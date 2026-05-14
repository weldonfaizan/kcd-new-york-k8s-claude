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
GOPROXY        ?=

CLAUDE_IMAGE   := claude-code:latest
PROXY_IMAGE    := credential-proxy:latest

# ---------------------------------------------------------------------------
# Phony targets
# ---------------------------------------------------------------------------
.PHONY: help all cluster \
	build build-claude build-proxy \
	load load-claude load-proxy \
	deploy-03 deploy-04 deploy-05 \
	run-03 run-04 run-05 \
	logs-03 logs-04 logs-05 \
	proxy-logs-03 proxy-logs-04 proxy-logs-05 \
	clean-03 clean-04 clean-05 clean

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
deploy-03: ## Apply 03-sidecar-proxy manifests
	kubectl apply -f 03-sidecar-proxy/manifests/configmap.yaml
	kubectl apply -f 03-sidecar-proxy/manifests/job.yaml

deploy-04: ## Apply 04-code-reviewer manifests (envsubst for TESTING_REPO)
	@set -a && source .env && set +a && \
		envsubst '$$TESTING_REPO' < 04-code-reviewer/manifests/configmap.yaml \
		| kubectl apply -f -
	kubectl apply -f 04-code-reviewer/manifests/proxy-configmap.yaml
	kubectl apply -f 04-code-reviewer/manifests/job.yaml

deploy-05: ## Apply 05-developer-agent manifests (envsubst for TESTING_REPO)
	@set -a && source .env && set +a && \
		envsubst '$$TESTING_REPO' < 05-developer-agent/manifests/configmap.yaml \
		| kubectl apply -f -
	kubectl apply -f 05-developer-agent/manifests/proxy-configmap.yaml
	kubectl apply -f 05-developer-agent/manifests/pvc.yaml
	kubectl apply -f 05-developer-agent/manifests/job.yaml

# ---------------------------------------------------------------------------
# Run (delete old job, then deploy fresh)
# ---------------------------------------------------------------------------
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
clean-03: ## Delete job in 03
	-kubectl delete job claude-hello-secure -n 03-sidecar-proxy --ignore-not-found

clean-04: ## Delete job in 04
	-kubectl delete job claude-reviewer -n 04-code-reviewer --ignore-not-found

clean-05: ## Delete job in 05
	-kubectl delete job claude-developer -n 05-developer-agent --ignore-not-found

clean: clean-03 clean-04 clean-05 ## Delete all jobs across concepts
