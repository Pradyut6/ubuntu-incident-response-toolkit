SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
.PHONY: help doctor test syntax lint format-check
help:
	@printf 'Targets: doctor | test | syntax | lint | format-check\n'
doctor:
	@./bin/uir doctor
test:
	@bash tests/run-all.sh
syntax:
	@bash -n bin/uir lib/*.sh tests/smoke.sh tests/integration/*.sh tests/unit/redaction.sh
lint:
	@shellcheck -S warning bin/uir lib/*.sh tests/smoke.sh tests/integration/*.sh tests/unit/redaction.sh
format-check:
	@shfmt -d -i 4 bin/uir lib/*.sh tests/smoke.sh tests/integration/*.sh tests/unit/redaction.sh
