# SystemVerilog Code Readability Reference

Adapted from the supplied **SystemVerilog Coding Standards**, version 1.0,
September 30, 2026. The original standards were written for SiliconBadgers;
their project-specific conventions and examples are retained below.

## Purpose and AI usage

**Use this file only when I ask an AI to help improve the readability of my
existing SystemVerilog code.**

Its purpose is to make RTL and testbenches easier for me to read, understand,
and follow through clearer formatting, organization, internal names, and
comments. It is not a general guide for writing new code, fixing bugs,
optimizing hardware, or conducting a full engineering review.

Do not apply this guide to conversational tone, answer length, explanations,
chat formatting, or other non-code responses. It is a standalone reference
that I can attach or point to; it is not a global instruction file for every
conversation or task.

### How to apply it to readability work

- Follow the scope of my current request. My explicit instructions for that
  request take precedence over this reference.
- Preserve functionality: arithmetic, widths, signedness, cycle timing,
  handshake behavior, reset behavior, and externally visible interfaces must
  remain unchanged during readability work.
- Use consistent indentation, spacing, line breaks, and grouping to make the
  existing logic easier to follow.
- Clarify internal names where helpful and update their references consistently.
  Preserve public module and port names unless I explicitly request a rename.
  Avoid renaming solely to enforce a
  convention when the existing name is already clear and consistent.
- Add or improve comments that explain intent, timing, or non-obvious behavior.
  Avoid comments that merely repeat the code.
- Organize existing code for clarity without redesigning the architecture,
  changing algorithms, adding features, or introducing unnecessary abstractions.
- Treat the broader engineering and pull-request guidance below as background
  for understanding the code. It does not require adding assertions, expanding
  tests, changing reset strategies, or performing an unrelated review as part
  of a readability request.
- Examples illustrate conventions. They do not require adding the example
  hierarchy, adopting an asynchronous reset, or replacing an existing protocol.
- Preserve third-party source conventions, license notices, and attribution.
  Apply this guide to project-authored code and integration code.
- Existing files may not follow every convention. Keep cleanup within the
  requested scope rather than treating this document as a request to rewrite
  the entire repository.

Example request:

> Make this SystemVerilog code easier to read using SYSTEMVERILOG_STYLE.md.
> Preserve its functionality, cycle timing, and public interface.

**This readability-only scope takes precedence over broader wording in the
original standards below.** Apply their conventions only where they help the
requested readability improvement. They are not a request to bring the entire
design into compliance. Within that scope, **must** and **must not** identify
requirements, and **prefer** identifies a default.

## 1. Naming

Names must describe the block’s responsibility and the signal’s meaning. Use the same name for a module and its source file. Avoid abbreviations that require reading the implementation to understand them.

| Construct | Convention | Example |
| --- | --- | --- |
| Modules, signals, functions, tasks | lower_snake_case | riscv_wrapper, decode_route |
| Instances | u_ followed by the role | u_riscv, u_command_router |
| Input / output / bidirectional ports | _i / _o / _io, except clk, rst, clr | cmd_valid_i, cmd_ready_o |
| Clock / reset / operation clear | clk / rst / clr; no direction suffix | clk, rst, clr |
| Active-low signals | _n; before a direction suffix when present | rst_n, ready_ni |
| Registered state / next-state value | _q / _d when applicable | route_q, route_d |
| Tunable parameters | UpperCamelCase; explicit type | NumLanes, DataWidth |
| Fixed constants | ALL_CAPS; explicit type | COMMAND_ABI_VERSION |
| Enum types / members, including FSM states | _e / ALL_CAPS with underscores | state_e, LOAD_FIFO |
| Struct and other typedefs | _t | command_t, completion_t |
| Packages | Specific purpose followed by _pkg | command_pkg |
| Testbenches | Block name followed by _tb | command_router_tb |
| Simulation tops | Purpose followed by _sim_top | control_path_sim_top |

