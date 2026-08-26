# dev-ops — `main`. A project's branch fills in PROJECT and the backend directory.
#
# There is deliberately no `make up`. The backend's tests start a real database binary
# that arrives as a build dependency, so there is nothing to install and nothing to
# start. A `make up` that boots an unused service is a trap, not a reference.

PROJECT ?= CHANGE_ME
PREFIX  ?= $(shell echo $(PROJECT) | tr 'a-z-' 'A-Z_')
BACKEND ?= ../$(PROJECT)-backend

.PHONY: help test build psql check-env

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

test: ## Run the backend test suite (starts its own database)
	cd $(BACKEND) && ./gradlew test

build: ## Full backend build
	cd $(BACKEND) && ./gradlew clean build

psql: ## Open psql against the configured database
	@test -n "$$$(PREFIX)_DB_PASSWORD" || { echo "$(PREFIX)_DB_PASSWORD not set — see .env.example"; exit 1; }
	psql "$$$(PREFIX)_DB_URL"

# Derives the list from .env.example rather than hardcoding it, so a variable added there
# is checked here automatically. Hardcoded lists go stale silently: the previous version
# of this file still checked a provider that had been replaced months earlier.
check-env: ## List env vars .env.example declares but your shell does not have
	@sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' .env.example | while read -r v; do \
	  if [ -z "$$(printenv $$v)" ]; then echo "  missing: $$v"; fi; \
	done; echo "(see docs/env-matrix.md for what each one does)"
