# Local tools are installed into .rocks/ by `make setup` (needs Homebrew lua@5.4).
LUA_DIR ?= /opt/homebrew/opt/lua@5.4
ROCKS   := luarocks --lua-version=5.4 --lua-dir=$(LUA_DIR) --tree .rocks
LUA     := $(LUA_DIR)/bin/lua5.4
BIN     := $(CURDIR)/.rocks/bin
export LUA_PATH := $(CURDIR)/?.lua;$(CURDIR)/.rocks/share/lua/5.4/?.lua;$(CURDIR)/.rocks/share/lua/5.4/?/init.lua;;
export LUA_CPATH := $(CURDIR)/.rocks/lib/lua/5.4/?.so;;

DEV_PLUGINS ?= $(HOME)/Jagex/RuneScape-BETA/dev_plugins

.PHONY: check setup lint fmt fmt-check test validate package link unlink

check: lint fmt-check test validate  ## everything CI runs

setup:
	$(ROCKS) install luacheck
	$(ROCKS) install busted
	$(ROCKS) install dkjson

lint:
	$(BIN)/luacheck .

fmt:
	stylua .

fmt-check:
	stylua --check .

test:
	$(BIN)/busted

validate:
	$(LUA) tools/validate.lua

# make package PLUGIN=hello-world
package:
	$(LUA) tools/validate.lua --release plugins/$(PLUGIN)
	LUA=$(LUA) tools/package.sh $(PLUGIN)

# make link PLUGIN=hello-world  (symlinks the plugin into the beta client's dev_plugins)
link:
	@test -d "$(DEV_PLUGINS)" || { echo "missing $(DEV_PLUGINS)"; exit 1; }
	ln -sfn "$(CURDIR)/plugins/$(PLUGIN)" "$(DEV_PLUGINS)/$(PLUGIN)"
	@echo "linked $(DEV_PLUGINS)/$(PLUGIN) -> plugins/$(PLUGIN)"

unlink:
	rm "$(DEV_PLUGINS)/$(PLUGIN)"
