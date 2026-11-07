#include <iostream>
#include <cstring>
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
#include <tuple>
#include <cstdlib>
#include <bitset>
#include <stdexcept>

#include "cram_types.h"
#include "cram_tree.h"
#include "cram_impl.h"

//---------------------------------------------------------------------
// Define some constants for cycle limits (if not defined already).
#ifndef MAX_CODES_PER_CYCLE
#define MAX_CODES_PER_CYCLE 64
#endif

#ifndef MAX_BITS_PER_CYCLE
#define MAX_BITS_PER_CYCLE 512
#endif

#ifndef DECOMPRESSOR_LIFOS
#define DECOMPRESSOR_LIFOS 8
#endif

// Append a string of '0' and '1' characters into a DictBits object.
void appendBits(DictBits &db, const std::string &s) {
    for (char c : s) {
        if (db.length < DICT_BITS_SIZE) {
            db.bits[db.length] = (c == '1');
            db.length++;
        } else {
            throw std::runtime_error("Dictionary bitset overflow");
        }
    }
}

// Convert a DictBits object to its string representation (from bit 0 to length-1).
std::string dictBitsToString(const DictBits &db) {
    std::string s;
    s.reserve(db.length);
    for (int i = 0; i < db.length; i++) {
         s.push_back(db.bits[i] ? '1' : '0');
    }
    return s;
}

// Convert an integer to a binary string with fixed width.
std::string toBinaryString(int val, int width) {
    std::string s;
    s.reserve(width);
    for (int i = width - 1; i >= 0; i--) {
        s.push_back(((val >> i) & 1) ? '1' : '0');
    }
    return s;
}

//---------------------------------------------------------------------
// ---------- Candidate Representation ----------
struct Candidate {
    uint8_t len;         // The candidate length (between 2 and 5)
    MetaByte* ptr[5];    // The candidate MetaByte* pointers
};

// Compute a 64-bit packed key from a Candidate.
// The top 4 bits hold the candidate length, then 9 bits per element.
static inline uint64_t packCandidate(const Candidate &cand) {
    uint64_t key = ((uint64_t)cand.len << 60);
    for (uint8_t i = 0; i < cand.len; ++i) {
        int encoding = cand.ptr[i]->numEncoding();
        key |= ((uint64_t)encoding & 0x1FF) << (i * 9);
    }
    return key;
}

// ---------- Hash Record Structure ----------
struct HashRecord {
    float score = 0.0f;
    Candidate candidate;
    bool hasCandidate = false;
};

template std::vector<std::vector<uint8_t>> chunkInput(const std::vector<uint8_t>& data, size_t chunkSize);

//---------------------------------------------------------------------
// ---------- Padding / Unpadding Functions ----------
std::vector<MetaByte*> padInput(const std::vector<uint8_t>& page)
{
    std::vector<MetaByte*> meta;
    meta.reserve(page.size());
    for (auto b : page) {
        meta.push_back(LitByte::getInstance(b));
    }
    return meta;
}

std::vector<uint8_t> unpadOutput(const std::vector<MetaByte*>& meta)
{
    std::vector<uint8_t> bytes;
    bytes.reserve(meta.size());
    for (auto m : meta) {
        auto lb = dynamic_cast<LitByte*>(m);
        assert(lb && "unpadOutput found a non-LitByte in the stream!");
        bytes.push_back(static_cast<uint8_t>(lb->numEncoding()));
    }
    return bytes;
}

template <typename T>
std::vector<std::vector<T>> chunkInput(const std::vector<T>& input, size_t chunkSize)
{
    std::vector<std::vector<T>> output;
    size_t i = 0;
    while (i < input.size()) {
        size_t end = std::min(i + chunkSize, input.size());
        output.emplace_back(input.begin() + i, input.begin() + end);
        i = end;
    }
    return output;
}

template <typename T>
std::vector<T> unchunkOutput(const std::vector<std::vector<T>>& chunks)
{
    std::vector<T> out;
    size_t total = 0;
    for (auto &chunk : chunks) {
        total += chunk.size();
    }
    out.reserve(total);
    for (auto &chunk : chunks) {
        out.insert(out.end(), chunk.begin(), chunk.end());
    }
    return out;
}

template <typename InT, typename OutT, typename Func, typename... Args>
std::vector<std::vector<OutT>> applyChunkwise(
    Func&& func,
    const std::vector<std::vector<InT>>& chunkedData,
    Args&&... args)
{
    std::vector<std::vector<OutT>> result;
    result.reserve(chunkedData.size());
    for (const auto& chunk : chunkedData) {
        result.push_back(func(chunk, std::forward<Args>(args)...));
    }
    return result;
}

