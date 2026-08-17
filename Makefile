.DEFAULT_GOAL := help
.PHONY: help check hooks

help:  ## Show available targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

check:  ## Scan tracked files for secrets, fleet identifiers, private addresses
	@bash scripts/check-secrets.sh

hooks:  ## Install the pre-push hook that runs `make check`
	@mkdir -p .git/hooks
	@printf '#!/usr/bin/env sh\nexec make check\n' > .git/hooks/pre-push
	@chmod +x .git/hooks/pre-push
	@echo "installed .git/hooks/pre-push -> make check"
