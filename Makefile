SHELL := bash

.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:
MAKEFLAGS += --no-builtin-rules

Q ?= @
ifeq ($(V),1)
Q :=
endif

define msg
	@printf "  %-8s  %s\n" "$(1)" "$(2)"
endef

# By default, install the selected Kuiper binary package inside this project.
# A caller-provided KUIPER_HOME is treated as read-only and is never replaced.
ifeq ($(origin KUIPER_HOME),undefined)
KUIPER_HOME := $(CURDIR)/.kuiper
KUIPER_HOME_MANAGED := 1
else
KUIPER_HOME_MANAGED := 0
endif
override KUIPER_HOME := $(abspath $(KUIPER_HOME))
KUIPER_NIGHTLY ?= $(strip $(file <kuiper-version.txt))
ifeq ($(KUIPER_HOME_MANAGED),1)
KUIPER_MARKER := $(KUIPER_HOME)/.template-nightly-$(KUIPER_NIGHTLY)
else
KUIPER_MARKER := $(KUIPER_HOME)/.packaged
endif

FSTAR_EXE := $(KUIPER_HOME)/inst/bin/fstar.exe
FSTAR_SH := $(KUIPER_HOME)/fstar.sh
KRML_EXE := $(KUIPER_HOME)/inst/bin/krml
PLUGIN_SOURCE := $(KUIPER_HOME)/extraction/dune/_build/default/kuiper_extr.cmxs
LIST_ADMITS := $(KUIPER_HOME)/scripts/list-admits.py

# Pin generated-code formatting independently so dist/ is reproducible.
TOOLS_DIR ?= $(CURDIR)/.tools
CLANG_FORMAT_VERSION := 19.1.7
ifeq ($(origin CLANG_FORMAT),undefined)
CLANG_FORMAT := $(TOOLS_DIR)/clang-format-$(CLANG_FORMAT_VERSION)/bin/clang-format
CLANG_FORMAT_MANAGED := 1
else
CLANG_FORMAT_MANAGED := 0
endif
CLANG_FORMAT_FLAGS := --Werror --fail-on-incomplete-format \
	--style=file:$(CURDIR)/.clang-format
NORMALIZE_LEADING_BLANKS := awk 'BEGIN { print "" } NF || seen { seen = 1; print }'

# F* treats dots in --load_cmxs paths as module separators. Stage the plugin
# below obj/, whose default path is dot-free.
OUTDIR := obj
CACHEDIR := $(OUTDIR)
PLUGIN := $(CURDIR)/$(OUTDIR)/kuiper_extr

export KUIPER_HOME
export FSTAR_EXE
export KRML_EXE

ROOTS := $(shell find src -type f \( -name '*.fst' -o -name '*.fsti' \) | sort)
CHECKED := $(foreach f,$(ROOTS),$(OUTDIR)/$(notdir $(f)).checked)

# Put concrete extraction entry points in src/extract/. Library-only modules
# can live elsewhere under src/ and will still be verified.
EXTRACT := $(shell find src/extract -type f -name '*.fst' | sort)
EXTRACT_MODULES := $(subst .,_,$(basename $(notdir $(EXTRACT))))
EXTRACT_CU := $(addprefix $(OUTDIR)/,$(addsuffix .cu,$(EXTRACT_MODULES)))
EXTRACT_H := $(addprefix $(OUTDIR)/,$(addsuffix .h,$(EXTRACT_MODULES)))

# The package wrapper owns Kuiper's compiler flags, solver, and library paths.
FSTAR_LOCAL_FLAGS := --include $(CURDIR)/src --include $(CURDIR)/$(CACHEDIR)
ifneq ($(filter-out 0 1,$(strip $(ADMIT))),)
$(error ADMIT must be unset, 0, or 1)
endif
ifeq ($(strip $(ADMIT)),1)
FSTAR_LOCAL_FLAGS += --admit_smt_queries true
endif
FSTAR_LOCAL_FLAGS += $(O)
FSTAR := env MAKEFLAGS= MAKEOVERRIDES= ADMIT= O= $(FSTAR_SH) \
	$(if $(V),,--silent) $(FSTAR_LOCAL_FLAGS)

KRML_FLAGS :=
KRML_FLAGS += -add-early-include '<kuiper.h>'
KRML_FLAGS += -fc++-compat -fcast-allocations
KRML_FLAGS += -skip-compilation -skip-makefiles
KRML_FLAGS += -faggressive-inlining -fauto-for-loops -fnoshort-enums
KRML_FLAGS += -cuda -dbacktrace
KRML_FLAGS += $(if $(V),-verbose,-silent)
KRML_FLAGS += -drop Prims -minimal -header /dev/null
KRML_FLAGS += -warn-error @6 -warn-error -2@4-10@18
KRML_FLAGS += $(KO)
KRML := $(KRML_EXE) $(KRML_FLAGS)

.PHONY: all verify extract-all prepare install-kuiper install-clang-format
.PHONY: dist dist-check lint list-admits clean help

all: verify extract-all

verify: $(CHECKED)

extract-all: $(EXTRACT_CU) $(EXTRACT_H)

install-kuiper: $(KUIPER_MARKER)

install-clang-format: $(CLANG_FORMAT)

prepare: $(KUIPER_MARKER) $(CLANG_FORMAT)

ifeq ($(KUIPER_HOME_MANAGED),1)
$(KUIPER_MARKER): kuiper-version.txt scripts/install-kuiper.sh
	$(call msg,INSTALL,Kuiper nightly $(KUIPER_NIGHTLY))
	$(Q)./scripts/install-kuiper.sh --nightly --version $(KUIPER_NIGHTLY) \
		--dest $(KUIPER_HOME) --no-link
	$(Q)test -f $(KUIPER_HOME)/.packaged
	$(Q)test -x $(FSTAR_EXE)
	$(Q)test -x $(FSTAR_SH)
	$(Q)test -x $(KRML_EXE)
	$(Q)test -f $(PLUGIN_SOURCE)
	$(Q)test -f $(LIST_ADMITS)
	$(Q)rm -rf $(OUTDIR)
	$(Q)rm -f .depend
	$(Q)touch $@
