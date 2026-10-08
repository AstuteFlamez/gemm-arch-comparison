# Run from the project root. Each simulation writes only below build/.
PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
VCS ?= vcs
SEED ?= 20260917
RANDOM_COUNT ?= 100
BOARD_SEED ?= 20261008
BOARD_RANDOM_COUNT ?= 100
BOARD_VECTOR_ARGS = --seed $(BOARD_SEED) --random-count $(BOARD_RANDOM_COUNT) --out-dir fpga/de2_115
GEMM_COMMON_RTL = rtl/gemm/mac.sv rtl/gemm/fifo.sv rtl/gemm/memory/sram.sv rtl/gemm/memory/memory_wrapper.sv rtl/gemm/top_level_controller.sv
SYSTOLIC_RTL = rtl/gemm/systolic_array/pe.sv rtl/gemm/systolic_array/systolic_array.sv rtl/gemm/systolic_array/systolic_tile_controller.sv rtl/gemm/systolic_array/systolic_gemm.sv
CONVENTIONAL_RTL = rtl/gemm/conventional_matmul/conventional_tile_controller.sv rtl/gemm/conventional_matmul/conventional_gemm.sv
GEMM_RTL = $(GEMM_COMMON_RTL) $(SYSTOLIC_RTL)
GEMM_SOURCES = $(GEMM_RTL) tb/tb_gemm.sv
QUARTUS_SH ?= quartus_sh

.PHONY: help env smoke smoke-vcs test-python vectors mac-compile test-mac test-mac-vcs gemv-compile test-gemv test-gemv-vcs test-gemv-full test-gemv-full-vcs gemm-compile test-gemm test-gemm-vcs sram-compile test-sram check
.PHONY: gemm-controller-compile test-gemm-controller test-gemm-controller-vcs
.PHONY: fifo-compile test-fifo test-fifo-vcs test-fifo-configs
.PHONY: pe-compile test-pe
.PHONY: systolic-array-compile test-systolic-array
.PHONY: systolic-tile-controller-compile test-systolic-tile-controller
.PHONY: de2-115-vectors check-de2-115-vectors test-de2-115 quartus-de2-115
.PHONY: test-conventional-tile-controller test-conventional-gemm test-gemm-comparison

help:
	@printf '%s\n' \
	  'Current milestone: compare the four-MAC conventional and systolic GEMM cores' \
	  '  make env        Find tools in this shell; write build/environment.json' \
	  '  make smoke      Compile/run the local Icarus environment test' \
	  '  make smoke-vcs  Compile/run the same test on a configured VCS machine' \
	  '  make test-python Run independent oracle and file-format checks' \
	  '  make vectors     Generate 10 directed + RANDOM_COUNT seeded random cases' \
	  '  make mac-compile Compile the MAC and its testbench without simulating' \
	  '  make test-mac    Run your MAC testbench locally with Icarus' \
	  '  make test-mac-vcs Run MAC checks inside the configured CAE container' \
	  '  make test-pe     Run PE accumulation, enable, forwarding, and reset checks' \
	  '  make test-systolic-array Run 2x2 array arithmetic, zero padding, pause, and reset checks' \
	  '  make test-systolic-tile-controller Run tile loading, compute, writeback, reset, and timing checks' \
	  '  make gemv-compile Compile the GEMV core and testbench without simulating' \
	  '  make test-gemv    Run the five basic GEMV tests locally' \
	  '  make test-gemv-vcs Run the basic GEMV tests on CAE' \
	  '  make test-gemv-full Run the full arithmetic/protocol regression locally' \
	  '  make test-gemv-full-vcs Run the full regression on CAE' \
	  '  make gemm-compile Compile the GEMM core and its testbench' \
	  '  make test-gemm    Run GEMM arithmetic and control checks locally' \
	  '  make test-gemm-vcs Run GEMM checks on a configured VCS machine' \
	  '  make test-conventional-tile-controller Check conventional tile arithmetic and timing' \
	  '  make test-conventional-gemm Run the same arithmetic/protocol tests on conventional GEMM' \
	  '  make test-gemm-comparison Run both cores on the same 110 FPGA fixture pairs' \
	  '  make test-de2-115 Simulate the board buttons, GEMM self-test, and LEDs' \
	  '  make de2-115-vectors Regenerate board ROMs (10 directed + BOARD_RANDOM_COUNT pairs)' \
	  '  make check-de2-115-vectors Verify checked-in ROMs match BOARD_SEED and BOARD_RANDOM_COUNT' \
	  '  make quartus-de2-115 Compile the FPGA project where Quartus is installed' \
	  '  make gemm-controller-compile Compile standalone GEMM controller checks' \
	  '  make test-gemm-controller Run top-level tile sequencing and completion checks' \
	  '  make test-gemm-controller-vcs Run standalone controller checks with VCS' \
	  '  make sram-compile Compile standalone SRAM checks in two configurations' \
	  '  make test-sram    Run standalone SRAM checks (64x8 and 7x16)' \
	  '  make fifo-compile Compile standalone FIFO checks' \
	  '  make test-fifo    Run FIFO ordering, boundary, reset, and random checks' \
	  '  make test-fifo-configs Test parameterized RTL at depths 2/4/6/8 and widths 1/8/15/32' \
	  '  make test-fifo-vcs Run the same FIFO checks with VCS' \
	  '  make check       Run env, local smoke, and Python checks' \
	  'make check covers support checks only; run test-mac, test-gemv-full, and test-gemm for RTL.'