size_t totalLength(const std::vector<std::vector<MetaByte*>>& chunks)
{
    size_t total = 0;
    for (auto &c : chunks) {
        total += c.size();
    }
    return total;
}

//---------------------------------------------------------------------
// ---------- Core Compression Functions ----------

std::vector<MetaByte*> findBestMetabyteSeq(
    const std::vector<std::vector<MetaByte*>> &metabyteChunks,
    int64_t total_bits,
    tsl::robin_map<uint64_t, HashRecord, std::hash<uint64_t>, std::equal_to<uint64_t>,
                      std::allocator<std::pair<uint64_t, HashRecord>>, false, tsl::rh::prime_growth_policy> &table)
{
    table.clear();
    
    for (const auto &chunk : metabyteChunks) {
        size_t m = chunk.size();
        for (size_t i = 0; i < m; ++i) {
            for (uint8_t L = 2; L <= 5; ++L) {
                if (i + L > m)
                    break;
                Candidate cand;
                cand.len = L;
                std::memcpy(cand.ptr, &chunk[i], L * sizeof(MetaByte*));
                uint64_t key = packCandidate(cand);
                float inc = 9.0f * (L - 1);
                auto &rec = table[key];
                rec.score += inc;
                if (!rec.hasCandidate) {
                    rec.candidate = cand;
                    rec.hasCandidate = true;
                }
            }
        }
    }
    
    float bestScore = -std::numeric_limits<float>::max();
    Candidate bestCandidate;
    bool found = false;
    
    for (const auto &pair : table) {
        const HashRecord &rec = pair.second;
        if (!rec.hasCandidate)
            continue;
        uint8_t L = rec.candidate.len;
        int dictSize = static_cast<int>(L * 9 + 2);
        int true_size = 0;
        float finalScore = (rec.score - dictSize) / static_cast<float>(dictSize);
        if (finalScore > bestScore) {
            for (uint8_t i = 0; i < L; i++) {
                true_size += rec.candidate.ptr[i]->getDictBinaryLen();
            }
            if (true_size <= total_bits) {
                bestScore = finalScore;
                bestCandidate = rec.candidate;
                found = true;
            }
        }
    }
    std::vector<MetaByte*> result;
    if (found) {
        result.resize(bestCandidate.len);
        for (uint8_t i = 0; i < bestCandidate.len; i++) {
            result[i] = bestCandidate.ptr[i];
        }
    }
    return result;
}

std::tuple<std::vector<MetaByte*>, std::vector<std::vector<MetaByte*>>, int> 
cramIteration(const std::vector<std::vector<MetaByte*>>& chunks,
              CRAMSub* subByte,
              const std::vector<MetaByte*>& best)
{
    int dictEntrySize = 0;
    for (auto m : best) {
        dictEntrySize += static_cast<int>(m->getDictBinaryLen());
    }
    dictEntrySize += 2;

    std::vector<std::vector<MetaByte*>> newChunks;
    newChunks.reserve(chunks.size());

    for (auto &chunk : chunks) {
        std::vector<MetaByte*> newChunk;
        newChunk.reserve(chunk.size());
        size_t idx = 0;
        while (idx < chunk.size()) {
            bool matched = false;
            if (idx + best.size() <= chunk.size()) {
                bool equal = true;
                for (size_t k = 0; k < best.size(); k++) {
                    if (chunk[idx + k] != best[k]) {
                        equal = false;
                        break;
                    }
                }
                if (equal) {
                    newChunk.push_back(subByte);
                    idx += best.size();
                    matched = true;
                }
            }
            if (!matched) {
                newChunk.push_back(chunk[idx]);
                idx++;
            }
        }
        newChunks.push_back(std::move(newChunk));
    }
    return std::make_tuple(best, newChunks, dictEntrySize);
}

