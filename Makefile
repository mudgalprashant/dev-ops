.PHONY: help test build psql check-env

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# There is no `make up`. Decision #14 dropped Docker for local development and #13
# dropped Redis; the backend's tests start a real Postgres binary that arrives as a
# Gradle dependency, so there is nothing to install and nothing to start.

test: ## Run the backend test suite (starts its own Postgres)
	cd ../drovi-backend && ./gradlew test

build: ## Full backend build
	cd ../drovi-backend && ./gradlew clean build

psql: ## Open psql against the configured database (needs DROVI_DB_* in your env)
	@test -n "$$DROVI_DB_PASSWORD" || { echo "DROVI_DB_PASSWORD not set — see .env.example"; exit 1; }
	psql "$$DROVI_DB_URL"

check-env: ## List env vars the backend expects but your shell does not have
	@for v in DROVI_DB_URL DROVI_DB_USERNAME DROVI_DB_PASSWORD DROVI_ANTHROPIC_API_KEY; do \
	  if [ -z "$$(printenv $$v)" ]; then echo "  missing: $$v"; fi; \
	done; echo "(see docs/env-matrix.md for what each one does)"
