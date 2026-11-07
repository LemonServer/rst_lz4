#include <algorithm>
#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <string>
#include <thread>
#include <vector>

namespace fs = std::filesystem;

static constexpr size_t PAGE_SIZE = 4096;

struct Token {
    bool is_dict;
    uint16_t val; // literal byte or dict index
};

struct PageResult {
    uint64_t total_bits{0};
    uint64_t dict_bits{0};
    uint32_t max_entry_len{0};
    double   utilization{0.0};
};

enum class UtilMode : int { SelectFirst = 0, Savings = 1, Utility = 2 };

static inline const char* util_label(UtilMode m) {
    switch (m) {
        case UtilMode::SelectFirst: return "select-first";
        case UtilMode::Savings:     return "savings";
        case UtilMode::Utility:     return "utility";
    }
    return "unknown";
}


// --- Add these includes if not already present ---
#include <cstdint>
#include <vector>
#include <unordered_map>
#include <algorithm>

// Dictionary “subsequence compression” estimator.
// Replaces any occurrence of an earlier full entry inside a later entry with a single ref token.
// Costs are parametric; default assumes 8-bit literals and a 9-bit reference token (one symbol).
struct DictSubseqCost {
    int literal_bits = 9;   // cost to emit one raw byte/symbol
    int ref_bits     = 9;   // cost to emit one reference token (e.g., index 256 + j)
    int min_ref_len  = 2;   // minimum entry length worth referencing
};

static inline bool has_prefix_at(const std::vector<uint8_t>& hay,
                                 size_t pos,
                                 const std::vector<uint8_t>& needle)
{
    const size_t n = needle.size();
    if (pos + n > hay.size()) return false;
    // Fast path: compare bytes
    for (size_t i = 0; i < n; ++i)
        if (hay[pos + i] != needle[i]) return false;
    return true;
}

// Choose the *longest* prior entry that matches at hay[pos].
static inline int choose_longest_match(const std::vector<uint8_t>& hay,
                                       size_t pos,
                                       const std::vector<std::vector<uint8_t>>& entries,
                                       const std::vector<int>& candidates /* indices of prior entries */)
{
    int best_idx = -1;
    size_t best_len = 0;
    for (int j : candidates) {
        const auto& pat = entries[j];
        const size_t L = pat.size();
        if (L > best_len && has_prefix_at(hay, pos, pat)) {
            best_len = L;
            best_idx = j;
        }
    }
    return best_idx;
}

// Build a simple index: first byte -> list of prior entry indices starting with that byte.
static inline std::unordered_map<uint8_t, std::vector<int>>
build_firstbyte_index(const std::vector<std::vector<uint8_t>>& dict_entries)
{
    std::unordered_map<uint8_t, std::vector<int>> idx;
    idx.reserve(dict_entries.size() * 2);
    for (int i = 0; i < (int)dict_entries.size(); ++i) {
        if (!dict_entries[i].empty()) {
            idx[dict_entries[i][0]].push_back(i);
        }
    }
    return idx;
}

// Estimate dictionary size (bytes) when entries can reference earlier entries as single tokens.
// Mirrors your Python "compressdict": only full-entry subsequences are replaced.
static uint64_t estimate_dict_subseq_bytes(const std::vector<std::vector<uint8_t>>& dict_entries,
                                           DictSubseqCost cost = {})
{
    if (dict_entries.empty()) return 0;

    // Pre-index by first byte for quick candidate narrowing.
    auto first_idx = build_firstbyte_index(dict_entries);

    uint64_t total_bits = 0;

    for (int i = 0; i < (int)dict_entries.size(); ++i) {
        const auto& entry = dict_entries[i];
        if (entry.empty()) continue;

        size_t pos = 0;
        while (pos < entry.size()) {
            const uint8_t b0 = entry[pos];

            // Gather only prior entries that start with this byte and meet min length.
            std::vector<int> candidates;
            if (auto it = first_idx.find(b0); it != first_idx.end()) {
                candidates.reserve(it->second.size());
                for (int j : it->second) {
                    if (j >= i) break; // only earlier entries
                    if (dict_entries[j].size() >= (size_t)cost.min_ref_len)
                        candidates.push_back(j);
                }
            }

            int best = -1;
            if (!candidates.empty()) {
                best = choose_longest_match(entry, pos, dict_entries, candidates);
            }

            if (best >= 0) {
                const size_t L = dict_entries[best].size();
                // Only take the reference if it *actually* saves bits.
                const uint64_t raw_bits = (uint64_t)L * (uint64_t)cost.literal_bits;
                if (raw_bits > (uint64_t)cost.ref_bits) {
                    total_bits += (uint64_t)cost.ref_bits;
                    pos += L;
                    continue;
                }
                // Fall through to literal if no bit-savings.
            }

            // Emit as literal.
            total_bits += (uint64_t)cost.literal_bits;
            ++pos;
        }
    }

    // Round up to whole bytes.
    return (total_bits + 7u) >> 3;
}


