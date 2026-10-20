# ============================================================================
# ECE180 Lab 2 -- CNN Processing Element
#
#   make tb       build + run YOUR testbench (tb/tb_pe.sv)
#   make check    build + run the instructor testbench (tb/tb_check.sv)
#   make wave     run your testbench and dump build/tb/pe.vcd
#   make lint     syntax/lint only, no simulation -- fastest way to find typos
#   make clean
#
# Everything in rtl/ is compiled automatically, so just drop your new
# module files in there. No Makefile edits needed.
# ============================================================================

VERILATOR ?= verilator
RTL        = $(wildcard rtl/*.sv)

# Latches and blocking-assignment-in-always_ff are errors, as in Lab 1.
# Width mismatches are left as warnings here: signed arithmetic widens a lot
# on purpose in this design, and chasing those would eat the hour.
VFLAGS = --binary --timing -j 0 \
         -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-VARHIDDEN \
         -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-fatal \
         -Werror-LATCH -Werror-BLKSEQ -Werror-COMBDLY \
         -Werror-MULTIDRIVEN -Werror-IMPLICIT -Werror-PINMISSING \
         --Mdir build/$(T) -o sim

.PHONY: tb check wave lint clean

tb:    ; @$(MAKE) --no-print-directory run T=tb    TOP=tb_pe    SRC="tb/tb_pe.sv"
check: ; @$(MAKE) --no-print-directory run T=check TOP=tb_check SRC="tb/tb_check.sv"
wave:  ; @$(MAKE) --no-print-directory run T=tb    TOP=tb_pe    SRC="tb/tb_pe.sv" TRACE=1

run:
	@mkdir -p build/$(T)
	@$(VERILATOR) $(VFLAGS) $(if $(TRACE),--trace) \
	    --top-module $(TOP) $(RTL) tb/tb.vlt $(SRC) \
	    > build/$(T)/compile.log 2>&1 \
	  || { echo "--- compile failed ---"; \
	       grep -E '%(Error|Warning)' build/$(T)/compile.log | head -30; \
	       echo "  (full log: build/$(T)/compile.log)"; exit 1; }
	@grep -E '%Warning' build/$(T)/compile.log | head -10 || true
	@./build/$(T)/sim $(if $(TRACE),+trace) | grep -v '\$$finish'

lint:
	@$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
	    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	    --top-module pe_top $(RTL) && echo "lint clean"

clean:
	@rm -rf build *.vcd
