// Emit compact per-page CRAM metrics for verification and ratio comparisons.

#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "cram_types.h"
#include "cram_impl.h"

namespace {

struct Options {
    std::string input_file;
    size_t max_pages = 16;
    size_t page_bytes = 4096;
    size_t chunk_size = 256;
    int memory_blocks = 2;
    bool runtime_pad = false;
};

Options parse_args(int argc, char** argv) {
    Options options;
    for (int idx = 1; idx < argc; ++idx) {
        std::string arg = argv[idx];
        auto require_value = [&](const char* flag) -> std::string {
            if (idx + 1 >= argc) {
                throw std::runtime_error(std::string("missing value for ") + flag);
            }
            return argv[++idx];
        };

        if (arg == "--input-file") {
            options.input_file = require_value("--input-file");
        } else if (arg == "--pages") {
            options.max_pages = std::stoul(require_value("--pages"));
        } else if (arg == "--page-bytes") {
            options.page_bytes = std::stoul(require_value("--page-bytes"));
        } else if (arg == "--chunk-size") {
            options.chunk_size = std::stoul(require_value("--chunk-size"));
        } else if (arg == "--memory-blocks") {
            options.memory_blocks = std::stoi(require_value("--memory-blocks"));
        } else if (arg == "--runtime-pad") {
            options.runtime_pad = true;
        } else {
            throw std::runtime_error("unknown argument: " + arg);
        }
    }

    if (options.input_file.empty()) {
        throw std::runtime_error("--input-file is required");
    }
    if (options.page_bytes == 0) {
        throw std::runtime_error("--page-bytes must be > 0");
    }
    return options;
}

struct InputPage {
    std::vector<uint8_t> bytes;
    size_t valid_bytes = 0;
};

uint8_t runtime_pad_byte(size_t page_idx, size_t lane_idx) {
    return static_cast<uint8_t>((page_idx * 73 + lane_idx * 29) & 0xff);
}

std::vector<InputPage> load_pages(
    const std::string& input_file,
    size_t page_bytes,
    size_t max_pages,
    bool runtime_pad
) {
    std::ifstream input(input_file, std::ios::binary);
    if (!input) {
        throw std::runtime_error("failed to open input file: " + input_file);
    }

    std::vector<InputPage> pages;
    while (input.good() && (max_pages == 0 || pages.size() < max_pages)) {
        std::vector<uint8_t> buffer(page_bytes);
        input.read(reinterpret_cast<char*>(buffer.data()), static_cast<std::streamsize>(page_bytes));
        std::streamsize read_count = input.gcount();
        if (read_count <= 0) {
            break;
        }
        const size_t valid_bytes = static_cast<size_t>(read_count);
        if (runtime_pad) {
            for (size_t idx = valid_bytes; idx < page_bytes; ++idx) {
                buffer[idx] = runtime_pad_byte(pages.size(), idx);
            }
        } else {
            buffer.resize(valid_bytes);
        }
        pages.push_back(InputPage{std::move(buffer), valid_bytes});
        if (read_count < static_cast<std::streamsize>(page_bytes)) {
            break;
        }
    }
    return pages;
}

int dict_count_from_bits(const DictBits& dict_bits) {
    int count = 0;
    const int bits_to_read = std::min(dict_bits.length, 6);
    for (int idx = 0; idx < bits_to_read; ++idx) {
        count = (count << 1) | (dict_bits.bits[idx] ? 1 : 0);
    }
    return count;
}

size_t total_encoded_bits(const CompressMetrics& metrics) {
    size_t total = metrics.dictSizeBits;
    for (size_t chunk_bits : metrics.chunkSizes) {
        total += chunk_bits;
    }
    return total;
}

}  // namespace

int main(int argc, char** argv) {
    try {
        Options options = parse_args(argc, argv);
        auto pages = load_pages(
            options.input_file,
            options.page_bytes,
            options.max_pages,
            options.runtime_pad
        );
        if (pages.empty()) {
            throw std::runtime_error("no pages loaded from input file");
        }

        size_t total_input_bytes = 0;
        size_t total_encoded = 0;
        size_t total_dict_bits = 0;

        for (size_t page_idx = 0; page_idx < pages.size(); ++page_idx) {
            const auto& page = pages[page_idx].bytes;
            const size_t valid_bytes = pages[page_idx].valid_bytes;
            auto comp_res = compressAllStages(page, options.memory_blocks, options.chunk_size);
            auto metrics = measureCompress(comp_res.first, comp_res.second);
            size_t encoded_bits = total_encoded_bits(metrics);
            int dict_count = dict_count_from_bits(comp_res.second);
            double ratio = encoded_bits ? (static_cast<double>(valid_bytes) * 8.0) / encoded_bits : 0.0;

            total_input_bytes += valid_bytes;
            total_encoded += encoded_bits;
            total_dict_bits += metrics.dictSizeBits;

            std::cout
                << "[page " << (page_idx + 1) << "/" << pages.size() << "] "
                << "valid_bytes=" << valid_bytes << " "
                << "dict_count=" << dict_count << " "
                << "dict_bits=" << metrics.dictSizeBits << " "
                << "encoded_bits=" << encoded_bits << " "
                << "ratio=" << std::fixed << std::setprecision(4) << ratio
                << "\n";
        }

        double summary_ratio = total_encoded ? (static_cast<double>(total_input_bytes) * 8.0) / total_encoded : 0.0;
        std::cout
            << "[file summary] "
            << "input_bytes=" << total_input_bytes << " "
            << "pages=" << pages.size() << " "
            << "dict_bits=" << total_dict_bits << " "
            << "encoded_bits=" << total_encoded << " "
            << "ratio=" << std::fixed << std::setprecision(4) << summary_ratio
            << "\n";
        return 0;
    } catch (const std::exception& exc) {
        std::cerr << "error: " << exc.what() << "\n";
        return 1;
    }
}
