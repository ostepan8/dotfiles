.DEFAULT_GOAL := help
.PHONY: help check verify test apply dry-run hooks

help:  ## Show available targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

check:  ## Scan tracked files for secrets, fleet identifiers, private addresses
	@bash scripts/check-secrets.sh

verify:  ## Prove the apply engine against a throwaway HOME (touches nothing)
	@bash scripts/verify-apply.sh

test: check verify  ## Run every check

dry-run:  ## Show what apply would change on THIS machine
	@bash apply.sh --dry-run

apply:  ## Put this machine's config in place
	@bash apply.sh

hooks:  ## Install the pre-push hook that runs `make check`
	@mkdir -p .git/hooks
	@printf '#!/usr/bin/env sh\nexec make check\n' > .git/hooks/pre-push
	@chmod +x .git/hooks/pre-push
	@echo "installed .git/hooks/pre-push -> make check"
