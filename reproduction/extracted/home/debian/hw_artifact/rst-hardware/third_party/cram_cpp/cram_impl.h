#ifndef CRAM_IMPL
#define CRAM_IMPL

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <deque>
#include <algorithm>
#include <cassert>
#include <unordered_map>
#include <map>
#include <future>
#include <filesystem>
#include <cmath>
#include <mutex>
#include <cstdint>
#include <limits>

#include "cram_tree.h"
#include "tsl/robin_map.h" 

// Constants.
static constexpr int CHUNK_SIZE = 128;
static constexpr int DECOMPRESSOR_LIFOS = 16;
static constexpr int MAX_CODES_PER_CYCLE = 8;
static constexpr int MAX_BITS_PER_CYCLE = 32;

// -------------------------------------------------------------------
// Padding and Chunking functions.
std::vector<MetaByte*> padInput(const std::vector<uint8_t>& page);
std::vector<uint8_t> unpadOutput(const std::vector<MetaByte*>& meta);

template <typename T>
std::vector<std::vector<T>> chunkInput(const std::vector<T>& input, size_t chunkSize);

template <typename T>
std::vector<T> unchunkOutput(const std::vector<std::vector<T>>& chunks);

template <typename InT, typename OutT, typename Func, typename... Args>
std::vector<std::vector<OutT>> applyChunkwise(
    Func&& func,
    const std::vector<std::vector<InT>>& chunkedData,
    Args&&... args);

template <typename T>
std::vector<std::vector<T>> slidingWindow(const std::vector<T>& input, size_t n);

size_t totalLength(const std::vector<std::vector<MetaByte*>>& chunks);

// -------------------------------------------------------------------
// Vector hashing and equality (for use in unordered maps, etc.)
struct VectorHash
{
    size_t operator()(const std::vector<MetaByte*>& v) const
    {
         std::size_t seed = v.size();
         for (auto x : v) {
             int p = x->numEncoding();
             p = ((p >> 16) ^ p) * 0x45d9f3b;
             p = ((p >> 16) ^ p) * 0x45d9f3b;
             p = (p >> 16) ^ p;
             seed ^= p + 0x9e3779b9 + (seed << 6) + (seed >> 2);
         }
         return seed;
    }
};

struct VectorEq
{
    bool operator()(const std::vector<MetaByte*>& a, const std::vector<MetaByte*>& b) const
    {
        if (a.size() != b.size()) return false;
        for (size_t i = 0; i < a.size(); i++) {
            if (a[i]->numEncoding() != b[i]->numEncoding()) {
                return false;
            }
        }
        return true;
    }
};

// -------------------------------------------------------------------
// Core Compression/Decompression function declarations.

// Returns the best candidate metabyte sequence from the provided chunks.
std::vector<MetaByte*> findBestMetabyteSeq(
    const std::vector<std::vector<MetaByte*>>& metabyteChunks,
    int64_t total_bits);

std::tuple<std::vector<MetaByte*>, std::vector<std::vector<MetaByte*>>, int>
cramIteration(const std::vector<std::vector<MetaByte*>>& chunks, CRAMSub* subByte, const std::vector<MetaByte*>& best);

std::pair<std::vector<std::string>, DictBits>
cramEncode9b(const std::vector<std::vector<MetaByte*>>& metabyteChunks, int memory_blocks);

std::pair<std::vector<MetaByte*>, int> cramDecodeSingleChunk(const std::string &chunkBits);
std::pair<MetaByte*, std::string> decodeDictMetabyte(const std::string &bits);

struct CRAMDictionary {
    std::vector<std::vector<MetaByte*>> expansions;
    std::vector<int> seqLengths;
};

std::pair<CRAMDictionary, int> parseDictBits(const DictBits &dictBitsFull);

std::pair<std::vector<std::vector<MetaByte*>>, std::vector<int>>
cramDecodeAllChunks(const std::vector<std::string>& compressedChunks, const DictBits &dictBits);

std::pair<std::vector<std::string>, DictBits>
compressAllStages(const std::vector<uint8_t>& page, int memoryBlocks, size_t chunkSize);

std::pair<std::vector<uint8_t>, std::vector<int>>
decompressAllStages(const std::vector<std::string>& compressedChunks, const DictBits &dictBits, size_t chunkSize);

std::pair<std::vector<uint8_t>, std::vector<int>>
decompressOneChunkAllStages(const std::string &compressedChunk, const DictBits &dictBits, size_t chunkSize);

std::vector<std::string> fastCompress(const std::vector<uint8_t>& page,
    size_t chunkSize,
    const DictBits &dict_bits);

std::string write_and_recompress(const std::string &metabyte_chunk,
                                 const std::vector<uint8_t> &new_block,
                                 size_t block_idx,
                                 const DictBits &dict_bits,
                                 size_t chunk_size);

struct CompressMetrics {
    size_t dictSizeBits;
    std::vector<size_t> chunkSizes;
};

struct PageResult {
    std::string line;
    bool matched;
    std::vector<int> timing;
};

CompressMetrics measureCompress(const std::vector<std::string>& compressedChunks, const DictBits &dictBits);

PageResult processPage(const std::vector<uint8_t>& page, int memBlocks, size_t chunkSize);

#endif // CRAM_IMPL