// ------------------------------------------------------------
// File -> pages (4096B chunks; last chunk may be <4096 if EOF)
// ------------------------------------------------------------
static std::vector<std::vector<uint8_t>> read_file_in_chunks(const fs::path& p) {
    std::vector<std::vector<uint8_t>> pages;
    std::ifstream ifs(p, std::ios::binary);
    if (!ifs) return pages;

    std::vector<uint8_t> buf(PAGE_SIZE);
    while (true) {
        ifs.read(reinterpret_cast<char*>(buf.data()), PAGE_SIZE);
        std::streamsize got = ifs.gcount();
        if (got <= 0) break;
        pages.emplace_back(buf.begin(), buf.begin() + got);
        if (ifs.eof()) break;
    }
    return pages;
}

// ------------------------------------------------------------
// Greedy LZ-like candidate mining (window = all prior bytes, non-overlapping)
// Returns sequences in first-found order. No duplicates. Entry length <= dict_budget.
// ------------------------------------------------------------
static std::vector<std::vector<uint8_t>>
greedy_lz_candidates(const std::vector<uint8_t>& page, int dict_budget) {
    const int N = static_cast<int>(page.size());
    const int max_cap = std::max(2, dict_budget);

    std::vector<int> hist[256]; // per starting byte, positions seen
    std::vector<std::vector<uint8_t>> candidates;

    auto seq_exists = [&](const std::vector<uint8_t>& s)->bool{
        for (auto& c : candidates) {
            if (c.size() == s.size() && std::equal(c.begin(), c.end(), s.begin())) return true;
        }
        return false;
    };

    int i = 0;
    while (i < N) {
        uint8_t b0 = page[i];
        int best_len = 0;
        int best_pos = -1;

        auto& lst = hist[b0];
        for (int k = static_cast<int>(lst.size()) - 1; k >= 0; --k) {
            int pos = lst[k];
            int limit = std::min({N - i, N - pos, max_cap});
            if (limit <= best_len) continue;
            int l = 0;
            while (l < limit && page[pos + l] == page[i + l]) ++l;
            if (l > best_len) {
                best_len = l;
                best_pos = pos;
            }
        }

        if (best_len >= 2) {
            std::vector<uint8_t> seq(page.begin() + i, page.begin() + i + best_len);
            if (!seq_exists(seq)) candidates.emplace_back(std::move(seq));
            // consume matched region
            for (int k = 0; k < best_len; ++k) {
                hist[page[i + k]].push_back(i + k);
            }
            i += best_len;
        } else {
            hist[b0].push_back(i);
            ++i;
        }
    }
    return candidates;
}

// ------------------------------------------------------------
// Recount true non-self-overlapping occurrences for all candidates.
// Per-sequence non-overlap only. One pass over page.
// Returns vector<int> counts aligned with 'sequences' order.
// ------------------------------------------------------------
static std::vector<int>
recount_true_nonoverlap_counts(const std::vector<uint8_t>& page,
                               const std::vector<std::vector<uint8_t>>& sequences) {
    const int N = static_cast<int>(page.size());
    std::vector<std::vector<int>> by_first(256);
    for (int si = 0; si < (int)sequences.size(); ++si) {
        if (sequences[si].size() >= 2) {
            by_first[sequences[si][0]].push_back(si);
        }
    }

    std::vector<int> next_ok(sequences.size(), 0);
    std::vector<int> counts(sequences.size(), 0);

    for (int i = 0; i < N; ++i) {
        auto& idxs = by_first[page[i]];
        if (idxs.empty()) continue;
        for (int si : idxs) {
            const auto& seq = sequences[si];
            int L = (int)seq.size();
            if (L == 0) continue;
            if (i < next_ok[si]) continue;
            if (i + L <= N && std::memcmp(&page[i], seq.data(), L) == 0) {
                counts[si] += 1;
                next_ok[si] = i + L; // per-seq non-overlap
            }
        }
    }
    return counts;
}