env:
	$(PYTHON) scripts/check_env.py --output build/environment.json

smoke:
	@mkdir -p build/env
	$(IVERILOG) -g2012 -Wall -s tb_env_smoke -o build/env/env-smoke.vvp tb/tb_env_smoke.sv > build/env/iverilog-compile.log 2>&1 || { cat build/env/iverilog-compile.log; exit 1; }
	cd build/env && $(VVP) -l iverilog-run.log env-smoke.vvp

smoke-vcs:
	@mkdir -p build/env/vcs
	cd build/env/vcs && $(VCS) -full64 -sverilog -top tb_env_smoke ../../../tb/tb_env_smoke.sv -o simv -l compile.log
	cd build/env/vcs && ./simv -l run.log

test-python:
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py' -v

vectors: test-python
	$(PYTHON) tests/gen_vectors.py --seed $(SEED) --random-count $(RANDOM_COUNT) --out-dir build/vectors

mac-compile:
	@mkdir -p build/mac
	$(IVERILOG) -g2012 -Wall -s tb_mac -o build/mac/mac.vvp rtl/gemm/mac.sv tb/tb_mac.sv > build/mac/compile.log 2>&1 || { cat build/mac/compile.log; exit 1; }

test-mac: mac-compile
	cd build/mac && $(VVP) -l run.log mac.vvp

test-mac-vcs:
	@mkdir -p build/mac/vcs
	cd build/mac/vcs && $(VCS) -full64 -sverilog -top tb_mac ../../../rtl/gemm/mac.sv ../../../tb/tb_mac.sv -o simv -l compile.log
	cd build/mac/vcs && ./simv -l run.log

pe-compile:
	@mkdir -p build/pe
	$(IVERILOG) -g2012 -Wall -s tb_pe -o build/pe/pe.vvp rtl/gemm/mac.sv rtl/gemm/systolic_array/pe.sv tb/tb_pe.sv > build/pe/compile.log 2>&1 || { cat build/pe/compile.log; exit 1; }

test-pe: pe-compile
	cd build/pe && $(VVP) -l run.log pe.vvp

systolic-array-compile:
	@mkdir -p build/systolic-array
	$(IVERILOG) -g2012 -Wall -s tb_systolic_array -o build/systolic-array/systolic-array.vvp rtl/gemm/mac.sv rtl/gemm/systolic_array/pe.sv rtl/gemm/systolic_array/systolic_array.sv tb/tb_systolic_array.sv > build/systolic-array/compile.log 2>&1 || { cat build/systolic-array/compile.log; exit 1; }

test-systolic-array: systolic-array-compile
	cd build/systolic-array && $(VVP) -l run.log systolic-array.vvp +SEED=$(SEED)

gemv-compile:
	@mkdir -p build/gemv
	$(IVERILOG) -g2012 -Wall -s tb_gemv -o build/gemv/gemv.vvp rtl/gemm/mac.sv rtl/gemv/gemv.sv tb/tb_gemv.sv > build/gemv/compile.log 2>&1 || { cat build/gemv/compile.log; exit 1; }

test-gemv: gemv-compile
	cd build/gemv && $(VVP) -l run.log gemv.vvp

test-gemv-vcs:
	@mkdir -p build/gemv/vcs
	cd build/gemv/vcs && $(VCS) -full64 -sverilog -top tb_gemv ../../../rtl/gemm/mac.sv ../../../rtl/gemv/gemv.sv ../../../tb/tb_gemv.sv -o simv -l compile.log
	cd build/gemv/vcs && ./simv -l run.log

