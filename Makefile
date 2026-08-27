# Cellbreak — the commands worth remembering.
# The repo is a pnpm workspace; every target below is a thin, honest wrapper.

.DEFAULT_GOAL := help
REPO := ../cellbreak

.PHONY: help install test check build dev serve deploy tail

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

install: ## Install workspace dependencies
	cd $(REPO) && pnpm install

test: ## Run the engine test suite
	cd $(REPO) && pnpm test

check: ## Typecheck every package
	cd $(REPO) && pnpm typecheck

build: ## Build the client (REQUIRED before serve or deploy)
	cd $(REPO) && pnpm --filter @cellbreak/web build

dev: ## Client only, with hot reload, on :5173 — no /api, so no online play
	cd $(REPO) && pnpm --filter @cellbreak/web dev

serve: build ## Worker + Durable Objects + the built client on :8788
	cd $(REPO) && pnpm --filter @cellbreak/server dev

deploy: test check build ## Publish the Worker and the client together
	cd $(REPO) && pnpm --filter @cellbreak/server deploy

tail: ## Stream production logs
	cd $(REPO)/apps/server && pnpm exec wrangler tail
