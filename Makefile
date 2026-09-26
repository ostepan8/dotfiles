.DEFAULT_GOAL := help
.PHONY: help check verify dfw-test roles acl test apply dry-run fleet fleet-dry setup vault-backup hooks

help:  ## Show available targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

check:  ## Scan tracked files for secrets, fleet identifiers, private addresses
	@bash scripts/check-secrets.sh
	@bash scripts/check-exec-bits.sh

verify:  ## Prove the apply engine against a throwaway HOME (touches nothing)
	@bash scripts/verify-apply.sh

dfw-test:  ## Test the dfw worktree tool and its JSON merge driver (throwaway repos)
	@python3 base/agents/skills/dotfiles-worktree/tests/test_json_merge.py 2>&1 | tail -1
	@bash base/agents/skills/dotfiles-worktree/tests/test_dfw.sh | tail -1

roles:  ## Check roles/ and the generated ACL agree
	@bash scripts/gen-nephos-acl.sh --check >/dev/null && echo "roles coherent"

doctor:  ## Assert the RUNNING system matches the config (live state, not files)
	@bash scripts/doctor.sh

cheatsheet:  ## Regenerate the keybinding sections of docs/cheatsheet.html from docs/keys.tsv
	@bash scripts/gen-cheatsheet.sh

acl:  ## Print the Tailscale ACL generated from roles/
	@bash scripts/gen-nephos-acl.sh

test: check verify dfw-test roles doctor  ## Run every check

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
	@git config merge.dfjson.name "three-way JSON merge (dotfiles-worktree)"
	@git config merge.dfjson.driver "python3 '$(CURDIR)/base/agents/skills/dotfiles-worktree/scripts/json-merge.py' %O %A %B %P"
	@echo "registered the dfjson merge driver"
