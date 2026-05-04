# -------- CONFIG --------
NIXCONF := /etc/nixos
CURRENTDIR := nixos
BACKUPDIR := /etc/nixos.backups
TIMESTAMP := $(shell date +"%Y-%m-%dT%H-%M-%S")
FORCE ?= 0

# -------- COLORS --------
RED     := \033[1;31m
GREEN   := \033[1;32m
YELLOW  := \033[1;33m
RESET   := \033[0m

# -------- TARGETS --------

import:
	@printf "%b\n" "$(YELLOW)Importing current /etc/nixos → $(CURRENTDIR)$(RESET)"
	@sudo mkdir -p $(CURRENTDIR)
	@sudo cp -rT $(NIXCONF) $(CURRENTDIR)
	@printf "%b\n" "$(GREEN)Imported current system configuration.$(RESET)"

check:
	@cd $(CURRENTDIR); \
	printf "%b\n" "$(YELLOW)Checking for configuration drift...$(RESET)"; \
	found=0; \
	for f in $$(find . -type f); do \
		if [ -f "$(NIXCONF)/$$f" ]; then \
			localhash=$$(sha256sum "$$f" | cut -d' ' -f1); \
			sysconfhash=$$(sudo sha256sum "$(NIXCONF)/$$f" | cut -d' ' -f1); \
			if [ "$$localhash" != "$$sysconfhash" ]; then \
				found=1; \
				printf "%b\n" "\n$(YELLOW)FILE: $(RESET)$$f"; \
				printf "%b\n" "  $(GREEN)LIVE:  $(RESET)$$sysconfhash"; \
				printf "%b\n" "  $(RED)LOCAL: $(RESET)$$localhash"; \
				sudo diff -u --color=always "$(NIXCONF)/$$f" "$$f" || true; \
			fi; \
		else \
			printf "%b\n" "\n$(RED)MISSING in /etc/nixos: $(RESET)$$f"; \
		fi; \
	done; \
	if [ "$$found" -eq 0 ]; then \
		printf "%b\n" "$(GREEN)No differences detected.$(RESET)"; \
	else \
		printf "%b\n" "$(YELLOW)Differences found above.$(RESET)"; \
	fi

backup:
	@printf "%b\n" "$(YELLOW)Creating backup of $(NIXCONF)$(RESET)"
	@sudo mkdir -p $(BACKUPDIR)
	@sudo cp -rT $(NIXCONF) $(BACKUPDIR)/backup-$(TIMESTAMP)
	@printf "%b\n" "$(GREEN)Backup saved to $(BACKUPDIR)/backup-$(TIMESTAMP)$(RESET)"

backups:
	@printf "%b\n" "$(YELLOW)Available backups:$(RESET)"
	@sudo ls -1 $(BACKUPDIR) | sort || true

revert:
	@printf "%b\n" "$(YELLOW)Available backups:$(RESET)"
	@sudo ls -1 $(BACKUPDIR) | sort || true
	@printf "\nEnter backup name to restore (leave blank for latest): "; \
	read name; \
	if [ -z "$$name" ]; then \
		name=$$(sudo ls -1t $(BACKUPDIR) | head -n1); \
	fi; \
	if [ -d "$(BACKUPDIR)/$$name" ]; then \
		printf "%b\n" "$(RED)Restoring backup $$name → $(NIXCONF)$(RESET)"; \
		sudo rm -rf $(NIXCONF); \
		sudo mkdir -p $(NIXCONF); \
		sudo cp -rT "$(BACKUPDIR)/$$name" "$(NIXCONF)"; \
		printf "%b\n" "$(GREEN)Reverted to backup: $$name$(RESET)"; \
	else \
		printf "%b\n" "$(RED)Backup not found: $$name$(RESET)"; \
	fi

install:
	@if [ "$(FORCE)" = "1" ]; then \
		printf "%b\n" "$(YELLOW)FORCE=1: creating backup automatically.$(RESET)"; \
		$(MAKE) --no-print-directory backup; \
	else \
		printf "%b" "$(YELLOW)Would you like to create a backup before installation? [Y/n]: $(RESET)"; \
		read ans; \
		case "$$ans" in \
			n|N) printf "%b\n" "$(YELLOW)Skipping backup.$(RESET)";; \
			*) $(MAKE) --no-print-directory backup;; \
		esac; \
	fi; \
	printf "%b\n" "$(YELLOW)Checking for configuration drift...$(RESET)"; \
	changed=$$(cd $(CURRENTDIR); \
		found=0; \
		for f in $$(find . -type f); do \
			if [ -f "$(NIXCONF)/$$f" ]; then \
				localhash=$$(sha256sum "$$f" | cut -d' ' -f1); \
				sysconfhash=$$(sudo sha256sum "$(NIXCONF)/$$f" | cut -d' ' -f1); \
				[ "$$localhash" != "$$sysconfhash" ] && found=1 && echo "$$f"; \
			else found=1 && echo "$$f"; fi; \
		done; echo $$found); \
	if [ "$$changed" = "0" ]; then \
		printf "%b\n" "$(GREEN)No differences detected. Nothing to install.$(RESET)"; \
		exit 0; \
	fi; \
	if [ "$(FORCE)" = "1" ]; then \
		printf "%b\n" "$(YELLOW)Starting forced install...$(RESET)"; \
	else \
		printf "%b\n" "$(YELLOW)Starting interactive install...$(RESET)"; \
	fi; \
	all=false; installed=0; skipped=0; total=0; \
	cd $(CURRENTDIR); \
	for f in $$(find . -type f); do \
		total=$$((total+1)); \
		if [ -f "$(NIXCONF)/$$f" ]; then \
			localhash=$$(sha256sum "$$f" | cut -d' ' -f1); \
			sysconfhash=$$(sudo sha256sum "$(NIXCONF)/$$f" | cut -d' ' -f1); \
			if [ "$$localhash" != "$$sysconfhash" ]; then \
				printf "%b\n" "\n$(YELLOW)FILE:$(RESET) $$f"; \
				sudo diff -u --color=always "$(NIXCONF)/$$f" "$$f" || true; \
				if [ "$(FORCE)" = "1" ]; then \
					ans="y"; \
				elif [ "$$all" = false ]; then \
					printf "Install this file? [y/n/a/q]: "; read ans; \
				else ans="y"; fi; \
				case "$$ans" in \
					y|Y) sudo cp --parents "$$f" $(NIXCONF)/; installed=$$((installed+1));; \
					a|A) all=true; sudo cp --parents "$$f" $(NIXCONF)/; installed=$$((installed+1));; \
					q|Q) break;; \
					*) printf "%b\n" "$(YELLOW)→ Skipping $(RESET)$$f"; skipped=$$((skipped+1));; \
				esac; \
			fi; \
		else \
			printf "%b\n" "$(RED)NEW FILE:$(RESET) $$f"; \
			if [ "$(FORCE)" = "1" ] || [ "$$all" = true ]; then \
				ans="y"; \
			else \
				printf "Copy to /etc/nixos? [y/n/a/q]: "; read ans; \
			fi; \
			case "$$ans" in \
				y|Y) sudo cp --parents "$$f" $(NIXCONF)/; installed=$$((installed+1));; \
				a|A) all=true; sudo cp --parents "$$f" $(NIXCONF)/; installed=$$((installed+1));; \
				q|Q) break;; \
				*) printf "%b\n" "$(YELLOW)→ Skipping $(RESET)$$f"; skipped=$$((skipped+1));; \
			esac; \
		fi; \
	done; \
	printf "%b\n" "\n$(YELLOW)Summary:$(RESET)"; \
	printf "%b\n" "  Installed: $(GREEN)$$installed$(RESET)"; \
	printf "%b\n" "  Skipped:   $(RED)$$skipped$(RESET)"; \
	printf "%b\n" "  Total:     $(YELLOW)$$total$(RESET)"
