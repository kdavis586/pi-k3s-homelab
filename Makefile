-include .make-vars

ANSIBLE := $(shell command -v ansible-playbook 2>/dev/null || echo ~/.local/bin/ansible-playbook) -i ansible/inventory.yaml
KUBECONFIG := $(HOME)/.kube/config-pi-k3s
KUBECTL := kubectl --kubeconfig $(KUBECONFIG)

# GitHub App credentials (override via env or .make-vars)
FLUX_APP_ID        ?=
FLUX_INSTALLATION_ID ?=
FLUX_APP_KEY       ?= $(HOME)/.config/flux/github-app.pem

.PHONY: help generate setup install-k3s deploy status logs bootstrap-flux flux-status flux-reconcile

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Config generation ────────────────────────────────────────────────────────

generate: ## Regenerate cloud-init + k8s configs from ansible/group_vars/all.yaml
	$(ANSIBLE) ansible/playbooks/generate-configs.yaml

# ── Provisioning ────────────────────────────────────────────────────────────

setup: ## Run base OS setup on all nodes (run once after first boot)
	$(ANSIBLE) ansible/playbooks/base-setup.yaml

install-k3s: ## Install K3s server + agents and fetch kubeconfig
	$(ANSIBLE) ansible/playbooks/k3s-install.yaml

# ── Day-to-day ───────────────────────────────────────────────────────────────

deploy: ## Apply all k8s/ manifests to the cluster (use before Flux is bootstrapped)
	$(ANSIBLE) ansible/playbooks/deploy.yaml

# ── Flux CD ───────────────────────────────────────────────────────────────────

bootstrap-flux: ## Bootstrap Flux CD using a GitHub App (set FLUX_APP_ID, FLUX_INSTALLATION_ID, FLUX_APP_KEY)
	@command -v flux >/dev/null 2>&1 || { echo "Error: flux CLI not found. Run: brew install fluxcd/tap/flux"; exit 1; }
	@[ -n "$(FLUX_APP_ID)" ] || { echo "Error: FLUX_APP_ID not set. Add to .make-vars or export before running."; exit 1; }
	@[ -n "$(FLUX_INSTALLATION_ID)" ] || { echo "Error: FLUX_INSTALLATION_ID not set. Add to .make-vars or export before running."; exit 1; }
	@[ -f "$(FLUX_APP_KEY)" ] || { echo "Error: GitHub App private key not found at $(FLUX_APP_KEY)"; exit 1; }
	flux bootstrap github \
		--owner=kdavis586 \
		--repository=pi-k3s-homelab \
		--branch=main \
		--path=flux \
		--app-id=$(FLUX_APP_ID) \
		--app-installation-id=$(FLUX_INSTALLATION_ID) \
		--app-private-key=$(FLUX_APP_KEY) \
		--version=v2.4.0 \
		--kubeconfig=$(KUBECONFIG)

flux-status: ## Show Flux reconciliation status across all resources
	flux get all --kubeconfig $(KUBECONFIG)

flux-reconcile: ## Force Flux to re-sync from git immediately
	flux reconcile source git flux-system --kubeconfig $(KUBECONFIG)
	flux reconcile kustomization flux-system --kubeconfig $(KUBECONFIG)

status: ## Show node and pod status
	$(KUBECTL) get nodes,pods,svc,pvc -A

# ── Debugging ────────────────────────────────────────────────────────────────

logs: ## Tail Jellyfin logs
	$(KUBECTL) logs -n jellyfin -l app=jellyfin -f

ssh-%: ## SSH into any node by name  e.g. make ssh-the-bakery
	ssh ubuntu@$(shell ansible-inventory -i ansible/inventory.yaml --host $* | python3 -c "import sys,json; print(json.load(sys.stdin)['ansible_host'])")
