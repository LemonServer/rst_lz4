# Generated Sorting Networks

This directory contains auto-generated optimal sorting networks for different batch sizes.

## Files

- `seq_sorter_b8.sv` - 8-input sorter (6 layers, 19 CEs)
- `seq_sorter_b16.sv` - 16-input sorter (9 layers, 61 CEs)
- `seq_sorter_b24.sv` - 24-input sorter (12 layers, 122 CEs)

## Regeneration

To regenerate or create new sorters:

```bash
cd ../../synthesis/scripts
./generate_sorter.py <batch_size> ../compressor/generated/seq_sorter_b<batch_size>.sv
```

Available batch sizes: 2-24 (see `generate_sorter.py` for complete list)

## Optimal Networks

These networks use the optimal sorting networks with preference for:
1. Fewer layers (lower latency)
2. Fewer compare-exchange elements (lower area) when layer count is equal

The networks are based on research from:
- Codish et al. (optimal networks for small sizes)
- Bundala & Závodný (proving optimality)
- Various contributions from sorting network researchers

## Usage in Synthesis

These files are used by `synthesis/scripts/synth_sorter.tcl` during synthesis sweeps.
The sweep script automatically generates all required sizes.