test-gemv-full: vectors
	@mkdir -p build/gemv-regression
	$(IVERILOG) -g2012 -Wall -s tb_gemv_regression -o build/gemv-regression/gemv.vvp rtl/gemm/mac.sv rtl/gemv/gemv.sv tb/tb_gemv_regression.sv > build/gemv-regression/compile.log 2>&1 || { cat build/gemv-regression/compile.log; exit 1; }
	cd build/gemv-regression && $(VVP) -l run.log gemv.vvp +VECTORS=../vectors/vectors.txt

test-gemv-full-vcs: vectors
	@mkdir -p build/gemv-regression/vcs
	cd build/gemv-regression/vcs && $(VCS) -full64 -sverilog -top tb_gemv_regression ../../../rtl/gemm/mac.sv ../../../rtl/gemv/gemv.sv ../../../tb/tb_gemv_regression.sv -o simv -l compile.log
	cd build/gemv-regression/vcs && ./simv -l run.log +VECTORS=../../vectors/vectors.txt

gemm-compile:
	@mkdir -p build/gemm
	$(IVERILOG) -g2012 -Wall -s tb_gemm -o build/gemm/gemm.vvp $(GEMM_SOURCES) > build/gemm/compile.log 2>&1 || { cat build/gemm/compile.log; exit 1; }

test-gemm: gemm-compile
	cd build/gemm && $(VVP) -l run.log gemm.vvp

test-gemm-vcs:
	@mkdir -p build/gemm/vcs
	cd build/gemm/vcs && $(VCS) -full64 -sverilog -top tb_gemm $(addprefix ../../../,$(GEMM_SOURCES)) -o simv -l compile.log
	cd build/gemm/vcs && ./simv -l run.log

test-conventional-tile-controller:
	@mkdir -p build/conventional-tile-controller
	$(IVERILOG) -g2012 -Wall -s tb_conventional_tile_controller -o build/conventional-tile-controller/controller.vvp $(GEMM_COMMON_RTL) $(CONVENTIONAL_RTL) tb/tb_conventional_tile_controller.sv > build/conventional-tile-controller/compile.log 2>&1 || { cat build/conventional-tile-controller/compile.log; exit 1; }
	cd build/conventional-tile-controller && $(VVP) -l run.log controller.vvp +SEED=$(SEED)

test-conventional-gemm:
	@mkdir -p build/conventional-gemm
	$(IVERILOG) -g2012 -Wall -s tb_gemm -Ptb_gemm.USE_CONVENTIONAL=1 -o build/conventional-gemm/gemm.vvp $(GEMM_COMMON_RTL) $(CONVENTIONAL_RTL) tb/tb_gemm.sv > build/conventional-gemm/compile.log 2>&1 || { cat build/conventional-gemm/compile.log; exit 1; }
	cd build/conventional-gemm && $(VVP) -l run.log gemm.vvp

test-gemm-comparison: check-de2-115-vectors
	@mkdir -p build/gemm-comparison
	cp fpga/de2_115/inputs_a.hex fpga/de2_115/inputs_b.hex fpga/de2_115/expected.hex build/gemm-comparison/
	$(IVERILOG) -g2012 -Wall -I fpga/de2_115 -s tb_gemm_comparison -o build/gemm-comparison/comparison.vvp $(GEMM_RTL) $(CONVENTIONAL_RTL) tb/tb_gemm_comparison.sv > build/gemm-comparison/compile.log 2>&1 || { cat build/gemm-comparison/compile.log; exit 1; }
	cd build/gemm-comparison && $(VVP) -l run.log comparison.vvp

de2-115-vectors:
	$(PYTHON) tests/gen_gemm_vectors.py $(BOARD_VECTOR_ARGS)

check-de2-115-vectors:
	$(PYTHON) tests/gen_gemm_vectors.py $(BOARD_VECTOR_ARGS) --check

test-de2-115: check-de2-115-vectors
	@mkdir -p build/de2-115
	cp fpga/de2_115/inputs_a.hex fpga/de2_115/inputs_b.hex fpga/de2_115/expected.hex build/de2-115/
	$(IVERILOG) -g2012 -Wall -I fpga/de2_115 -s tb_de2_115_gemm -o build/de2-115/board.vvp $(GEMM_RTL) fpga/de2_115/de2_115_gemm_top.sv tb/tb_de2_115_gemm.sv > build/de2-115/compile.log 2>&1 || { cat build/de2-115/compile.log; exit 1; }
	cd build/de2-115 && $(VVP) -l run.log board.vvp

