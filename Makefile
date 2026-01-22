SHELL := /bin/bash
MKDIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

help:
	@echo help

.PHONY: docs

docs: ## Generate Sphinx docs
	$(MAKE) -C docs clean html