else
$(KUIPER_MARKER):
	$(error KUIPER_HOME does not contain a packaged Kuiper installation: $(KUIPER_HOME))
endif

ifeq ($(CLANG_FORMAT_MANAGED),1)
$(CLANG_FORMAT): scripts/install-clang-format.sh
	$(call msg,INSTALL,clang-format $(CLANG_FORMAT_VERSION))
	$(Q)CLANG_FORMAT_VERSION=$(CLANG_FORMAT_VERSION) \
		./scripts/install-clang-format.sh $(TOOLS_DIR)/clang-format-$(CLANG_FORMAT_VERSION)
endif

$(FSTAR_EXE) $(FSTAR_SH) $(KRML_EXE) $(PLUGIN_SOURCE) $(LIST_ADMITS): | $(KUIPER_MARKER)
	$(Q)test -e $@

# Avoid loading the build dependency file for metadata-only targets.
NON_BUILD_GOALS := clean echo-fstar echo-krml install-kuiper prepare \
	install-clang-format lint list-admits help
ifeq ($(strip $(MAKECMDGOALS)),)
-include .depend
else ifneq ($(strip $(filter-out $(NON_BUILD_GOALS),$(MAKECMDGOALS))),)
-include .depend
endif

.depend: $(ROOTS) $(KUIPER_MARKER)
	$(call msg,DEPEND,$@)
	$(Q)mkdir -p $(OUTDIR)
	$(Q)$(FSTAR) --codegen krml \
		--already_cached 'FStar,LowStar,Prims,Pulse,PulseCore' \
		--dep full $(ROOTS) -o $@.tmp
	$(Q)mv $@.tmp $@

$(OUTDIR)/%.checked: | $(KUIPER_MARKER)
	$(call msg,CHECK,$<)
	$(Q)mkdir -p $(OUTDIR)
	$(Q)$(FSTAR) --already_cached '*' -c $< -o $@
	$(Q)touch -c $@

$(OUTDIR)/kuiper_extr.cmxs: $(PLUGIN_SOURCE) | $(KUIPER_MARKER)
	$(Q)mkdir -p $(OUTDIR)
	$(Q)ln -sf $(PLUGIN_SOURCE) $@

$(OUTDIR)/%.krml: MOD = $(subst _,.,$(basename $(notdir $@)))
$(OUTDIR)/%.krml: | $(KUIPER_MARKER) $(OUTDIR)/kuiper_extr.cmxs
	$(call msg,EXTRACT,$(MOD))
	$(Q)$(FSTAR) --codegen krml --load_cmxs $(PLUGIN) \
		--extract "-*,+$(MOD),+Kuiper" -o $@ $<

$(OUTDIR)/pre/%.cu $(OUTDIR)/pre/%.h &: MOD = $(subst _,.,$(basename $(notdir $<)))
$(OUTDIR)/pre/%.cu $(OUTDIR)/pre/%.h &: $(OUTDIR)/%.krml $(KRML_EXE)
	$(call msg,KRML,$(MOD))
	$(Q)mkdir -p $(OUTDIR)/pre
	$(Q)$(KRML) -bundle "$(MOD)=*" -tmpdir $(OUTDIR)/pre/ $<

$(OUTDIR)/%.cu: $(OUTDIR)/pre/%.cu $(KUIPER_HOME)/scripts/fixup.sed $(CLANG_FORMAT) .clang-format
	$(call msg,FIXUP,$@)
	$(Q)sed -f $(KUIPER_HOME)/scripts/fixup.sed $< | \
		$(CLANG_FORMAT) $(CLANG_FORMAT_FLAGS) --assume-filename=$@ | \
		$(NORMALIZE_LEADING_BLANKS) > $@

$(OUTDIR)/%.h: $(OUTDIR)/pre/%.h $(KUIPER_HOME)/scripts/fixup.sed $(CLANG_FORMAT) .clang-format
	$(call msg,FIXUP,$@)
	$(Q)sed -f $(KUIPER_HOME)/scripts/fixup.sed $< | \
		$(CLANG_FORMAT) $(CLANG_FORMAT_FLAGS) --assume-filename=$@ | \
		$(NORMALIZE_LEADING_BLANKS) > $@

dist: extract-all
	$(Q)./scripts/update-dist.sh

dist-check: dist
	$(Q)git diff --exit-code -- dist
	$(Q)test -z "$$(git ls-files --others --exclude-standard -- dist)"

lint:
	$(Q)python3 scripts/lint.py

list-admits: $(LIST_ADMITS)
	$(Q)find src -type f \( -name '*.fst' -o -name '*.fsti' \) -print0 | \
		sort -z | xargs -0 python3 $(LIST_ADMITS)

clean:
	$(Q)rm -rf $(OUTDIR) .depend

.PHONY: echo-fstar echo-krml
echo-fstar: $(KUIPER_MARKER)
	@echo $(FSTAR)

echo-krml: $(KUIPER_MARKER)
	@echo $(KRML)

help:
	@printf '%s\n' \
		'make -j$$(nproc) prepare      install pinned tools' \
		'make -j$$(nproc) verify       verify every local F*/Pulse module' \
		'make -j$$(nproc) extract-all  extract src/extract/*.fst to obj/' \
		'make -j$$(nproc) dist         refresh checked-in generated output' \
		'make lint                     run repository hygiene checks' \
		'make list-admits              report explicit trust markers'