//---------------------------------------------------------------------
// The compress function now builds a dictionary as a DictBits instance.
// (Other parts of the compression remain unchanged.)
std::pair<std::vector<std::string>, DictBits>
cramEncode9b(const std::vector<std::vector<MetaByte*>>& metabyteChunks,
             int memory_blocks)
{
    int64_t totalBits = static_cast<int64_t>(memory_blocks) * 64 * 8 - 6; 

    std::vector<MetaByte*> reuse_chrs = { 
        CRAMSub::getInstance(63), CRAMSub::getInstance(64), 
        CRAMSub::getInstance(65), CRAMSub::getInstance(66),
        CRAMSub::getInstance(67), CRAMSub::getInstance(68),
        CRAMSub::getInstance(69), CRAMSub::getInstance(70)
    };

    std::vector<std::vector<MetaByte*>> subs;
    std::vector<MetaByte*> subs_flat;
    std::vector<MetaByte*> reuse_subs_flat;
    std::vector<std::vector<MetaByte*>> compressed = metabyteChunks;
    int nextSubVal = 0;

    tsl::robin_map<uint64_t, HashRecord, std::hash<uint64_t>, std::equal_to<uint64_t>,
                      std::allocator<std::pair<uint64_t, HashRecord>>, false, tsl::rh::prime_growth_policy> table;

    while (true) {
        if (nextSubVal >= 63) {
            break;
        }
        std::vector<MetaByte*> bestSeq;
        if (nextSubVal == 0) {
            bestSeq = std::vector<MetaByte*>{LitByte::getInstance(0), LitByte::getInstance(0)};
        } else if (nextSubVal == 1) {
            bestSeq = std::vector<MetaByte*>{CRAMSub::getInstance(0), CRAMSub::getInstance(0)};
        } else {
            bestSeq = findBestMetabyteSeq(compressed, totalBits, table);
        }
        if (bestSeq.empty()) {
            break;
        }
        CRAMSub* subByte = CRAMSub::getInstance(nextSubVal);
        std::vector<std::vector<MetaByte*>> oldCompressed = compressed;
        auto iterResult = cramIteration(compressed, subByte, bestSeq);
        std::vector<MetaByte*> seqUsed = std::get<0>(iterResult);
        std::vector<std::vector<MetaByte*>> newCompressed = std::get<1>(iterResult);
        int dictEntrySize = std::get<2>(iterResult);
        int64_t oldLen = static_cast<int64_t>(totalLength(oldCompressed));
        int64_t newLen = static_cast<int64_t>(totalLength(newCompressed));

        std::vector<MetaByte *> new_rep;
        for (int i = 0; i < static_cast<int>(seqUsed.size()); i++) {
            int curr_size = seqUsed[i]->getDictBinaryLen();
            int best_savings = 0;
            int match_num = -1;
            for (int j = 0; j < static_cast<int>(reuse_chrs.size()); j++) {
                int look_back = j + 1;
                int overflow = 0;
                int possible_savings = curr_size - reuse_chrs[j]->getDictBinaryLen();
                if (look_back > i) {
                    overflow = look_back - i;
                }
                if (overflow == 0 && i - look_back >= 0 && seqUsed[i] == seqUsed[i - look_back] && possible_savings > best_savings) {
                    best_savings = possible_savings;
                    match_num = j;
                } else if (overflow > 0 && subs_flat.size() >= static_cast<size_t>(overflow)) {
                    if (seqUsed[i] == subs_flat[subs_flat.size() - overflow] && possible_savings > best_savings) {
                        best_savings = possible_savings;
                        match_num = j;
                    }
                }
            }
            if (best_savings > 0 && match_num >= 0) {
                new_rep.push_back(reuse_chrs[match_num]);
                dictEntrySize -= best_savings;
            } else {
                new_rep.push_back(seqUsed[i]);
            }
        }

        if (((totalBits - dictEntrySize) < 0) ||
             (((oldLen * 9 - newLen * 9 - dictEntrySize) <= 0) && nextSubVal >= 2))
        {
            compressed = oldCompressed;
            break;
        }
        compressed = newCompressed;
        if (nextSubVal >= 2) {
            totalBits -= dictEntrySize;
            subs.push_back(seqUsed);
            for (size_t i = 0; i < new_rep.size(); i++) {
                reuse_subs_flat.push_back(new_rep[i]);
            }
        }
        for (size_t i = 0; i < seqUsed.size(); i++) {
            subs_flat.push_back(seqUsed[i]);
        }
        nextSubVal++;
    }

    int count = static_cast<int>(subs.size());
    std::string countBits = toBinaryString(count, 6);
    std::string subLengthBits;
    for (size_t i = 0; i < subs.size(); i++) {
        int lengthMinus2 = static_cast<int>(subs[i].size()) - 2;
        if (lengthMinus2 < 0) lengthMinus2 = 0;
        subLengthBits += toBinaryString(lengthMinus2, 2);
    }

    // Build dictionary bits using our DictBits structure.
    DictBits dictBits;
    appendBits(dictBits, countBits);
    appendBits(dictBits, subLengthBits);
    for (size_t i = 0; i < reuse_subs_flat.size(); i++) {
        appendBits(dictBits, reuse_subs_flat[i]->dictBinaryRep());
    }
    if (dictBits.length > memory_blocks * 64 * 8) {
        std::cerr << "Warning: dictionary bits exceed memory block capacity!\n";
    }

    std::vector<std::string> encodedCompressed;
    encodedCompressed.reserve(compressed.size());
    for (size_t i = 0; i < compressed.size(); i++) {
        std::string chunkStr;
        for (size_t j = 0; j < compressed[i].size(); j++) {
            int best_saving = 0;
            int reuse_idx = -1;
            for (int k = 0; k < static_cast<int>(reuse_chrs.size()); k++) {
                int reuse_dist = k + 1;
                int potential_saving = compressed[i][j]->chunkBinaryRep().size() - reuse_chrs[k]->chunkBinaryRep().size();
                if (j >= static_cast<size_t>(reuse_dist) && compressed[i][j - reuse_dist] == compressed[i][j] && potential_saving > best_saving) {
                    best_saving = potential_saving;
                    reuse_idx = k;
                }
            }
            if (best_saving != 0 && reuse_idx >= 0) {
                chunkStr += reuse_chrs[reuse_idx]->chunkBinaryRep();
            } else {
                chunkStr += compressed[i][j]->chunkBinaryRep();
            }
        }
        encodedCompressed.push_back(chunkStr);
    }

    return std::make_pair(encodedCompressed, dictBits);
}