// ------------------------------------------------------------
// Dictionary selection under budget (sum lengths <= dictsize), ≤ 256 entries.
// Sorting semantics preserved exactly by util_mode:
//    - SelectFirst: discovery order (stable)
//    - Savings:     descending (n_true-1)*(L-1), tie→earlier discovery
//    - Utility:     descending savings/L, tie→earlier discovery
// After that, we pack without truncation, then run a **backfill pass**
// on remaining items (shortest-first) to fill any budget slack.
// ------------------------------------------------------------
static std::vector<std::vector<uint8_t>>
select_dictionary(const std::vector<std::vector<uint8_t>>& first_found,
                  const std::vector<int>& true_counts,
                  int dictsize,
                  UtilMode util_mode,
                  double* out_utilization /*optional*/) {
    struct Item {
        int seq_idx;
        int L;
        int n;
        double score;
        int first_idx;
    };
    std::vector<Item> items;
    items.reserve(first_found.size());
    for (int idx = 0; idx < (int)first_found.size(); ++idx) {
        int L = (int)first_found[idx].size();
        int n = (idx < (int)true_counts.size()) ? true_counts[idx] : 0;
        int s = std::max(0, (n - 1) * (L - 1));
        double score = 0.0;
        switch (util_mode) {
            case UtilMode::SelectFirst: score = 1e300; break; // stable-sort will keep first_idx order
            case UtilMode::Savings:     score = (double)s; break;
            case UtilMode::Utility:     score = (L > 0) ? (double(s) / double(L)) : 0.0; break;
        }
        items.push_back({idx, L, n, score, idx});
    }

    // Preserve original sorting semantics
    if (util_mode == UtilMode::SelectFirst) {
        std::stable_sort(items.begin(), items.end(),
                         [](const Item& a, const Item& b){ return a.first_idx < b.first_idx; });
    } else {
        std::stable_sort(items.begin(), items.end(),
                         [](const Item& a, const Item& b){
                             if (a.score != b.score) return a.score > b.score; // desc score
                             return a.first_idx < b.first_idx;                  // earlier discovery wins ties
                         });
    }

    // Primary pack pass (no truncation)
    std::vector<std::vector<uint8_t>> chosen;
    chosen.reserve(std::min((size_t)256, items.size()));
    int used_bytes = 0;
    std::vector<char> taken(items.size(), 0);

    for (size_t k = 0; k < items.size(); ++k) {
        const auto& it = items[k];
        if (it.L < 2) continue;
        if (it.L > dictsize) continue;          // do NOT truncate
        if ((int)chosen.size() >= 256) break;
        if (used_bytes + it.L + 1 <= dictsize) { // Edit length + 1
            chosen.push_back(first_found[it.seq_idx]);
            used_bytes += it.L + 1; // Edit length + 1
            taken[k] = 1;
        }
    }

    // Backfill (length-ascending among not-taken)
    if (used_bytes < dictsize && (int)chosen.size() < 256) {
        struct Rem { int k; int L; };
        std::vector<Rem> rem;
        rem.reserve(items.size());
        for (size_t k = 0; k < items.size(); ++k) {
            if (taken[k]) continue;
            if (items[k].L >= 2 && items[k].L <= dictsize) rem.push_back({(int)k, items[k].L});
        }
        std::stable_sort(rem.begin(), rem.end(),
                         [](const Rem& a, const Rem& b){
                             if (a.L != b.L) return a.L < b.L;  // shortest first
                             return a.k < b.k;
                         });

        for (const auto& r : rem) {
            if ((int)chosen.size() >= 256) break;
            const auto& it = items[r.k];
            if (used_bytes + it.L + 1 <= dictsize) { // Edit length + 1
                chosen.push_back(first_found[it.seq_idx]);
                used_bytes += it.L + 1; // Edit length + 1
            }
            if (used_bytes == dictsize) break;
        }
    }

    if (out_utilization) {
        *out_utilization = (dictsize > 0) ? (double)used_bytes / (double)dictsize : 0.0;
    }
    return chosen;
}

