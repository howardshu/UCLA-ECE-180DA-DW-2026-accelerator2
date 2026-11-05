# Accelerator build and simulation (Verilator 5, --timing).
#
#   make model         check the Python reference model against the vectors
#   make sim           run tb_team (async external memory)
#   make sim-sync      run tb_team with cnn_ext_mem REGISTERED_READ=1
#   make sim BRINGUP=1 check only conv1 output (1..4 = a1, p1, a2, p2)
#   make lint          lint the RTL only (interface-port UNDRIVEN/UNUSED warnings are expected)
#
# Run from OoOFinalProject-Files/. The course files (common/, tb/) live
# alongside ours; sync the fork with upstream to pick up course updates.

COURSE      ?= .
COMMON      := $(COURSE)/common
VECTORS     := $(abspath $(COURSE)/tb/vectors)
BUILD       := build
BRINGUP     ?= 0

# Files the course testbench references but the course repo does not ship
# yet. Use the official copy as soon as it appears, else our stand-in.
pick = $(if $(wildcard $(COMMON)/$(1)),$(COMMON)/$(1),rtl/stubs/$(1))

PKGS := $(COMMON)/accelerator_pkg.sv \
        $(call pick,accelerator_cnn_pkg.sv) \
        rtl/acc_internal_pkg.sv
IFS  := $(COMMON)/csr_accelerator_if.sv \
        $(call pick,cnn_mem_if.sv) \
        $(call pick,acc_debug_if.sv)
RTL  := rtl/acc_ram.sv rtl/acc_controller.sv rtl/acc_conv.sv rtl/acc_pool.sv \
        rtl/acc_fc.sv rtl/accelerator_top.sv
TB   := $(COMMON)/cnn_ext_mem.sv tb/tb_team.sv

VFLAGS := --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY \
          -Wno-UNUSEDPARAM -Wno-IMPORTSTAR -Wno-VARHIDDEN

.PHONY: model sim sim-sync sim-pe lint lint-pe clean

PE_RTL := rtl/pe/mac_unit.sv rtl/pe/accumulator.sv rtl/pe/pe_top.sv

lint-pe:
	verilator --lint-only -Wall --top-module pe_top $(PE_RTL)

sim-pe:
	@mkdir -p $(BUILD)/pe
	verilator $(VFLAGS) --top-module tb_pe --Mdir $(BUILD)/pe \
	    $(PE_RTL) tb/tb_pe.sv -o Vtb
	@for dir in $(VECTORS)/*/; do \
	    offset=$$(python3 -c 'import sys; sys.path.insert(0,"model"); from cnn_ref import vector_offset; print(vector_offset(sys.argv[1]))' "$$dir"); \
	    $(BUILD)/pe/Vtb +vector="$$dir" +offset="$$offset" || exit $$?; \
	done

$(COMMON)/accelerator_pkg.sv:
	@echo "Course files not found at $(COURSE). Run make from OoOFinalProject-Files/." && exit 1

model: $(COMMON)/accelerator_pkg.sv
	python3 -I model/cnn_ref.py check $(VECTORS)/*/

sim: $(COMMON)/accelerator_pkg.sv
	@mkdir -p $(BUILD)/async
	verilator $(VFLAGS) --top-module tb_team -GSYNC=0 --Mdir $(BUILD)/async \
	    $(PKGS) $(IFS) $(PE_RTL) $(RTL) $(TB) -o Vtb
	$(BUILD)/async/Vtb +vectors=$(VECTORS) +bringup=$(BRINGUP)

sim-sync: $(COMMON)/accelerator_pkg.sv
	@mkdir -p $(BUILD)/sync
	verilator $(VFLAGS) --top-module tb_team -GSYNC=1 --Mdir $(BUILD)/sync \
	    $(PKGS) $(IFS) $(PE_RTL) $(RTL) $(TB) -o Vtb
	$(BUILD)/sync/Vtb +vectors=$(VECTORS) +bringup=$(BRINGUP)

lint: $(COMMON)/accelerator_pkg.sv
	verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-IMPORTSTAR \
	    -Wno-UNUSEDPARAM --top-module accelerator_top $(PKGS) $(IFS) $(PE_RTL) $(RTL)

clean:
	rm -rf $(BUILD)
