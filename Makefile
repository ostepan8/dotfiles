.DEFAULT_GOAL := help
.PHONY: help check verify roles acl test apply dry-run fleet fleet-dry setup vault-backup hooks

help:  ## Show available targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

check:  ## Scan tracked files for secrets, fleet identifiers, private addresses
	@bash scripts/check-secrets.sh
	@bash scripts/check-exec-bits.sh

verify:  ## Prove the apply engine against a throwaway HOME (touches nothing)
	@bash scripts/verify-apply.sh

roles:  ## Check roles/ and the generated ACL agree
	@bash scripts/gen-nephos-acl.sh --check >/dev/null && echo "roles coherent"

acl:  ## Print the Tailscale ACL generated from roles/
	@bash scripts/gen-nephos-acl.sh

test: check verify roles  ## Run every check

dry-run:  ## Show what apply would change on THIS machine
	@bash apply.sh --dry-run

apply:  ## Put this machine's config in place
	@bash apply.sh

fleet:  ## Update every reachable machine to the current commit
	@bash scripts/fleet.sh

fleet-dry:  ## Show what each machine in the fleet would change
	@bash scripts/fleet.sh --dry-run

vault-backup:  ## Passphrase-encrypted off-machine backup of ~/.vault (interactive)
	@bash scripts/vault-backup.sh $(DEST)

setup:  ## Re-run the interview for anything not yet configured
	@bash scripts/setup.sh

hooks:  ## Install the pre-push hook that runs `make check`
	@mkdir -p .git/hooks
	@printf '#!/usr/bin/env sh\nexec make check\n' > .git/hooks/pre-push
	@chmod +x .git/hooks/pre-push
	@echo "installed .git/hooks/pre-push -> make check"