Use domain prefixes when needed to prevent collisions; do not add an automatic `sb_` prefix to new project modules. Preserve upstream names such as `ibex_core` and `cv32e40p_top`.

Keep related signals together by prefix: `cmd_valid`, `cmd_ready`, and `cmd`. Include units when otherwise ambiguous, such as `timeout_cycles` or `stride_bytes`. Define stride units before choosing a name. Conventional matrix dimensions `m`, `n`, and `k` are acceptable when documented.

Use `clk`, `rst`, and `clr` consistently for clock, reset, and operation-clear
ports. Within a parent module, use a role prefix when needed: `core_rst`,
`mac_clr`, or `array_clr`. Do not spell these signal names `clock`, `reset`, or
`clear`. Keep required board/vendor names at external boundaries documented.

FSM state names must be **ALL_CAPS**, with underscores between words, in both
declarations and references: `IDLE`, `LOAD_FIFO`, `COMPUTE_ARRAY`, `STORE`,
`FINISH`. Keep enum types such as `state_e` and state registers such as `state_q`
lowercase. Renaming a state must preserve its encoding, transitions, and timing.

The naming baseline comes from [lowRISC’s Naming section](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md#naming). The `u_` instance prefix and the hierarchy names below are SiliconBadgers choices, not SystemVerilog language requirements.

### Hierarchy names

| Name | Responsibility |
| --- | --- |
| soc_top | System hardware assembly connecting CPU, control, compute, and memory |
| riscv_wrapper | Adapt the selected RISC-V core to the system’s common interface |
| command_controller | Command sequencing and execution control |
| command_router | Decode and route commands to execution destinations |
| engine_stub | Explicitly unimplemented execution endpoint |
| command_pkg | Shared command, completion, and routing definitions |
| command_router_test_top | Test assembly containing the router and fixture endpoints |
| control_path_sim_top | Host-assisted simulation assembly |

These names define responsibilities; they do not require every listed module to exist. Introduce hierarchy when it provides a real interface or verification boundary. A simulation wrapper must not be presented as the complete hardware SoC.

## 2. Source layout and formatting

- Use `.sv` for SystemVerilog sources and `.svh` for included headers.
- Use four-space indentation, LF line endings, and a 100-character line target.
- Put one port declaration, named port connection, and procedural statement on each line.
- Place imports, types, parameters, and signal declarations before instances and procedural logic.
- Use `begin` and `end` for procedural branches. Label named generate blocks and assertions.
- Keep one primary module per source file. Use packages for shared declarations.
- Preserve required license and attribution headers. Comments should explain constraints, behavior, or rationale.

The formatting baseline follows [lowRISC’s Verilog/SystemVerilog style guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md), particularly its guidance on indentation, line length, declarations, and module organization.

## 3. Types, widths, and configuration

Use `logic`, explicitly sized vectors, packed structs, and enums to make interfaces precise. Use explicit signed types and casts where signed arithmetic is intended.

- Type parameters and constants explicitly. Use `parameter` for configurable values and `localparam` for derived or module-local constants.
- Use named constants for protocol encodings and array dimensions. Do not repeat numeric route indices.
- Define externally visible opcodes and status encodings explicitly. Internal enum encodings may remain automatic when no interface depends on them.
- Make extension and truncation intentional. Review signedness, multiplication width, accumulator width, rounding, and saturation.
- Use `'0` and `'1` for context-sized fills. Prefer sized literals at hardware interfaces.
- Check supported parameter ranges. Handle width expressions such as `$clog2(1)` deliberately.
- Prefer parameters and generate blocks for hardware configuration. Use compile-time defines only when the build requires source selection or tool compatibility.
- Prevent implicit-net mistakes through lint or an explicitly configured net-declaration policy.

The use of shared types and packages follows Sutherland and Mills’ [*Synthesizing SystemVerilog*, §2.6 and §4.1, pp. 9–16](https://sutherland-hdl.com/papers/2013-SNUG-SV_Synthesizable-SystemVerilog_paper.pdf#page=9). These constructs keep declarations consistent across modules and reduce accidental type and width mismatches.

## 4. Combinational and sequential logic

Use `always_comb` with blocking assignments for combinational procedures. Assign every output on every path, normally by establishing defaults first. Use continuous assignments for simple expressions.

Use `always_ff` with nonblocking assignments for registers. Give each stored value one procedural driver. Keep update priority explicit; avoid multiple independent assignments to the same register within one clocked block.

The assignment discipline follows Cliff Cummings’ [*Nonblocking Assignments in Verilog Synthesis, Coding Styles That Kill!*, §5, guidelines 1, 3, 5, and 6](https://rfsoc.mit.edu/6S965/_static/F25/lectures/CummingsSNUG2000SJ_NBA.pdf#page=5). The paper explains how assignment scheduling can cause simulation races even when synthesis produces plausible hardware.

Sutherland and Mills’ [*Synthesizing SystemVerilog*, §5.1, pp. 17–20](https://sutherland-hdl.com/papers/2013-SNUG-SV_Synthesizable-SystemVerilog_paper.pdf#page=17) explains how `always_comb` and `always_ff` express design intent and enable additional tool checks.

The following fragment illustrates a pending flag with an explicit next-state value. The containing interface must define whether simultaneous acceptance and retirement are permitted.

```systemverilog
logic pending_d;
logic pending_q;

always_comb begin
    pending_d = pending_q;

    if (retire) begin
        pending_d = 1'b0;
    end

    if (accept) begin
        pending_d = 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        pending_q <= 1'b0;
    end else begin
        pending_q <= pending_d;
    end
end
```

A simple enabled register does not require a separate next-state block. Choose the form that makes behavior easiest to review. Do not use `casex` in control RTL. Use `unique case` only when its exclusivity and completeness assumptions are valid; define illegal-input behavior explicitly.

## 5. Interfaces and module boundaries

Use named parameter and port connections. The shorthand `.clk` is allowed when the local signal has the same name. Do not use positional connections or wildcard `.*` connections.

Account for every upstream port: connect required signals, tie off unused inputs with correctly sized values, and mark intentionally unused outputs with explicit empty connections or documented unused signals. Do not hide incomplete integration behind a blanket missing-port waiver.

Document each interface’s clock, reset, units, ownership, supported transactions, and error behavior. Packed structs group related fields but do not, by themselves, define a software-visible memory layout or ABI.

Our explicit-connection policy follows [lowRISC’s module-instantiation guidance](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md#module-instantiation). Sutherland and Mills discuss both dot-name and wildcard connections; this standard deliberately permits only dot-name shorthand so reviewers can see each connection.

### Ready/valid channels

- A transfer occurs on the active clock edge when both `valid` and `ready` are asserted.
- The producer must hold `valid` and its payload stable while stalled.
- The producer must not wait for `ready` before asserting `valid`.
- Capture or otherwise preserve accepted payloads; do not depend on subsequent input values.
- Avoid combinational handshake loops. Document any intentional combinational path across a boundary.
- Specify queue capacity, ordering, simultaneous transfers, and backpressure behavior.

For the reasoning behind these handshake rules, see Charles Eric LaForest’s [*Rules for Ready/Valid Handshakes*](https://fpgacpu.ca/fpga/handshake.html), especially “Loops,” “Avoiding Deadlocks and Livelocks,” and “Internal State.” It explains why waiting for ready can deadlock a channel and why state changes must follow completed handshakes.

## 6. Clocks, reset, clear, and shutdown

Document the clock and reset domain of each interface. Use `clk` for the clock,
`rst` for active-high reset, and `clr` for active-high operation clear. A required
active-low reset uses `rst_n`; a name does not change polarity or synchrony.

Keep reset and operation clear distinct. `rst` initializes or aborts a block;
`clr` clears its datapath for the next dot product or tile without resetting the
surrounding controller. Where both exist, make priority explicit:
`rst > clr > enable`. In this project's MAC, PE, and array, both are synchronous;
clear must work even when enable is low, and must also discard forwarded operands
so that data from a previous tile cannot enter the next one. Do not fold an
operation clear into the reset connection.

Only add `clr` where the block needs an operation-clear function. A naming cleanup
does not require unused clear ports on controllers, SRAMs, or wrappers. Preserve
existing board reset synchronization and each block's reset behavior unless I
explicitly request a functional change.

For asynchronous resets, provide safe deassertion in each receiving clock domain or document the upstream guarantee. Reset externally visible control state to a defined condition. Reset datapath storage only where functionality requires it.

Use reviewed clock-domain-crossing structures. Multi-bit transfers require a coherent transfer protocol; independently synchronizing each bit is insufficient. Do not gate clocks with ordinary combinational logic.

Specify what reset and quiesce do to accepted work, pending memory transactions, and completions. State whether work drains, is cancelled, or must be retried.

## 7. Stubs and simulation models

A stub must identify its unsupported behavior and preserve the interface contract. An unimplemented operation must return an explicit unsupported/error result or be rejected according to the protocol; it must not report successful computation.

Keep test fixtures, host memory models, and software reference calculations distinguishable from synthesizable hardware. Document where computation actually occurs. A passing software-assisted simulation is not evidence that an unimplemented datapath works.

## 8. Assertions and tests

Give assertions descriptive labels. Check interface invariants close to the block that owns them.

```systemverilog
CompletionStable_A: assert property (
    @(posedge clk) disable iff (rst)
    completion_valid_o && !completion_ready_i
    |=> completion_valid_o && $stable(completion_o)
);
```

This property checks stalled completion stability. It does not prove eventual completion or correctness of the returned result.

Tests must cover applicable normal, invalid-input, backpressure, reset, and boundary cases. Exercise supported parameter configurations and define a timeout. Testbenches using delays must declare `timeunit` and `timeprecision`; drive and sample signals with a deliberate scheduling convention that avoids races.

Distinguish simulation, formal verification, synthesis, timing analysis, and CDC/reset checks in reported results. Two-state simulation does not establish four-state/X behavior.

Sutherland and Mills’ [*Synthesizing SystemVerilog*, §9.5, p. 36](https://sutherland-hdl.com/papers/2013-SNUG-SV_Synthesizable-SystemVerilog_paper.pdf#page=36) explains how scoped `timeunit` and `timeprecision` avoid compilation-order dependence from `timescale` directives. Cummings’ [discussion of simulation races, §2](https://rfsoc.mit.edu/6S965/_static/F25/lectures/CummingsSNUG2000SJ_NBA.pdf#page=2) provides the rationale for deliberate testbench scheduling.

## References

The naming and formatting baseline is the [lowRISC SystemVerilog style guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md). This page makes explicit project choices, including the `u_` instance prefix and fixed-constant naming.

For RTL modeling and language semantics:

- Stuart Sutherland, [RTL Modeling with SystemVerilog for Simulation and Synthesis](https://sutherland-hdl.com/books_and_guides.html).
- Clifford E. Cummings, [Nonblocking Assignments in Verilog Synthesis, Coding Styles That Kill!](https://rfsoc.mit.edu/6S965/_static/F25/lectures/CummingsSNUG2000SJ_NBA.pdf).
- Stuart Sutherland and Don Mills, [Synthesizing SystemVerilog](https://sutherland-hdl.com/papers/2013-SNUG-SV_Synthesizable-SystemVerilog_paper.pdf). Tool-support observations in this paper reflect its publication date.

For concrete integration examples:

- [Ibex top-level RTL](https://github.com/lowRISC/ibex/blob/master/rtl/ibex_top.sv).
- [OpenTitan RISC-V core interfaces](https://opentitan.org/book/hw/ip/rv_core_ibex/doc/interfaces.html).
- [CV32E40P integration documentation](https://github.com/openhwgroup/cv32e40p/blob/master/docs/source/integration.rst).
- [PULP common-cells FIFO](https://github.com/pulp-platform/common_cells/blob/master/src/cc_fifo.sv).
