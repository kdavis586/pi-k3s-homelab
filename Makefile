-include .make-vars

ANSIBLE := $(shell command -v ansible-playbook 2>/dev/null || echo ~/.local/bin/ansible-playbook) -i ansible/inventory.yaml
KUBECONFIG := $(HOME)/.kube/config-pi-k3s
KUBECTL := kubectl --kubeconfig $(KUBECONFIG)

.PHONY: help generate setup install-k3s deploy status logs

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

deploy: ## Apply all k8s/ manifests to the cluster
	$(ANSIBLE) ansible/playbooks/deploy.yaml

status: ## Show node and pod status
	$(KUBECTL) get nodes,pods,svc,pvc -A

# ── Debugging ────────────────────────────────────────────────────────────────

logs: ## Tail Jellyfin logs
	$(KUBECTL) logs -n jellyfin -l app=jellyfin -f

ssh-%: ## SSH into any node by name  e.g. make ssh-the-bakery
	ssh ubuntu@$(shell ansible-inventory -i ansible/inventory.yaml --host $* | python3 -c "import sys,json; print(json.load(sys.stdin)['ansible_host'])")
