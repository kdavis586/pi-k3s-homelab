ANSIBLE := ansible-playbook -i ansible/inventory.yaml
KUBECONFIG := $(HOME)/.kube/config-pi-k3s
KUBECTL := kubectl --kubeconfig $(KUBECONFIG)

.PHONY: help setup install-k3s deploy status logs ssh-server ssh-agent-1 ssh-agent-2

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

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

ssh-server: ## SSH into TheBakery (server)
	ssh ubuntu@192.168.1.100

ssh-agent-1: ## SSH into ApplePi (agent 1)
	ssh ubuntu@192.168.1.101

ssh-agent-2: ## SSH into PumpkinPi (agent 2)
	ssh ubuntu@192.168.1.102