quartus-de2-115: check-de2-115-vectors
	cd fpga/de2_115 && $(QUARTUS_SH) --flow compile gemm_de2_115

gemm-controller-compile:
	@mkdir -p build/gemm-controller
	$(IVERILOG) -g2012 -Wall -s tb_gemm_controller -o build/gemm-controller/controller.vvp rtl/gemm/top_level_controller.sv rtl/gemm/systolic_array/systolic_tile_controller.sv tb/tb_gemm_controller.sv > build/gemm-controller/compile.log 2>&1 || { cat build/gemm-controller/compile.log; exit 1; }

test-gemm-controller: gemm-controller-compile
	cd build/gemm-controller && $(VVP) -l run.log controller.vvp

test-gemm-controller-vcs:
	@mkdir -p build/gemm-controller/vcs
	cd build/gemm-controller/vcs && $(VCS) -full64 -sverilog -top tb_gemm_controller ../../../rtl/gemm/top_level_controller.sv ../../../rtl/gemm/systolic_array/systolic_tile_controller.sv ../../../tb/tb_gemm_controller.sv -o simv -l compile.log
	cd build/gemm-controller/vcs && ./simv -l run.log

systolic-tile-controller-compile:
	@mkdir -p build/systolic-tile-controller
	$(IVERILOG) -g2012 -Wall -s tb_systolic_tile_controller -o build/systolic-tile-controller/controller.vvp rtl/gemm/systolic_array/systolic_tile_controller.sv rtl/gemm/memory/sram.sv rtl/gemm/fifo.sv rtl/gemm/mac.sv rtl/gemm/systolic_array/pe.sv rtl/gemm/systolic_array/systolic_array.sv tb/tb_systolic_tile_controller.sv > build/systolic-tile-controller/compile.log 2>&1 || { cat build/systolic-tile-controller/compile.log; exit 1; }

test-systolic-tile-controller: systolic-tile-controller-compile
	cd build/systolic-tile-controller && $(VVP) -l run.log controller.vvp +SEED=$(SEED)

sram-compile:
	@mkdir -p build/sram
	$(IVERILOG) -g2012 -Wall -s tb_sram -o build/sram/sram.vvp rtl/gemm/memory/sram.sv tb/tb_sram.sv > build/sram/compile.log 2>&1 || { cat build/sram/compile.log; exit 1; }
	$(IVERILOG) -g2012 -Wall -s tb_sram -Ptb_sram.DATA_WIDTH=16 -Ptb_sram.DEPTH=7 -o build/sram/sram-7x16.vvp rtl/gemm/memory/sram.sv tb/tb_sram.sv > build/sram/compile-7x16.log 2>&1 || { cat build/sram/compile-7x16.log; exit 1; }

test-sram: sram-compile
	cd build/sram && $(VVP) -l run.log sram.vvp
	cd build/sram && $(VVP) -l run-7x16.log sram-7x16.vvp

fifo-compile:
	@mkdir -p build/fifo
	$(IVERILOG) -g2012 -Wall -s tb_fifo -o build/fifo/fifo.vvp rtl/gemm/fifo.sv tb/tb_fifo.sv > build/fifo/compile.log 2>&1 || { cat build/fifo/compile.log; exit 1; }

test-fifo: fifo-compile
	cd build/fifo && $(VVP) -l run.log fifo.vvp +SEED=$(SEED)

test-fifo-configs:
	@set -e; for depth in 2 4 6 8; do \
	  for width in 1 8 15 32; do \
	    out_dir=build/fifo/config-$$depth-x-$$width; \
	    mkdir -p "$$out_dir"; \
	    $(IVERILOG) -g2012 -Wall -DFIFO_PARAMETERIZED -s tb_fifo \
	      -Ptb_fifo.DEPTH=$$depth -Ptb_fifo.DATA_WIDTH=$$width \
	      -o "$$out_dir/fifo.vvp" rtl/gemm/fifo.sv tb/tb_fifo.sv > "$$out_dir/compile.log" 2>&1 \
	      || { cat "$$out_dir/compile.log"; exit 1; }; \
	    (cd "$$out_dir" && $(VVP) -l run.log fifo.vvp +SEED=$(SEED)); \
	  done; \
	done

test-fifo-vcs:
	@mkdir -p build/fifo/vcs
	cd build/fifo/vcs && $(VCS) -full64 -sverilog -top tb_fifo ../../../rtl/gemm/fifo.sv ../../../tb/tb_fifo.sv -o simv -l compile.log
	cd build/fifo/vcs && ./simv -l run.log +SEED=$(SEED)

check: env smoke test-python