std::pair<std::vector<MetaByte*>, int> cramDecodeSingleChunk(const std::string &chunkBits) {
    std::vector<MetaByte*> decoded;
    std::string remaining = chunkBits;
    int totalCycles = 0;

    while (!remaining.empty()) {
        int codesDecodedThisCycle = 0;
        int bitsProcessedThisCycle = 0;

        while (codesDecodedThisCycle < MAX_CODES_PER_CYCLE &&
               bitsProcessedThisCycle < MAX_BITS_PER_CYCLE &&
               !remaining.empty()) {
            {
                std::pair<MetaByte*, std::string> result = CRAMSub::decodeChunkBinaryRep(remaining);
                if (result.first) {
                    decoded.push_back(result.first);
                    bitsProcessedThisCycle += (remaining.size() - result.second.size());
                    remaining = result.second;
                    codesDecodedThisCycle++;
                    continue;
                }
            }
            {
                std::pair<MetaByte*, std::string> result = LitByte::decodeChunkBinaryRep(remaining);
                if (result.first) {
                    decoded.push_back(result.first);
                    bitsProcessedThisCycle += (remaining.size() - result.second.size());
                    remaining = result.second;
                    codesDecodedThisCycle++;
                    continue;
                }
            }
            break;
        }
        totalCycles++;
    }
    return std::make_pair(decoded, totalCycles);
}

std::pair<MetaByte*, std::string> decodeDictMetabyte(const std::string &bits)
{
    {
        std::pair<MetaByte*, std::string> result = CRAMSub::decodeDictBinaryRep(bits);
        if (result.first) return result;
    }
    {
        std::pair<MetaByte*, std::string> result = LitByte::decodeDictBinaryRep(bits);
        if (result.first) return result;
    }
    return std::make_pair(nullptr, bits);
}

std::pair<std::vector<MetaByte*>, std::size_t> 
expandCRAMSubsCycle(
    const std::vector<MetaByte*>& compressedPage,
    const std::vector<std::vector<MetaByte*>>& expansions,
    const std::vector<int>& seqLengths)
{
    std::deque<MetaByte*> dq(compressedPage.begin(), compressedPage.end());
    std::vector<MetaByte*> output;
    output.reserve(compressedPage.size());
    std::size_t cycles = 0;

    while (!dq.empty())
    {
        if (dq.size() == 1) {
            MetaByte* top = dq.front();
            dq.pop_front();
            CRAMSub* sTop = dynamic_cast<CRAMSub*>(top);
            int topLen = (sTop ? seqLengths[sTop->subIndex()] : 0);
            if (topLen == 0) {
                output.push_back(top);
            } else {
                for (int i = 0; i < topLen; i++) {
                    dq.push_front(expansions[sTop->subIndex()][i]);
                }
            }
        }
        else {
            MetaByte* top    = dq[0];
            MetaByte* bottom = dq[1];
            dq.pop_front();
            dq.pop_front();

            CRAMSub* sTop = dynamic_cast<CRAMSub*>(top);
            CRAMSub* sBot = dynamic_cast<CRAMSub*>(bottom);

            int topLen = (sTop ? seqLengths[sTop->subIndex()] : 0);
            int botLen = (sBot ? seqLengths[sBot->subIndex()] : 0);

            if (botLen == 0 && topLen == 0) {
                output.push_back(top);
                output.push_back(bottom);
            }
            else if (botLen == 0 && topLen > 0) {
                dq.push_front(bottom);
                for (int i = 0; i < topLen; i++) {
                    dq.push_front(expansions[sTop->subIndex()][i]);
                }
            }
            else if (botLen > 0 && topLen > 0) {
                for (int i = 0; i < botLen; i++) {
                    dq.push_front(expansions[sBot->subIndex()][i]);
                }
                for (int i = 0; i < topLen; i++) {
                    dq.push_front(expansions[sTop->subIndex()][i]);
                }
            }
            else {
                output.push_back(top);
                for (int i = 0; i < botLen; i++) {
                    dq.push_front(expansions[sBot->subIndex()][i]);
                }
            }
        }
        cycles++;
    }
    return std::make_pair(output, cycles);
}

