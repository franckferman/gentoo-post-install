# Makefile for gentoo-post-install - local dev convenience (no root, no host changes).
#
#   make            same as `make check`
#   make check      full gate: syntax + lint + unit + integration + dry-run profiles + man
#   make syntax     bash -n on every shell file
#   make lint       shellcheck every shell file (override: make lint SHELLCHECK=/path/to/shellcheck)
#   make test       unit suite (tests/test.sh)
#   make integration  fake-root integration suite (tests/integration.sh)
#   make profiles   dry-run the script across all profiles, expect rc=0
#   make man        mandoc lint of the man page (skipped if mandoc is absent)
#   make help       list targets
#
# SHELLCHECK/MANDOC are overridable so the same gate runs locally and in CI.

SHELL       := /usr/bin/env bash
SHELLCHECK  ?= shellcheck
MANDOC      ?= mandoc
SCRIPT      := gentoo-post-install.sh
SHFILES     := $(SCRIPT) tests/test.sh tests/integration.sh tests/smoke.sh tests/boot-test.sh contrib/gentoo-post-install.bash
MANPAGE     := gentoo-post-install.1
PROFILES    := default desktop server hardened minimal opsec

.PHONY: all check syntax lint test integration profiles smoke man boot-test help

all: check

check: syntax lint test integration profiles smoke man
	@echo "==> all checks passed"

syntax:
	@echo "==> bash -n"
	@for f in $(SCRIPT) tests/test.sh tests/integration.sh tests/smoke.sh tests/boot-test.sh; do bash -n "$$f" || exit 1; done

lint:
	@echo "==> shellcheck ($(SHELLCHECK))"
	@command -v $(SHELLCHECK) >/dev/null 2>&1 || { echo "shellcheck not found; set SHELLCHECK=/path/to/shellcheck" >&2; exit 1; }
	@$(SHELLCHECK) $(SHFILES)

test:
	@echo "==> unit tests"
	@bash tests/test.sh

integration:
	@echo "==> integration tests"
	@bash tests/integration.sh

profiles:
	@echo "==> dry-run every profile (expect rc=0)"
	@for p in $(PROFILES); do \
		printf '  --profile %-9s ' "$$p"; \
		if ./$(SCRIPT) --dry-run --yes --no-banner --profile "$$p" >/dev/null 2>&1; then \
			echo ok; \
		else \
			echo FAIL; exit 1; \
		fi; \
	done

smoke:
	@echo "==> dry-run smoke matrix (kernel/accounts/desktop/opsec flag combos)"
	@bash tests/smoke.sh

man:
	@if command -v $(MANDOC) >/dev/null 2>&1; then \
		echo "==> mandoc lint"; \
		$(MANDOC) -Tlint -Wwarning $(MANPAGE); \
	else \
		echo "==> mandoc not installed, skipping man lint"; \
	fi

boot-test:
	@echo "==> QEMU/KVM kernel boot-test (hardened cmdline). Needs qemu + gcc; KVM if available."
	@bash tests/boot-test.sh $(BOOT_ARGS)

help:
	@echo "targets: check (default), syntax, lint, test, integration, profiles, smoke, man, boot-test"
