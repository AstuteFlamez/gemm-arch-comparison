# Run from the project root. Each simulation writes only below build/.
PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
VCS ?= vcs
SEED ?= 20260917
MATRIX_DIM ?= 8
GEMM_SEED ?= 20261008
GEMM_RANDOM_COUNT ?= 100
GEMM_BUILD_DIR = build/gemm/$(MATRIX_DIM)
CONVENTIONAL_BUILD_DIR = build/conventional-gemm/$(MATRIX_DIM)
GEMM_COMPARISON_DIR = build/gemm-comparison/$(MATRIX_DIM)/seed-$(GEMM_SEED)-random-$(GEMM_RANDOM_COUNT)
GEMM_VECTOR_ARGS = --size $(MATRIX_DIM) --seed $(GEMM_SEED) --random-count $(GEMM_RANDOM_COUNT) --out-dir $(GEMM_COMPARISON_DIR)
BOARD_SEED ?= 20261008
BOARD_RANDOM_COUNT ?= 100
BOARD_VECTOR_ARGS = --size 8 --seed $(BOARD_SEED) --random-count $(BOARD_RANDOM_COUNT) --out-dir fpga/de2_115
GEMM_COMMON_RTL = rtl/mac.sv rtl/fifo.sv rtl/memory/sram.sv rtl/memory/memory_wrapper.sv rtl/top_level_controller.sv
SYSTOLIC_RTL = rtl/systolic_array/pe.sv rtl/systolic_array/systolic_array.sv rtl/systolic_array/systolic_tile_controller.sv rtl/systolic_array/systolic_gemm.sv
CONVENTIONAL_RTL = rtl/conventional_matmul/conventional_tile_controller.sv rtl/conventional_matmul/conventional_gemm.sv
GEMM_RTL = $(GEMM_COMMON_RTL) $(SYSTOLIC_RTL)
GEMM_SOURCES = $(GEMM_RTL) tb/tb_gemm.sv
QUARTUS_SH ?= quartus_sh

.PHONY: help env smoke smoke-vcs test-python mac-compile test-mac test-mac-vcs gemm-compile test-gemm test-gemm-vcs sram-compile test-sram check test-rtl-units
.PHONY: gemm-controller-compile test-gemm-controller test-gemm-controller-vcs
.PHONY: fifo-compile test-fifo test-fifo-vcs test-fifo-configs
.PHONY: pe-compile test-pe
.PHONY: systolic-array-compile test-systolic-array
.PHONY: systolic-tile-controller-compile test-systolic-tile-controller
.PHONY: de2-115-vectors check-de2-115-vectors test-de2-115 quartus-de2-115
.PHONY: test-de2-115-systolic test-de2-115-conventional
.PHONY: quartus-de2-115-conventional quartus-de2-115-comparison
.PHONY: test-conventional-tile-controller test-conventional-gemm test-gemm-comparison
.PHONY: gemm-vectors test-gemm-all-sizes
.PHONY: test-gemm-ppa gemm-ppa-activity gemm-ppa
PPA_SIZES ?= 32
PPA_CONFIG ?= scripts/synopsys/config.saed32.json
PPA_TOOL_PREFIX ?=