//---------------------------------------------------------------------
// Parsing dictionary bits.
std::pair<CRAMDictionary, int> parseDictBits(const DictBits &dictBitsFull)
{
    std::string dictStr = dictBitsToString(dictBitsFull);
    std::vector<MetaByte*> reuse_chrs = { 
        CRAMSub::getInstance(63), CRAMSub::getInstance(64), 
        CRAMSub::getInstance(65), CRAMSub::getInstance(66),
        CRAMSub::getInstance(67), CRAMSub::getInstance(68),
        CRAMSub::getInstance(69), CRAMSub::getInstance(70)
    };
    CRAMDictionary out;
    out.expansions.resize(64, std::vector<MetaByte*>(5, LitByte::getInstance(0)));
    out.seqLengths.resize(64, 0);

    int count = std::stoi(dictStr.substr(0, 6), nullptr, 2);
    size_t idx = 6;

    std::vector<int> lengths;
    lengths.reserve(count);
    lengths.push_back(2);
    lengths.push_back(2);

    for (int i = 0; i < count; i++) {
        if (idx + 2 > dictStr.size()) break;
        int lMinus2 = std::stoi(dictStr.substr(idx, 2), nullptr, 2);
        idx += 2;
        int length = lMinus2 + 2;
        lengths.push_back(length);
    }
    
    std::string remainingDict = dictStr.substr(idx);
    std::vector<MetaByte*> decodedDict;
    int totalCycles = 0;

    while (!remainingDict.empty()) {
        int codesDecodedThisCycle = 0;
        int bitsProcessedThisCycle = 0;
        while (codesDecodedThisCycle < MAX_CODES_PER_CYCLE &&
               bitsProcessedThisCycle < MAX_BITS_PER_CYCLE &&
               !remainingDict.empty()) {
            std::pair<MetaByte*, std::string> decResult = decodeDictMetabyte(remainingDict);
            if (!decResult.first) {
                break;
            }
            decodedDict.push_back(decResult.first);
            bitsProcessedThisCycle += (remainingDict.size() - decResult.second.size());
            remainingDict = decResult.second;
            codesDecodedThisCycle++;
        }
        totalCycles++;
    }
    std::vector<MetaByte*> newDecoded;
    newDecoded.reserve(decodedDict.size());

    newDecoded.push_back(LitByte::getInstance(0));
    newDecoded.push_back(LitByte::getInstance(0));
    newDecoded.push_back(CRAMSub::getInstance(0));
    newDecoded.push_back(CRAMSub::getInstance(0));

    for (size_t i = 0; i < decodedDict.size(); i++) {
        bool matched = false;
        for (size_t j = 0; j < reuse_chrs.size(); j++) {
            if (decodedDict[i] == reuse_chrs[j]) {
                newDecoded.push_back(newDecoded[newDecoded.size() - (j+1)]);
                matched = true;
                break;
            }
        }
        if (!matched) {
            newDecoded.push_back(decodedDict[i]);
        }
    }
    decodedDict = std::move(newDecoded);
    size_t pos = 0;
    int subVal = 0;
    for (size_t i = 0; i < lengths.size(); i++) {
        int length = lengths[i];
        std::vector<MetaByte*> seq;
        seq.reserve(length);
        for (int j = 0; j < length; j++) {
            if (pos >= decodedDict.size()) break; 
            seq.push_back(decodedDict[pos]);
            pos++;
        }
        out.seqLengths[subVal] = static_cast<int>(seq.size());
        for (int j = 0; j < static_cast<int>(seq.size()); j++) {
            int revIndex = seq.size() - 1 - j;
            out.expansions[subVal][j] = seq[revIndex];
        }
        subVal++;
        if (subVal > CRAMSub::getMaxVal()) break;
    }
    return std::make_pair(out, totalCycles);
}

