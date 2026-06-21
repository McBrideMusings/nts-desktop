# NTS Radio — native macOS menu-bar app.
# All targets delegate to the Swift package in mac/.

.PHONY: help dev build app start install deploy clean

help: ## Show available targets
	@grep -E '^[a-z][a-zA-Z]*:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{ printf "  %-9s %s\n", $$1, $$2 }'

dev: ## Run the app from source (swift run)
	@$(MAKE) -C mac dev

build: ## Compile the release binary
	@$(MAKE) -C mac build

app: ## Assemble NTS Radio.app
	@$(MAKE) -C mac app

start: ## Build the .app and launch it
	@$(MAKE) -C mac run

install: ## Install NTS Radio.app to /Applications
	@$(MAKE) -C mac install

deploy: ## Build a distributable NTS Radio.dmg
	@$(MAKE) -C mac dmg

clean: ## Remove build artifacts
	@$(MAKE) -C mac clean