help:
	@printf '%s\n' \
	  'Compare the four-MAC conventional and systolic GEMM cores' \
	  '  make env        Find tools in this shell; write build/environment.json' \
	  '  make smoke      Compile/run the MAC testbench with Icarus' \
	  '  make smoke-vcs  Compile/run the MAC testbench on a configured VCS machine' \
	  '  make test-python Run independent oracle and file-format checks' \
	  '  make test-rtl-units Run shared hardware, datapath, and controller tests' \
	  '  make mac-compile Compile the MAC and its testbench without simulating' \
	  '  make test-mac    Run your MAC testbench locally with Icarus' \
	  '  make test-mac-vcs Run MAC checks inside the configured CAE container' \
	  '  make test-pe     Run PE accumulation, enable, forwarding, and reset checks' \
	  '  make test-systolic-array Run 2x2 array arithmetic, zero padding, pause, and reset checks' \
	  '  make test-systolic-tile-controller Run tile loading, compute, writeback, reset, and timing checks' \
	  '  make gemm-compile Compile the GEMM core and its testbench' \
	  '  make test-gemm    Run systolic arithmetic/protocol checks (MATRIX_DIM=8/16/32)' \
	  '  make test-gemm-vcs Run GEMM checks on a configured VCS machine' \
	  '  make test-conventional-tile-controller Check conventional tile arithmetic and timing' \
	  '  make test-conventional-gemm Run the same arithmetic/protocol tests on conventional GEMM' \
	  '  make gemm-vectors Generate simulation fixtures for MATRIX_DIM, GEMM_SEED, GEMM_RANDOM_COUNT' \
	  '  make test-gemm-comparison Compare identical pairs and save cycles.csv (MATRIX_DIM=8/16/32)' \
	  '  make test-gemm-all-sizes Run Python, both core regressions, and comparisons at 8/16/32' \
	  '  make test-gemm-ppa Check the isolated PPA benchmark locally (PPA_SIZES="8 16 32")' \
	  '  make gemm-ppa-activity Run VCS and capture RTL activity for both cores' \
	  '  make gemm-ppa Generate Synopsys reports using PPA_CONFIG; see docs/SETUP_GUIDE.md' \
	  '  make test-de2-115 Run the same board regression on both architectures' \
	  '  make test-de2-115-systolic Run just the systolic board regression' \
	  '  make test-de2-115-conventional Run just the conventional board regression' \
	  '  make de2-115-vectors Regenerate board ROMs (10 directed + BOARD_RANDOM_COUNT pairs)' \
	  '  make check-de2-115-vectors Verify checked-in ROMs match BOARD_SEED and BOARD_RANDOM_COUNT' \
	  '  make quartus-de2-115 Compile systolic FPGA revision and export reports' \
	  '  make quartus-de2-115-conventional Compile conventional revision and export reports' \
	  '  make quartus-de2-115-comparison Compile both revisions serially and export reports' \
	  '  make gemm-controller-compile Compile standalone GEMM controller checks' \
	  '  make test-gemm-controller Run top-level tile sequencing and completion checks' \
	  '  make test-gemm-controller-vcs Run standalone controller checks with VCS' \
	  '  make sram-compile Compile standalone SRAM checks in two configurations' \
	  '  make test-sram    Run standalone SRAM checks (64x8 and 7x16)' \
	  '  make fifo-compile Compile standalone FIFO checks' \
	  '  make test-fifo    Run FIFO ordering, boundary, reset, and random checks' \
	  '  make test-fifo-configs Test parameterized RTL at depths 2/4/6/8 and widths 1/8/15/32' \
	  '  make test-fifo-vcs Run the same FIFO checks with VCS' \
	  '  make check       Run the full local/CI regression (Python, RTL, all GEMM sizes, FPGA wrappers)'

env:
	$(PYTHON) scripts/check_env.py --output build/environment.json

smoke: test-mac

smoke-vcs: test-mac-vcs

test-python:
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py' -v

mac-compile:
	@mkdir -p build/mac
	$(IVERILOG) -g2012 -Wall -s tb_mac -o build/mac/mac.vvp rtl/mac.sv tb/tb_mac.sv > build/mac/compile.log 2>&1 || { cat build/mac/compile.log; exit 1; }

test-mac: mac-compile
	cd build/mac && $(VVP) -l run.log mac.vvp

test-mac-vcs:
	@mkdir -p build/mac/vcs
	cd build/mac/vcs && $(VCS) -full64 -sverilog -top tb_mac ../../../rtl/mac.sv ../../../tb/tb_mac.sv -o simv -l compile.log
	cd build/mac/vcs && ./simv -l run.log

pe-compile:
	@mkdir -p build/pe
	$(IVERILOG) -g2012 -Wall -s tb_pe -o build/pe/pe.vvp rtl/mac.sv rtl/systolic_array/pe.sv tb/tb_pe.sv > build/pe/compile.log 2>&1 || { cat build/pe/compile.log; exit 1; }

test-pe: pe-compile
	cd build/pe && $(VVP) -l run.log pe.vvp