// ------------------------------------------------------------
// Strictly-greedy "longest match" parse with fixed dictionary.
// At each position i: choose the longest matching entry; tie → lowest dict index.
// Else emit a literal. Advance by chosen length or 1.
// Returns tokens and per-entry usage counts.
// ------------------------------------------------------------
static std::pair<std::vector<Token>, std::vector<int>>
greedy_longest_parse(const std::vector<uint8_t>& page,
                     const std::vector<std::vector<uint8_t>>& dict_entries) {
    const int N = (int)page.size();

    // Index dict by first byte for quick candidate retrieval
    std::vector<std::vector<int>> by_first(256);
    for (int di = 0; di < (int)dict_entries.size(); ++di) {
        if (dict_entries[di].size() >= 2) {
            by_first[dict_entries[di][0]].push_back(di);
        }
    }

    std::vector<Token> tokens;
    tokens.reserve(N);
    std::vector<int> use_counts(dict_entries.size(), 0);

    int i = 0;
    while (i < N) {
        const auto& list = by_first[page[i]];
        int best_di = -1;
        int best_L  = 0;

        for (int di : list) {
            const auto& seq = dict_entries[di];
            int L = (int)seq.size();
            if (i + L <= N && std::memcmp(&page[i], seq.data(), L) == 0) {
                if (L > best_L || (L == best_L && (best_di < 0 || di < best_di))) {
                    best_L = L;
                    best_di = di;
                }
            }
        }

        if (best_di >= 0) {
            tokens.push_back({true, static_cast<uint16_t>(best_di)});
            use_counts[best_di] += 1;
            i += best_L;
        } else {
            tokens.push_back({false, page[i]});
            ++i;
        }
    }

    return {std::move(tokens), std::move(use_counts)};
}

// ------------------------------------------------------------
// Decompress tokens with dictionary (unchanged)
// ------------------------------------------------------------
static std::vector<uint8_t>
decompress(const std::vector<Token>& tokens,
           const std::vector<std::vector<uint8_t>>& dict_entries) {
    std::vector<uint8_t> out;
    out.reserve(tokens.size());
    for (const auto& t : tokens) {
        if (!t.is_dict) out.push_back((uint8_t)t.val);
        else {
            const auto& seq = dict_entries[t.val];
            out.insert(out.end(), seq.begin(), seq.end());
        }
    }
    return out;
}

// ------------------------------------------------------------
// Greedy LZ77 compress-size estimate for flattened dictionary (unchanged)
// ------------------------------------------------------------
static uint64_t lz77_estimated_bytes(const std::vector<uint8_t>& data) {
    const int N = (int)data.size();
    if (N <= 1) return (uint64_t)N;

    struct Tok { bool is_match; int len; int dist; uint8_t lit; };
    std::vector<Tok> toks;
    toks.reserve(N);

    const int MIN_MATCH = 3;
    const int MAX_LEN = 255;
    const int MAX_DIST = 65535;

    int i = 0;
    while (i < N) {
        int bestL = 0, bestD = 0;
        int jmin = std::max(0, i - MAX_DIST);
        for (int j = jmin; j < i; ++j) {
            int l = 0;
            while (l < MAX_LEN && i + l < N && data[j + l] == data[i + l]) ++l;
            if (l > bestL) {
                bestL = l;
                bestD = i - j;
                if (bestL == MAX_LEN) break;
            }
        }
        if (bestL >= MIN_MATCH) {
            toks.push_back({true, bestL, bestD, 0});
            i += bestL;
        } else {
            toks.push_back({false, 0, 0, data[i]});
            ++i;
        }
    }

    uint64_t flags_bits = toks.size();
    uint64_t flags_bytes = (flags_bits + 7) / 8;
    uint64_t payload = 0;
    for (const auto& t : toks) {
        if (!t.is_match) {
            payload += 1; // literal byte
        } else {
            payload += 1; // len
            payload += (t.dist <= 255) ? 1 : 2; // dist
        }
    }
    uint64_t est_bytes = flags_bytes + payload;
    uint64_t raw_bytes = (uint64_t)N;
    return std::min(raw_bytes, est_bytes);
}

