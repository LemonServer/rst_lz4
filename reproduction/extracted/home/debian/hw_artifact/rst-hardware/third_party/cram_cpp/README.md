This directory vendors the small subset of `cram_cpp` sources needed by the
reviewer-facing and internal validation flows.

It is the only in-repo source of truth for the C++ reference files. The copied
files match the authoritative external `cram_cpp` checkout byte-for-byte,
excluding unrelated build/test/results collateral.

Included files:

- `cram_impl.cpp`
- `cram_impl.h`
- `cram_tree.cpp`
- `cram_tree.h`
- `cram_types.h`
- `tsl/robin_growth_policy.h`
- `tsl/robin_hash.h`
- `tsl/robin_map.h`

They are used by:

- `helpful_files/cram_cpp_vendor.py` for shared path and completeness checks
- `helpful_files/rst_experimental_format.py` for static-tree parsing
- `tools/compare_ratio_models.py` and `tools/cram_cpp_page_metrics.cpp` for
  side-by-side ratio comparison against the reference C++ implementation