systolic-array-compile:
	@mkdir -p build/systolic-array
	$(IVERILOG) -g2012 -Wall -s tb_systolic_array -o build/systolic-array/systolic-array.vvp rtl/mac.sv rtl/systolic_array/pe.sv rtl/systolic_array/systolic_array.sv tb/tb_systolic_array.sv > build/systolic-array/compile.log 2>&1 || { cat build/systolic-array/compile.log; exit 1; }

test-systolic-array: systolic-array-compile
	cd build/systolic-array && $(VVP) -l run.log systolic-array.vvp +SEED=$(SEED)

gemm-compile:
	@mkdir -p $(GEMM_BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_gemm -Ptb_gemm.MatrixDim=$(MATRIX_DIM) -o $(GEMM_BUILD_DIR)/gemm.vvp $(GEMM_SOURCES) > $(GEMM_BUILD_DIR)/compile.log 2>&1 || { cat $(GEMM_BUILD_DIR)/compile.log; exit 1; }

test-gemm: gemm-compile
	cd $(GEMM_BUILD_DIR) && $(VVP) -l run.log gemm.vvp +SEED=$(GEMM_SEED)

test-gemm-vcs:
	@mkdir -p $(GEMM_BUILD_DIR)/vcs
	cd $(GEMM_BUILD_DIR)/vcs && $(VCS) -full64 -sverilog -top tb_gemm -pvalue+tb_gemm.MatrixDim=$(MATRIX_DIM) $(abspath $(GEMM_SOURCES)) -o simv -l compile.log
	cd $(GEMM_BUILD_DIR)/vcs && ./simv -l run.log +SEED=$(GEMM_SEED)

test-conventional-tile-controller:
	@mkdir -p build/conventional-tile-controller
	$(IVERILOG) -g2012 -Wall -s tb_conventional_tile_controller -o build/conventional-tile-controller/controller.vvp $(GEMM_COMMON_RTL) $(CONVENTIONAL_RTL) tb/tb_conventional_tile_controller.sv > build/conventional-tile-controller/compile.log 2>&1 || { cat build/conventional-tile-controller/compile.log; exit 1; }
	cd build/conventional-tile-controller && $(VVP) -l run.log controller.vvp +SEED=$(SEED)

test-conventional-gemm:
	@mkdir -p $(CONVENTIONAL_BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_gemm -Ptb_gemm.MatrixDim=$(MATRIX_DIM) -Ptb_gemm.USE_CONVENTIONAL=1 -o $(CONVENTIONAL_BUILD_DIR)/gemm.vvp $(GEMM_COMMON_RTL) $(CONVENTIONAL_RTL) tb/tb_gemm.sv > $(CONVENTIONAL_BUILD_DIR)/compile.log 2>&1 || { cat $(CONVENTIONAL_BUILD_DIR)/compile.log; exit 1; }
	cd $(CONVENTIONAL_BUILD_DIR) && $(VVP) -l run.log gemm.vvp +SEED=$(GEMM_SEED)

gemm-vectors:
	$(PYTHON) tests/gen_gemm_vectors.py $(GEMM_VECTOR_ARGS)

test-gemm-comparison: gemm-vectors
	$(IVERILOG) -g2012 -Wall -I $(GEMM_COMPARISON_DIR) -s tb_gemm_comparison -Ptb_gemm_comparison.MatrixDim=$(MATRIX_DIM) -o $(GEMM_COMPARISON_DIR)/comparison.vvp $(GEMM_RTL) $(CONVENTIONAL_RTL) tb/tb_gemm_comparison.sv > $(GEMM_COMPARISON_DIR)/compile.log 2>&1 || { cat $(GEMM_COMPARISON_DIR)/compile.log; exit 1; }
	cd $(GEMM_COMPARISON_DIR) && $(VVP) -l run.log comparison.vvp

test-gemm-all-sizes: test-python
	@set -e; for size in 8 16 32; do \
	  $(MAKE) test-gemm test-conventional-gemm test-gemm-comparison MATRIX_DIM=$$size; \
	done

# Each invocation creates a fresh timestamped directory below build/ppa/.
test-gemm-ppa:
	$(PYTHON) scripts/run_gemm_ppa.py --flow local --sizes $(PPA_SIZES) --seed $(GEMM_SEED) --random-count $(GEMM_RANDOM_COUNT)

gemm-ppa-activity:
	$(PYTHON) scripts/run_gemm_ppa.py --flow activity --sizes $(PPA_SIZES) --seed $(GEMM_SEED) --random-count $(GEMM_RANDOM_COUNT) --tool-prefix "$(PPA_TOOL_PREFIX)"

gemm-ppa:
	$(PYTHON) scripts/run_gemm_ppa.py --flow ppa --config "$(PPA_CONFIG)" --sizes $(PPA_SIZES) --seed $(GEMM_SEED) --random-count $(GEMM_RANDOM_COUNT) --tool-prefix "$(PPA_TOOL_PREFIX)"

de2-115-vectors:
	$(PYTHON) tests/gen_gemm_vectors.py $(BOARD_VECTOR_ARGS)

check-de2-115-vectors:
	$(PYTHON) tests/gen_gemm_vectors.py $(BOARD_VECTOR_ARGS) --check

test-de2-115: test-de2-115-systolic test-de2-115-conventional

test-de2-115-systolic: check-de2-115-vectors
	@mkdir -p build/de2-115
	cp fpga/de2_115/inputs_a.hex fpga/de2_115/inputs_b.hex fpga/de2_115/expected.hex build/de2-115/
	$(IVERILOG) -g2012 -Wall -I fpga/de2_115 -s tb_de2_115_gemm -o build/de2-115/board.vvp $(GEMM_RTL) fpga/de2_115/de2_115_gemm_top.sv tb/tb_de2_115_gemm.sv > build/de2-115/compile.log 2>&1 || { cat build/de2-115/compile.log; exit 1; }
	cd build/de2-115 && $(VVP) -l run.log board.vvp

test-de2-115-conventional: check-de2-115-vectors
	@mkdir -p build/de2-115-conventional
	cp fpga/de2_115/inputs_a.hex fpga/de2_115/inputs_b.hex fpga/de2_115/expected.hex build/de2-115-conventional/
	$(IVERILOG) -g2012 -Wall -I fpga/de2_115 -s tb_de2_115_gemm -Ptb_de2_115_gemm.UseConventional=1 -o build/de2-115-conventional/board.vvp $(GEMM_COMMON_RTL) $(CONVENTIONAL_RTL) fpga/de2_115/de2_115_gemm_top.sv tb/tb_de2_115_gemm.sv > build/de2-115-conventional/compile.log 2>&1 || { cat build/de2-115-conventional/compile.log; exit 1; }
	cd build/de2-115-conventional && $(VVP) -l run.log board.vvp

quartus-de2-115: check-de2-115-vectors
	cd fpga/de2_115 && $(QUARTUS_SH) --flow compile gemm_de2_115 -c gemm_de2_115
	cd fpga/de2_115 && $(QUARTUS_SH) -t ../../scripts/export_quartus_reports.tcl gemm_de2_115 gemm_de2_115 ../../build/quartus/de2_115/comparison

quartus-de2-115-conventional: check-de2-115-vectors
	cd fpga/de2_115 && $(QUARTUS_SH) --flow compile gemm_de2_115 -c gemm_de2_115_conventional
	cd fpga/de2_115 && $(QUARTUS_SH) -t ../../scripts/export_quartus_reports.tcl gemm_de2_115 gemm_de2_115_conventional ../../build/quartus/de2_115-conventional/comparison

# Revisions share Quartus's project database; never compile them concurrently.
quartus-de2-115-comparison:
	$(MAKE) quartus-de2-115
	$(MAKE) quartus-de2-115-conventional

gemm-controller-compile:
	@mkdir -p build/gemm-controller
	$(IVERILOG) -g2012 -Wall -s tb_gemm_controller -o build/gemm-controller/controller.vvp rtl/top_level_controller.sv rtl/systolic_array/systolic_tile_controller.sv tb/tb_gemm_controller.sv > build/gemm-controller/compile.log 2>&1 || { cat build/gemm-controller/compile.log; exit 1; }

test-gemm-controller: gemm-controller-compile
	cd build/gemm-controller && $(VVP) -l run.log controller.vvp

test-gemm-controller-vcs:
	@mkdir -p build/gemm-controller/vcs
	cd build/gemm-controller/vcs && $(VCS) -full64 -sverilog -top tb_gemm_controller ../../../rtl/top_level_controller.sv ../../../rtl/systolic_array/systolic_tile_controller.sv ../../../tb/tb_gemm_controller.sv -o simv -l compile.log
	cd build/gemm-controller/vcs && ./simv -l run.log

systolic-tile-controller-compile:
	@mkdir -p build/systolic-tile-controller
	$(IVERILOG) -g2012 -Wall -s tb_systolic_tile_controller -o build/systolic-tile-controller/controller.vvp rtl/systolic_array/systolic_tile_controller.sv rtl/memory/sram.sv rtl/fifo.sv rtl/mac.sv rtl/systolic_array/pe.sv rtl/systolic_array/systolic_array.sv tb/tb_systolic_tile_controller.sv > build/systolic-tile-controller/compile.log 2>&1 || { cat build/systolic-tile-controller/compile.log; exit 1; }

test-systolic-tile-controller: systolic-tile-controller-compile
	cd build/systolic-tile-controller && $(VVP) -l run.log controller.vvp +SEED=$(SEED)

sram-compile:
	@mkdir -p build/sram
	$(IVERILOG) -g2012 -Wall -s tb_sram -o build/sram/sram.vvp rtl/memory/sram.sv tb/tb_sram.sv > build/sram/compile.log 2>&1 || { cat build/sram/compile.log; exit 1; }
	$(IVERILOG) -g2012 -Wall -s tb_sram -Ptb_sram.DATA_WIDTH=16 -Ptb_sram.DEPTH=7 -o build/sram/sram-7x16.vvp rtl/memory/sram.sv tb/tb_sram.sv > build/sram/compile-7x16.log 2>&1 || { cat build/sram/compile-7x16.log; exit 1; }

test-sram: sram-compile
	cd build/sram && $(VVP) -l run.log sram.vvp
	cd build/sram && $(VVP) -l run-7x16.log sram-7x16.vvp

fifo-compile:
	@mkdir -p build/fifo
	$(IVERILOG) -g2012 -Wall -DFIFO_PARAMETERIZED -s tb_fifo -o build/fifo/fifo.vvp rtl/fifo.sv tb/tb_fifo.sv > build/fifo/compile.log 2>&1 || { cat build/fifo/compile.log; exit 1; }

test-fifo: fifo-compile
	cd build/fifo && $(VVP) -l run.log fifo.vvp +SEED=$(SEED)

test-fifo-configs:
	@set -e; for depth in 2 4 6 8; do \
	  for width in 1 8 15 32; do \
	    out_dir=build/fifo/config-$$depth-x-$$width; \
	    mkdir -p "$$out_dir"; \
	    $(IVERILOG) -g2012 -Wall -DFIFO_PARAMETERIZED -s tb_fifo \
	      -Ptb_fifo.DEPTH=$$depth -Ptb_fifo.DATA_WIDTH=$$width \
	      -o "$$out_dir/fifo.vvp" rtl/fifo.sv tb/tb_fifo.sv > "$$out_dir/compile.log" 2>&1 \
	      || { cat "$$out_dir/compile.log"; exit 1; }; \
	    (cd "$$out_dir" && $(VVP) -l run.log fifo.vvp +SEED=$(SEED)); \
	  done; \
	done

test-fifo-vcs:
	@mkdir -p build/fifo/vcs
	cd build/fifo/vcs && $(VCS) -full64 -sverilog +define+FIFO_PARAMETERIZED -top tb_fifo ../../../rtl/fifo.sv ../../../tb/tb_fifo.sv -o simv -l compile.log
	cd build/fifo/vcs && ./simv -l run.log +SEED=$(SEED)

test-rtl-units: test-mac test-pe test-sram test-fifo test-fifo-configs test-systolic-array test-gemm-controller test-systolic-tile-controller test-conventional-tile-controller

check: env test-rtl-units test-gemm-all-sizes test-de2-115