// ------------------------------------------------------------
// Full page pipeline
// ------------------------------------------------------------
static PageResult
process_page(const std::vector<uint8_t>& page, int dictsize, UtilMode util_mode, bool compress_dict) {
    // 1) mine candidates (first-found order)
    auto candidates = greedy_lz_candidates(page, dictsize);

    // 2) recount non-overlap counts (used for Savings/Utility scores)
    auto true_counts = recount_true_nonoverlap_counts(page, candidates);

    // 3) select dictionary (util_mode sorting preserved; add backfill)
    double util_prefinal = 0.0;
    auto dict_entries = select_dictionary(candidates, true_counts, dictsize - 8, util_mode, &util_prefinal);

    // 4) strictly-greedy parse
    auto [tokens, use_counts] = greedy_longest_parse(page, dict_entries);

    // 5) prune entries used <= 1 and re-parse (still greedy)
    bool any_pruned = false;
    std::vector<std::vector<uint8_t>> pruned;
    pruned.reserve(dict_entries.size());
    for (size_t i = 0; i < dict_entries.size(); ++i) {
        if (use_counts[i] > 1) pruned.push_back(dict_entries[i]);
        else any_pruned = true;
    }
    if (any_pruned) {
        dict_entries.swap(pruned);
        std::tie(tokens, std::ignore) = greedy_longest_parse(page, dict_entries);
    }

    // 6) verify
    {
        auto recon = decompress(tokens, dict_entries);
        if (recon != page) {
            std::cerr << "Decompression mismatch on a page\n";
            std::abort();
        }
    }

    // 7) metrics (post-prune)
    uint64_t dict_bytes = 0;
    uint32_t max_entry_len = 0;
    for (const auto& e : dict_entries) {
        dict_bytes += e.size() + 1;
        if (e.size() > max_entry_len) max_entry_len = (uint32_t)e.size();
    }

    // Dictionary size: raw vs compressed-by-LZ77(flattened)
    //uint64_t dict_size_bytes = dict_bytes;
    //if (compress_dict && dict_bytes > 0) {
    //    std::vector<uint8_t> flat;
    //    flat.reserve((size_t)dict_bytes);
    //    for (const auto& e : dict_entries) flat.insert(flat.end(), e.begin(), e.end());
    //    dict_size_bytes = lz77_estimated_bytes(flat);
    //}

    uint64_t dict_size_bytes = dict_bytes;
    if (compress_dict && dict_bytes > 0) {
        // Tune costs to your stream. If your dictionary section uses 9-bit alphabet, set literal_bits = 9.
        DictSubseqCost cost;
        cost.literal_bits = 9;   // or 9 if your dict alphabet is 9-bit
        cost.ref_bits     = 9;   // single reference token (e.g., 256+index) – mirrors your Python
        cost.min_ref_len  = 2;

        dict_size_bytes = estimate_dict_subseq_bytes(dict_entries, cost);
    }

    uint64_t token_count = tokens.size();
    uint64_t dict_bits = dict_size_bytes * 9;
    uint64_t total_bits = (dict_size_bytes + token_count) * 9;
    double utilization = (dictsize > 0) ? double(dict_bytes) / double(dictsize) : 0.0;

    uint64_t log_blocks = ceil(token_count * 9 / 8 / 63.25);
    uint64_t oh_bits = log_blocks * 6;
    total_bits = total_bits + oh_bits;

    if (total_bits > 4096 * 8) total_bits = 4096 * 8;

    return PageResult{ total_bits, dict_bits, max_entry_len, utilization };
}

// ------------------------------------------------------------
// Parallel page runner
// ------------------------------------------------------------
static std::vector<PageResult>
process_pages_parallel(const std::vector<std::vector<uint8_t>>& pages,
                       int dictsize, UtilMode util_mode, bool compress_dict) {
    const size_t N = pages.size();
    std::vector<PageResult> results(N);

    unsigned hw = std::thread::hardware_concurrency();
    if (hw == 0) hw = 2;
    unsigned nthreads = (hw > 1) ? (hw - 1) : 1;

    std::atomic<size_t> idx{0};
    std::vector<std::thread> threads;
    threads.reserve(nthreads);

    for (unsigned t = 0; t < nthreads; ++t) {
        threads.emplace_back([&](){
            size_t i;
            while ((i = idx.fetch_add(1)) < N) {
                results[i] = process_page(pages[i], dictsize, util_mode, compress_dict);
            }
        });
    }
    for (auto& th : threads) th.join();
    return results;
}

// ------------------------------------------------------------
// CSV helpers
// ------------------------------------------------------------
static void initialize_output_csv(const fs::path& outcsv) {
    std::ofstream ofs(outcsv, std::ios::trunc);
    ofs << "config_label,"
           "dict_charsize_bits,"
           "dict_size_entries,"
           "util_mode,"
           "compress_dict,"
           "file,"
           "pages_count,"
           "total_c_bits,"
           "total_dict_bits,"
           "dict_percent,"
           "avg_longest_entry,"
           "compression_ratio\n";
}

