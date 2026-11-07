#ifndef CRAM_TREE_H
#define CRAM_TREE_H

#include <string>
#include <vector>
#include <array>
#include <memory>
#include <utility>
#include <stdexcept>
#include <cassert>
#include <map>
#include <cstdio>

static const int EXTENDED_CRAMSUB = 72;

// ------------------- Forward Declarations -------------------
class MetaByte;
class LitByte;
class CRAMSub;

// ------------------- Base Class -------------------
class MetaByte
{
public:
    virtual ~MetaByte() = default;
    virtual std::string reprStr() const = 0;
    virtual int numEncoding() const = 0;
    virtual std::string dictBinaryRep() const = 0;
    virtual std::string chunkBinaryRep() const = 0;
    virtual int getDictBinaryLen() const = 0;
};

// ------------------- Static Arrays for Huffman Trees -------------------
// (These arrays are unchanged except for formatting.)
static const std::array<std::string, 256> s_litByteDictCodes = {
    "0000", "011110100", "011110101", "011110110", "011110111", "011111000", "011111001", "011111010",
    "011111011", "011111100", "011111101", "011111110", "011111111", "100000000", "100000001", "100000010",
    "100000011", "100000100", "100000101", "100000110", "100000111", "100001000", "100001001", "100001010",
    "100001011", "100001100", "100001101", "100001110", "100001111", "100010000", "100010001", "100010010",
    "100010011", "100010100", "100010101", "100010110", "100010111", "100011000", "100011001", "100011010",
    "100011011", "100011100", "100011101", "100011110", "100011111", "100100000", "100100001", "100100010",
    "100100011", "100100100", "100100101", "100100110", "100100111", "100101000", "100101001", "100101010",
    "100101011", "100101100", "100101101", "100101110", "100101111", "100110000", "100110001", "100110010",
    "100110011", "100110100", "100110101", "100110110", "100110111", "100111000", "100111001", "100111010",
    "100111011", "100111100", "100111101", "100111110", "100111111", "101000000", "101000001", "101000010",
    "101000011", "101000100", "101000101", "101000110", "101000111", "101001000", "101001001", "101001010",
    "101001011", "101001100", "101001101", "101001110", "101001111", "101010000", "101010001", "101010010",
    "101010011", "101010100", "101010101", "101010110", "101010111", "101011000", "101011001", "101011010",
    "101011011", "101011100", "101011101", "101011110", "101011111", "101100000", "101100001", "101100010",
    "101100011", "101100100", "101100101", "101100110", "101100111", "101101000", "101101001", "101101010",
    "101101011", "101101100", "101101101", "101101110", "101101111", "101110000", "101110001", "101110010",
    "101110011", "101110100", "101110101", "101110110", "101110111", "101111000", "101111001", "101111010",
    "101111011", "101111100", "101111101", "101111110", "101111111", "110000000", "110000001", "110000010",
    "110000011", "110000100", "110000101", "110000110", "110000111", "110001000", "110001001", "110001010",
    "110001011", "110001100", "110001101", "110001110", "110001111", "110010000", "110010001", "110010010",
    "110010011", "110010100", "110010101", "110010110", "110010111", "110011000", "110011001", "110011010",
    "110011011", "110011100", "110011101", "110011110", "110011111", "110100000", "110100001", "110100010",
    "110100011", "110100100", "110100101", "110100110", "110100111", "110101000", "110101001", "110101010",
    "110101011", "110101100", "110101101", "110101110", "110101111", "110110000", "110110001", "110110010",
    "110110011", "110110100", "110110101", "110110110", "110110111", "110111000", "110111001", "110111010",
    "110111011", "110111100", "110111101", "110111110", "110111111", "111000000", "111000001", "111000010",
    "111000011", "111000100", "111000101", "111000110", "111000111", "111001000", "111001001", "111001010",
    "111001011", "111001100", "111001101", "111001110", "111001111", "111010000", "111010001", "111010010",
    "111010011", "111010100", "111010101", "111010110", "111010111", "111011000", "111011001", "111011010",
    "111011011", "111011100", "111011101", "111011110", "111011111", "111100000", "111100001", "111100010",
    "111100011", "111100100", "111100101", "111100110", "111100111", "111101000", "111101001", "111101010",
    "111101011", "111101100", "111101101", "111101110", "111101111", "111110000", "111110001", "111110010"
};

