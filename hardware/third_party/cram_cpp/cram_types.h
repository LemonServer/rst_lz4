#ifndef CRAM_TYPES_H
#define CRAM_TYPES_H

#include <bitset>

// Keep extra headroom in the temporary dictionary bit buffer so sweeps above
// the default 128 B configuration do not fail while assembling DictBits.
// The actual algorithmic budget is still enforced by the memory_blocks checks
// in cram_impl.cpp.
static constexpr int DICT_BITS_SIZE = 65536;

// DictBits holds the fixed-size bitset plus the number of valid bits stored.
struct DictBits {
    std::bitset<DICT_BITS_SIZE> bits;
    int length = 0; // Number of valid bits currently stored.
};

#endif // CRAM_TYPES_H