std::pair<std::vector<std::vector<MetaByte*>>, std::vector<int>> cramDecodeAllChunks(
    const std::vector<std::string>& compressedChunks,
    const DictBits &dictBits,
    size_t chunkSize)
{
    auto parseOut = parseDictBits(dictBits);
    CRAMDictionary dictData = parseOut.first;
    int dict_cycles = parseOut.second;

    std::vector<std::vector<MetaByte*>> result;
    std::vector<int> cycles_per_chunk;
    cycles_per_chunk.push_back(dict_cycles);

    result.reserve(compressedChunks.size());
    for (size_t i = 0; i < compressedChunks.size(); i++) {
        auto decodeResult = cramDecodeSingleChunk(compressedChunks[i]);
        std::vector<MetaByte*> partial = decodeResult.first;
        int huff_cycles = decodeResult.second;
        std::vector<MetaByte*> reuse_chrs = { 
            CRAMSub::getInstance(63), CRAMSub::getInstance(64), 
            CRAMSub::getInstance(65), CRAMSub::getInstance(66),
            CRAMSub::getInstance(67), CRAMSub::getInstance(68),
            CRAMSub::getInstance(69), CRAMSub::getInstance(70)
        };
        std::vector<MetaByte*> new_decoded;
        for (size_t j = 0; j < partial.size(); j++) {
            bool reuse = false;
            for (size_t k = 0; k < reuse_chrs.size(); k++) {
                if (partial[j] == reuse_chrs[k] && new_decoded.size() >= (k+1)) {
                    new_decoded.push_back(new_decoded[new_decoded.size() - (k+1)]);
                    reuse = true;
                    break;
                } 
            }
            if (!reuse) {
                new_decoded.push_back(partial[j]);
            }
        }
        partial = new_decoded;
        std::vector<std::vector<MetaByte*>> pieces;
        size_t total_size = partial.size();
        size_t base_size = total_size / DECOMPRESSOR_LIFOS;
        size_t remainder = total_size % DECOMPRESSOR_LIFOS;
        size_t start = 0;
        for (int j = 0; j < DECOMPRESSOR_LIFOS; ++j) {
            size_t section_size = base_size + (j < static_cast<int>(remainder) ? 1 : 0);
            std::vector<MetaByte*> sub_vec(partial.begin() + start, partial.begin() + start + section_size);
            pieces.push_back(sub_vec);
            start += section_size;
        }
        std::vector<MetaByte*> expanded;
        size_t cycles = 0;
        for (size_t j = 0; j < pieces.size(); j++) {
            auto expandResult = expandCRAMSubsCycle(pieces[j], dictData.expansions, dictData.seqLengths);
            std::vector<MetaByte*> expanded_piece = expandResult.first;
            size_t cycleCount = expandResult.second;
            cycles = std::max(cycles, cycleCount);
            expanded.insert(expanded.end(), expanded_piece.begin(), expanded_piece.end());
        }
        result.push_back(expanded);
        cycles_per_chunk.push_back(huff_cycles + static_cast<int>(cycles));
    }
    return std::make_pair(result, cycles_per_chunk);
}

//---------------------------------------------------------------------
// Update compressAllStages and decompressAllStages to use DictBits
std::pair<std::vector<std::string>, DictBits>
compressAllStages(const std::vector<uint8_t>& page,
                  int memoryBlocks,
                  size_t chunkSize)
{
    std::vector<std::vector<uint8_t>> chunkedBytes = chunkInput(page, chunkSize);
    auto padFunc = [](const std::vector<uint8_t> &chunk) -> std::vector<MetaByte*> {
        return padInput(chunk);
    };
    std::vector<std::vector<MetaByte*>> metaChunks = applyChunkwise<uint8_t, MetaByte*>(padFunc, chunkedBytes);
    auto compResult = cramEncode9b(metaChunks, memoryBlocks);
    return compResult;
}

std::pair<std::vector<uint8_t>, std::vector<int>> decompressAllStages(const std::vector<std::string> &compressedChunks,
                    const DictBits &dictBits,
                    size_t chunkSize)
{
    auto decodeResult = cramDecodeAllChunks(compressedChunks, dictBits, chunkSize);
    std::vector<std::vector<MetaByte*>> allMetaChunks = decodeResult.first;
    std::vector<int> cycle_info = decodeResult.second;
    auto unpadFunc = [](const std::vector<MetaByte*> &chunk) -> std::vector<uint8_t> {
        return unpadOutput(chunk);
    };
    std::vector<std::vector<uint8_t>> unpaddedChunks = applyChunkwise<MetaByte*, uint8_t>(unpadFunc, allMetaChunks);
    std::vector<uint8_t> decompressedPage = unchunkOutput(unpaddedChunks);
    return std::make_pair(decompressedPage, cycle_info);
}

std::pair<std::vector<uint8_t>, std::vector<int>> decompressOneChunkAllStages(const std::string &compressedChunk,
                    const DictBits &dictBits,
                    size_t chunkSize)
{
    std::vector<std::string> vec;
    vec.push_back(compressedChunk);
    return decompressAllStages(vec, dictBits, chunkSize);
}

bool sequenceMatches(const std::vector<MetaByte*>& chunk,
                     size_t start,
                     const std::vector<MetaByte*>& seq)
{
    if (start + seq.size() > chunk.size()) {
        return false;
    }
    for (size_t i = 0; i < seq.size(); i++) {
        if (chunk[start + i]->numEncoding() != seq[seq.size() - 1 - i]->numEncoding()) {
            return false;
        }
    }
    return true;
}