static const std::array<std::string, 256> s_litByteChunkCodes = {
    "000110", "011110110", "011110111", "011111000", "011111001", "011111010", "011111011", "011111100",
    "011111101", "011111110", "011111111", "100000000", "100000001", "100000010", "100000011", "100000100",
    "100000101", "100000110", "100000111", "100001000", "100001001", "100001010", "100001011", "100001100",
    "100001101", "100001110", "100001111", "100010000", "100010001", "100010010", "100010011", "100010100",
    "100010101", "100010110", "100010111", "100011000", "100011001", "100011010", "100011011", "100011100",
    "100011101", "100011110", "100011111", "100100000", "100100001", "100100010", "100100011", "100100100",
    "100100101", "100100110", "100100111", "100101000", "100101001", "100101010", "100101011", "100101100",
    "100101101", "100101110", "100101111", "100110000", "100110001", "100110010", "100110011", "100110100",
    "100110101", "100110110", "100110111", "100111000", "100111001", "100111010", "100111011", "100111100",
    "100111101", "100111110", "100111111", "101000000", "101000001", "101000010", "101000011", "101000100",
    "101000101", "101000110", "101000111", "101001000", "101001001", "101001010", "101001011", "101001100",
    "101001101", "101001110", "101001111", "101010000", "101010001", "101010010", "101010011", "101010100",
    "101010101", "101010110", "101010111", "101011000", "101011001", "101011010", "101011011", "101011100",
    "101011101", "101011110", "101011111", "101100000", "101100001", "101100010", "101100011", "101100100",
    "101100101", "101100110", "101100111", "101101000", "101101001", "101101010", "101101011", "101101100",
    "101101101", "101101110", "101101111", "101110000", "101110001", "101110010", "101110011", "101110100",
    "101110101", "101110110", "101110111", "101111000", "101111001", "101111010", "101111011", "101111100",
    "101111101", "101111110", "101111111", "110000000", "110000001", "110000010", "110000011", "110000100",
    "110000101", "110000110", "110000111", "110001000", "110001001", "110001010", "110001011", "110001100",
    "110001101", "110001110", "110001111", "110010000", "110010001", "110010010", "110010011", "110010100",
    "110010101", "110010110", "110010111", "110011000", "110011001", "110011010", "110011011", "110011100",
    "110011101", "110011110", "110011111", "110100000", "110100001", "110100010", "110100011", "110100100",
    "110100101", "110100110", "110100111", "110101000", "110101001", "110101010", "110101011", "110101100",
    "110101101", "110101110", "110101111", "110110000", "110110001", "110110010", "110110011", "110110100",
    "110110101", "110110110", "110110111", "110111000", "110111001", "110111010", "110111011", "110111100",
    "110111101", "110111110", "110111111", "111000000", "111000001", "111000010", "111000011", "111000100",
    "111000101", "111000110", "111000111", "111001000", "111001001", "111001010", "111001011", "111001100",
    "111001101", "111001110", "111001111", "111010000", "111010001", "111010010", "111010011", "111010100",
    "111010101", "111010110", "111010111", "111011000", "111011001", "111011010", "111011011", "111011100",
    "111011101", "111011110", "111011111", "111100000", "111100001", "111100010", "111100011", "111100100",
    "111100101", "111100110", "111100111", "111101000", "111101001", "111101010", "111101011", "111101100",
    "111101101", "111101110", "111101111", "111110000", "111110001", "111110010", "111110011", "111110100"
};

