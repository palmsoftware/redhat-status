.PHONY: lint fix-lint help

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

lint: ## Check shell scripts with shellcheck and shfmt
	@echo "Running shellcheck..."
	@shellcheck scripts/*.sh
	@echo "✅ shellcheck passed"
	@echo "Running shfmt..."
	@shfmt -d -i 2 -ci scripts/*.sh
	@echo "✅ shfmt passed"

fix-lint: ## Auto-fix shell script formatting
	@shfmt -w -i 2 -ci scripts/*.sh
	@echo "✅ Formatting fixed"