std::string write_and_recompress(
    const std::string &metabyte_chunk,
    const std::vector<uint8_t> &new_block,
    size_t block_idx,
    const DictBits &dict_bits,
    size_t chunk_size)
{
    // Decompress the given chunk using the provided dictionary bits.
    std::vector<std::string> singleChunk = { metabyte_chunk };
    auto decompResult = decompressAllStages(singleChunk, dict_bits, chunk_size);
    std::vector<uint8_t> old_chunk = decompResult.first;

    if (old_chunk.size() % 64 != 0) {
        throw std::runtime_error("old_chunk size not multiple of 64!");
    }
    size_t numBlocks = old_chunk.size() / 64;
    if (block_idx >= numBlocks) {
        throw std::runtime_error("block_idx out of range");
    }
    // Overwrite the specified block.
    for (size_t i = 0; i < 64; i++) {
        old_chunk[block_idx * 64 + i] = new_block[i];
    }
    const std::vector<uint8_t> &written_chunk = old_chunk;
    std::vector<MetaByte*> chunk = padInput(written_chunk);

    // Parse the dictionary bits.
    auto parseOut = parseDictBits(dict_bits);
    CRAMDictionary dictData = parseOut.first;

    // The first 6 bits encode the number of dictionary entries (only those beyond the first two).
    std::string dictStr = dictBitsToString(dict_bits);
    int count = 0;
    if (dictStr.size() >= 6) {
        count = std::stoi(dictStr.substr(0, 6), nullptr, 2);
    }

    // Apply dictionary substitution.
    // Since your compressor never records subVal 0 and 1,
    // we add an offset of 2 so that the first dictionary entry becomes CRAMSub::getInstance(2), etc.
    for (int i = 0; i < count; i++) {
        int subVal = i; // offset adjustment
        const std::vector<MetaByte*> &seq = dictData.expansions[i];
        int seqLen = dictData.seqLengths[i];
        if (seqLen <= 0) {
            continue;
        }
        std::vector<MetaByte*> actualSeq(seq.begin(), seq.begin() + seqLen);
        std::vector<MetaByte*> newChunk;
        newChunk.reserve(chunk.size());
        for (size_t j = 0; j < chunk.size();) {
            if (sequenceMatches(chunk, j, actualSeq)) {
                newChunk.push_back(CRAMSub::getInstance(subVal));
                j += seqLen;
            } else {
                newChunk.push_back(chunk[j]);
                j++;
            }
        }
        chunk = std::move(newChunk);
    }

    std::vector<MetaByte*> reuse_chrs = { 
        CRAMSub::getInstance(63), CRAMSub::getInstance(64), 
        CRAMSub::getInstance(65), CRAMSub::getInstance(66),
        CRAMSub::getInstance(67), CRAMSub::getInstance(68),
        CRAMSub::getInstance(69), CRAMSub::getInstance(70)
    };
    std::vector<MetaByte*> optimizedChunk;
    optimizedChunk.reserve(chunk.size());
    for (size_t j = 0; j < chunk.size(); j++) {
        int best_saving = 0;
        int reuse_idx = -1;
        // Look back using each reuse candidate.
        for (int k = 0; k < static_cast<int>(reuse_chrs.size()); k++) {
            int reuse_dist = k + 1;
            if (j >= static_cast<size_t>(reuse_dist)) {
                int potential_saving = static_cast<int>(chunk[j]->chunkBinaryRep().size()) - 
                                       static_cast<int>(reuse_chrs[k]->chunkBinaryRep().size());
                if (chunk[j] == chunk[j - reuse_dist] && potential_saving > best_saving) {
                    best_saving = potential_saving;
                    reuse_idx = k;
                }
            }
        }
        if (best_saving > 0 && reuse_idx >= 0) {
            optimizedChunk.push_back(reuse_chrs[reuse_idx]);
        } else {
            optimizedChunk.push_back(chunk[j]);
        }
    }
    chunk = std::move(optimizedChunk);

    // Build final binary representation.
    std::string binary_chunk;
    for (size_t i = 0; i < chunk.size(); i++) {
        binary_chunk += chunk[i]->chunkBinaryRep();
    }
    return binary_chunk;
}