static const std::array<std::string, EXTENDED_CRAMSUB> s_cramSubDictCodes = {
    "00010", "00011", "00100", "00101", "00110", "00111", "010000", "010001",
    "010010", "010011", "010100", "010101", "0101110", "0101111", "0110000", "0110001",
    "0110010", "0110011", "0110100", "01110000", "01110001", "01110010", "01110011", "01110100",
    "01110101", "111110011", "111110100", "111110101", "111110110", "111110111", "111111000", "111111001",
    "1111110100", "1111110101", "1111110110", "1111110111", "11111110000", "11111110001", "11111110010", "11111110011",
    "11111110100", "111111101010", "111111101011", "111111101100", "111111101101", "111111101110", "111111101111", "111111110000",
    "111111110001", "111111110010", "111111110011", "111111110100", "111111110101", "111111110110", "111111110111", "111111111000",
    "111111111001", "111111111010", "111111111011", "111111111100", "111111111101", "111111111110", "111111111111", "0110101",
    "010110", "0110110", "0110111", "01110110", "01110111", "01111000", "01111001"
};

static const std::array<std::string, EXTENDED_CRAMSUB> s_cramSubChunkCodes = {
    "0011000", "0011001", "0011010", "0011011", "0011100", "000111", "0011101", "0011110",
    "0011111", "0100000", "0100001", "0100010", "0100011", "0100100", "0100101", "0100110",
    "0100111", "0101000", "0101001", "0101010", "0101011", "0101100", "0101101", "0101110",
    "0101111", "0110000", "0110001", "0110010", "0110011", "01101010", "01101011", "01101100",
    "01101101", "01101110", "01101111", "01110000", "01110001", "01110010", "01110011", "01110100",
    "01110101", "01110110", "01110111", "01111000", "01111001", "01111010", "111110101", "111110110",
    "111110111", "111111000", "111111001", "1111110100", "1111110101", "1111110110", "1111110111", "1111111000",
    "1111111001", "1111111010", "1111111011", "1111111100", "1111111101", "1111111110", "1111111111", "0110100",
    "00000", "00001", "00010", "001000", "001001", "001010", "001011"
};

// ------------------- LitByte Class -------------------
class LitByte : public MetaByte
{
public:
    static LitByte* getInstance(int value)
    {
        if (value < getMinVal() || value > getMaxVal()) {
            throw std::out_of_range("LitByte value must be between 0 and 255");
        }
        if (!s_initialized) {
            initializeAll();
        }
        return instances_[value];
    }

    std::string reprStr() const override { return reprStr_; }

    inline int numEncoding() const override { return numEncoding_; }

    std::string dictBinaryRep() const override { return dictBinaryRep_; }
    std::string chunkBinaryRep() const override { return chunkBinaryRep_; }

    // New inline accessor to return the cached dictionary binary length.
    inline int getDictBinaryLen() const { return dictBinaryLen_; }

    static std::string getPrefix() { return "0"; }
    static int getMaxVal() { return 255; }
    static int getMinVal() { return 0; }

    static std::pair<MetaByte*, std::string> decodeDictBinaryRep(const std::string &binary)
    {
        for (int i = 0; i < 256; i++) {
            const std::string &code = s_litByteDictCodes[i];
            if (code.empty()) continue;
            if (binary.compare(0, code.size(), code) == 0) {
                return std::make_pair(getInstance(i), binary.substr(code.size()));
            }
        }
        return std::make_pair(nullptr, binary);
    }

    static std::pair<MetaByte*, std::string> decodeChunkBinaryRep(const std::string &binary)
    {
        for (int i = 0; i < 256; i++) {
            const std::string &code = s_litByteChunkCodes[i];
            if (code.empty()) continue;
            if (binary.compare(0, code.size(), code) == 0) {
                return std::make_pair(getInstance(i), binary.substr(code.size()));
            }
        }
        return std::make_pair(nullptr, binary);
    }

private:
    explicit LitByte(int value)
        : value_(value),
          numEncoding_(value),
          reprStr_("LitByte: " + std::to_string(value)),
          dictBinaryRep_(s_litByteDictCodes[value]),
          chunkBinaryRep_(s_litByteChunkCodes[value]),
          dictBinaryLen_( static_cast<int>(s_litByteDictCodes[value].size()) ) // cache the length here
    {}