// ------------------------------------------------------------
// Per-file run & aggregate -> CSV row + console summary
// ------------------------------------------------------------
static void run_one_config_on_file(const fs::path& filepath,
                                   const fs::path& outcsv,
                                   int dictsize, UtilMode util_mode, bool compress_dict,
                                   const std::string& label) {
    // read pages
    auto pages = read_file_in_chunks(filepath);

    // run pages in parallel
    auto results = process_pages_parallel(pages, dictsize, util_mode, compress_dict);

    // aggregate
    uint64_t total_c_bits = 0, total_dict_bits = 0;
    double sum_util = 0.0;
    double avg_longest_entry = 0.0;
    for (const auto& r : results) {
        total_c_bits += r.total_bits;
        total_dict_bits += r.dict_bits;
        sum_util += r.utilization;
        avg_longest_entry += r.max_entry_len;
    }
    const size_t pages_count = pages.size();
    if (pages_count > 0) {
        avg_longest_entry /= double(pages_count);
    }
    double dict_percent = (total_c_bits > 0) ? (double)total_dict_bits / double(total_c_bits) * 100.0 : 0.0;
    uint64_t orig_bits = PAGE_SIZE * 8ull * pages_count;
    double compression_ratio = (total_c_bits > 0) ? double(orig_bits) / double(total_c_bits) : 0.0;
    double avg_utilization = (pages_count > 0) ? (sum_util / double(pages_count) * 100.0) : 0.0;

    // CSV row
    std::ofstream ofs(outcsv, std::ios::app);
    ofs << label << ","
        << 9 << ","                      // dict_charsize_bits
        << dictsize << ","               // dict_size_entries (bytes budget)
        << util_label(util_mode) << ","
        << (compress_dict ? 1 : 0) << ","
        << filepath.string() << ","
        << pages_count << ","
        << total_c_bits << ","
        << total_dict_bits << ","
        << dict_percent << ","
        << avg_longest_entry << ","
        << compression_ratio << "\n";

    // Console summary
    std::cout << "[" << label << "] " << filepath << "\n"
              << "  pages=" << pages_count
              << "  dict_bits=" << total_dict_bits
              << "  total_bits=" << total_c_bits
              << "  dict%=" << std::fixed << std::setprecision(2) << dict_percent << "%\n"
              << "  avg_longest_entry=" << std::setprecision(2) << avg_longest_entry
              << "  CR=" << std::setprecision(6) << compression_ratio
              << "  dict_utilization=" << std::setprecision(2) << avg_utilization << "%\n";
}

// ------------------------------------------------------------
// Main
// ------------------------------------------------------------
int main(int argc, char** argv) {
    // Simple CLI parse: -f DIR  -o OUTCSV
    fs::path dir;
    fs::path outcsv;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if ((a == "-f" || a == "--filename") && i + 1 < argc) {
            dir = fs::path(argv[++i]);
        } else if ((a == "-o" || a == "--outfile") && i + 1 < argc) {
            outcsv = fs::path(argv[++i]);
        } else {
            std::cerr << "Usage: " << argv[0] << " -f <DIR> -o <OUTCSV>\n";
            return 1;
        }
    }
    if (dir.empty() || outcsv.empty()) {
        std::cerr << "Usage: " << argv[0] << " -f <DIR> -o <OUTCSV>\n";
        return 1;
    }

    // Gather files (DIR/*), sorted
    std::vector<fs::path> files;
    for (auto& de : fs::directory_iterator(dir)) {
        if (!de.is_regular_file()) continue;
        files.push_back(de.path());
    }
    std::sort(files.begin(), files.end());
    if (files.empty()) {
        std::cerr << "No files found under: " << dir << "\n";
        return 1;
    }

    initialize_output_csv(outcsv);

    const int dictsizes[] = {64, 128, 192, 256};
    const UtilMode util_modes[] = {UtilMode::Utility};

    for (int dsz : dictsizes) {
        for (UtilMode um : util_modes) {
            // Non-compressed dict
            //std::string label0 = "lz-bse:dict=" + std::to_string(dsz) + ":util=" + std::string(util_label(um)) + ":cd=0";
            //for (const auto& f : files) {
            //    run_one_config_on_file(f, outcsv, dsz, um, false, label0);
            //}
            // Compressed dict (LZ on flattened dict)
            std::string label1 = "lz-bse:dict=" + std::to_string(dsz) + ":util=" + std::string(util_label(um)) + ":cd=1";
            for (const auto& f : files) {
                run_one_config_on_file(f, outcsv, dsz, um, true, label1);
            }
        }
    }
    return 0;
}