std::vector<std::string> fastCompress(const std::vector<uint8_t>& page,
                         size_t chunkSize,
                         const DictBits &dict_bits)
{
    // Split the page into chunks of the specified chunkSize.
    std::vector<std::vector<uint8_t>> chunkedBytes = chunkInput(page, chunkSize);
    
    // Parse the provided dictionary bits.
    auto parseOut = parseDictBits(dict_bits);
    CRAMDictionary dictData = parseOut.first;
    std::string dictStr = dictBitsToString(dict_bits);
    int count = 0;
    if (dictStr.size() >= 6) {
        count = std::stoi(dictStr.substr(0, 6), nullptr, 2);
    }
    
    // Prepare the reuse characters.
    std::vector<MetaByte*> reuse_chrs = { 
        CRAMSub::getInstance(63), CRAMSub::getInstance(64), 
        CRAMSub::getInstance(65), CRAMSub::getInstance(66),
        CRAMSub::getInstance(67), CRAMSub::getInstance(68),
        CRAMSub::getInstance(69), CRAMSub::getInstance(70)
    };
    std::vector<std::string> chunks;
    // Process each chunk.
    for (const auto &chunkBytes : chunkedBytes) {
        // Convert raw bytes to MetaByte pointers.
        std::vector<MetaByte*> metaChunk = padInput(chunkBytes);
        
        // Apply dictionary substitution for each dictionary entry.
        // For each dictionary entry, scan the chunk for matching sequences and replace them.
        for (int subVal = 0; subVal < count; subVal++) {
            const std::vector<MetaByte*>& seq = dictData.expansions[subVal];
            int seqLen = dictData.seqLengths[subVal];
            if (seqLen <= 0)
                continue;
            std::vector<MetaByte*> actualSeq(seq.begin(), seq.begin() + seqLen);
            std::vector<MetaByte*> newChunk;
            newChunk.reserve(metaChunk.size());
            for (size_t i = 0; i < metaChunk.size();) {
                if (sequenceMatches(metaChunk, i, actualSeq)) {
                    newChunk.push_back(CRAMSub::getInstance(subVal));
                    i += seqLen;
                } else {
                    newChunk.push_back(metaChunk[i]);
                    i++;
                }
            }
            metaChunk = std::move(newChunk);
        }
        
        // Apply reuse optimization. For each MetaByte, check previous positions using the eight reuse codes.
        std::vector<MetaByte*> optimizedChunk;
        optimizedChunk.reserve(metaChunk.size());
        for (size_t j = 0; j < metaChunk.size(); j++) {
            int best_saving = 0;
            int reuse_idx = -1;
            for (int k = 0; k < static_cast<int>(reuse_chrs.size()); k++) {
                int reuse_dist = k + 1;
                if (j >= static_cast<size_t>(reuse_dist)) {
                    int potential_saving = static_cast<int>(metaChunk[j]->chunkBinaryRep().size()) -
                                           static_cast<int>(reuse_chrs[k]->chunkBinaryRep().size());
                    if (metaChunk[j] == metaChunk[j - reuse_dist] && potential_saving > best_saving) {
                        best_saving = potential_saving;
                        reuse_idx = k;
                    }
                }
            }
            if (best_saving > 0 && reuse_idx >= 0)
                optimizedChunk.push_back(reuse_chrs[reuse_idx]);
            else
                optimizedChunk.push_back(metaChunk[j]);
        }
        metaChunk = std::move(optimizedChunk);
        
        // Build the binary string for this compressed chunk.
        std::string chunkBinary;
        for (MetaByte* mb : metaChunk)
            chunkBinary += mb->chunkBinaryRep();
        
        // Concatenate the chunk to the overall compressed page.
        chunks.push_back(chunkBinary);
    }
    
    return chunks;
}

CompressMetrics measureCompress(const std::vector<std::string>& compressedChunks,
                                  const DictBits &dictBits)
{
    CompressMetrics cm;
    cm.dictSizeBits = dictBits.length; // now in bits
    for (size_t i = 0; i < compressedChunks.size(); i++) {
        cm.chunkSizes.push_back(compressedChunks[i].size());
    }
    return cm;
}

PageResult processPage(const std::vector<uint8_t>& page,
                       int memBlocks,
                       size_t chunkSize)
{
    auto compRes = compressAllStages(page, memBlocks, chunkSize);
    std::vector<std::string> compressedChunks = compRes.first;
    DictBits dictBits = compRes.second;
    CompressMetrics cm = measureCompress(compressedChunks, dictBits);
    std::string line = std::to_string(cm.dictSizeBits);
    for (size_t i = 0; i < compressedChunks.size(); i++) {
        size_t csize = 0;
        if (i < cm.chunkSizes.size()) {
            csize = cm.chunkSizes[i];
        }
        line += " " + std::to_string(csize);
    }
    auto decompResult = decompressAllStages(compressedChunks, dictBits, chunkSize);
    std::vector<uint8_t> restored = decompResult.first;
    std::vector<int> cycle_timing = decompResult.second;
    bool match = (restored.size() == page.size());
    if (match) {
        for (size_t i = 0; i < page.size(); i++) {
            if (restored[i] != page[i]) {
                match = false;
                break;
            }
        }
    }
    PageResult result;
    result.timing = cycle_timing;
    result.line = line;
    result.matched = match;
    return result;
}
