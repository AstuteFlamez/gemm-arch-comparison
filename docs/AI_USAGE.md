# AI Usage

I used AI throughout this project, mainly to help with verification, tooling,
and making the code easier to read.

## What I worked on

- Developing the architectures and working through the RTL.
- Choosing the comparison: four MACs in each design, with the same shared blocks.
- Designing the experiment, deciding what to measure, and interpreting the results.
- Inspecting a few simulation waveforms in Verdi myself.

## Where AI helped

- Drafting and fixing some RTL when I asked for implementation help.
- Creating testbenches, random input generators, and Python tests.
- Cleaning up comments, naming, and readability using
  [SYSTEMVERILOG_STYLE.md](SYSTEMVERILOG_STYLE.md).
- Setting up the Synopsys flow, checking reports, and running most of the experiment.
- Generating the graphs and helping turn my documentation drafts into these pages.

The repo includes AI-generated and AI-edited code. My contribution was the design
work and decisions, alongside implementation and learning how the pieces fit
together. The tests checked every matrix result against an independent mathematical
reference; passing those checks supports correctness, but doesn't prove that
either architecture is optimal.