    static void initializeAll();

    int value_;
    int numEncoding_;
    std::string reprStr_;
    std::string dictBinaryRep_;
    std::string chunkBinaryRep_;
    int dictBinaryLen_;  // new member: cached length of the dictionary code

    static LitByte* instances_[256];
    static bool s_initialized;
};

// ------------------- CRAMSub Class -------------------
class CRAMSub : public MetaByte
{
public:
    static CRAMSub* getInstance(int value)
    {
        if (value < getMinVal() || value > getMaxVal()) {
            throw std::out_of_range("CRAMSub value must be between 0 and 63");
        }
        if (!s_initialized) {
            initializeAll();
        }
        return instances_[value];
    }

    std::string reprStr() const override { return reprStr_; }
    inline int numEncoding() const override { return numEncoding_; }
    std::string dictBinaryRep() const override { return dictBinaryRep_; }
    std::string chunkBinaryRep() const override { return chunkBinaryRep_; }

    int subIndex() const { return value_; }

    // New inline accessor.
    inline int getDictBinaryLen() const { return dictBinaryLen_; }

    static std::string getPrefix() { return "1"; }
    static int getMaxVal() { return EXTENDED_CRAMSUB; }
    static int getMinVal() { return 0; }

    static std::pair<MetaByte*, std::string> decodeDictBinaryRep(const std::string &binary)
    {
        for (int i = 0; i < EXTENDED_CRAMSUB; i++) {
            const std::string &code = s_cramSubDictCodes[i];
            if (code.empty()) continue;
            if (binary.compare(0, code.size(), code) == 0) {
                return std::make_pair(getInstance(i), binary.substr(code.size()));
            }
        }
        return std::make_pair(nullptr, binary);
    }

    static std::pair<MetaByte*, std::string> decodeChunkBinaryRep(const std::string &binary)
    {
        for (int i = 0; i < EXTENDED_CRAMSUB; i++) {
            const std::string &code = s_cramSubChunkCodes[i];
            if (code.empty()) continue;
            if (binary.compare(0, code.size(), code) == 0) {
                return std::make_pair(getInstance(i), binary.substr(code.size()));
            }
        }
        return std::make_pair(nullptr, binary);
    }

private:
    explicit CRAMSub(int value)
        : value_(value),
          numEncoding_((1 << 8) | value),
          reprStr_("CRAMSub: " + std::to_string(value)),
          dictBinaryRep_(s_cramSubDictCodes[value]),
          chunkBinaryRep_(s_cramSubChunkCodes[value]),
          dictBinaryLen_( static_cast<int>(s_cramSubDictCodes[value].size()) )
    {}

    static void initializeAll();

    int value_;
    int numEncoding_;
    std::string reprStr_;
    std::string dictBinaryRep_;
    std::string chunkBinaryRep_;
    int dictBinaryLen_;  // new member

    static CRAMSub* instances_[EXTENDED_CRAMSUB];
    static bool s_initialized;
};

// ------------------- Encoding Map -------------------
inline std::map<int, MetaByte*>& getEncodingToObjectMap()
{
    static std::map<int, MetaByte*> encodingMap;
    static bool initialized = false;
    if (!initialized) {
        for (int i = 0; i < 256; i++) {
            MetaByte* obj = LitByte::getInstance(i);
            encodingMap[obj->numEncoding()] = obj;
        }
        for (int i = 0; i < EXTENDED_CRAMSUB; i++) {
            MetaByte* obj = CRAMSub::getInstance(i);
            encodingMap[obj->numEncoding()] = obj;
        }
        initialized = true;
    }
    return encodingMap;
}

#endif // CRAM_TREE_H