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
#include <bitset>

// We choose a fixed size for our bitset storage (16 bits is enough for our codes)
static const int MAX_CODE_BITS = 16;
static const int EXTENDED_CRAMSUB = 72;

// ----------------- Helper Struct and Functions -----------------
//
// BinaryCode holds a fixed-size bitset and the effective length (number
// of bits actually used in the Huffman code).
//
struct BinaryCode {
    std::bitset<MAX_CODE_BITS> bits;
    int length;
};

// Macro to construct a BinaryCode from a literal.
// sizeof(x)-1 gives the length of the literal (excluding the null).
#define BC(x) BinaryCode{ std::bitset<MAX_CODE_BITS>(x), static_cast<int>(sizeof(x) - 1) }

// Helper function that converts a bitset to a string containing only the
// "effective" (low‑order) bits.
static inline std::string bitsetToString(const std::bitset<MAX_CODE_BITS>& bits, int length) {
    std::string full = bits.to_string();
    return full.substr(MAX_CODE_BITS - length);
}

// ------------------- Static Arrays for Huffman Trees -------------------
// (These arrays must be defined before we use them in our precomputed string functions.)

static const std::array<BinaryCode, 256> s_litByteDictCodes = {{
    BC("0000"), BC("011110100"), BC("011110101"), BC("011110110"),
    BC("011110111"), BC("011111000"), BC("011111001"), BC("011111010"),
    BC("011111011"), BC("011111100"), BC("011111101"), BC("011111110"),
    BC("011111111"), BC("100000000"), BC("100000001"), BC("100000010"),
    BC("100000011"), BC("100000100"), BC("100000101"), BC("100000110"),
    BC("100000111"), BC("100001000"), BC("100001001"), BC("100001010"),
    BC("100001011"), BC("100001100"), BC("100001101"), BC("100001110"),
    BC("100001111"), BC("100010000"), BC("100010001"), BC("100010010"),
    BC("100010011"), BC("100010100"), BC("100010101"), BC("100010110"),
    BC("100010111"), BC("100011000"), BC("100011001"), BC("100011010"),
    BC("100011011"), BC("100011100"), BC("100011101"), BC("100011110"),
    BC("100011111"), BC("100100000"), BC("100100001"), BC("100100010"),
    BC("100100011"), BC("100100100"), BC("100100101"), BC("100100110"),
    BC("100100111"), BC("100101000"), BC("100101001"), BC("100101010"),
    BC("100101011"), BC("100101100"), BC("100101101"), BC("100101110"),
    BC("100101111"), BC("100110000"), BC("100110001"), BC("100110010"),
    BC("100110011"), BC("100110100"), BC("100110101"), BC("100110110"),
    BC("100110111"), BC("100111000"), BC("100111001"), BC("100111010"),
    BC("100111011"), BC("100111100"), BC("100111101"), BC("100111110"),
    BC("100111111"), BC("101000000"), BC("101000001"), BC("101000010"),
    BC("101000011"), BC("101000100"), BC("101000101"), BC("101000110"),
    BC("101000111"), BC("101001000"), BC("101001001"), BC("101001010"),
    BC("101001011"), BC("101001100"), BC("101001101"), BC("101001110"),
    BC("101001111"), BC("101010000"), BC("101010001"), BC("101010010"),
    BC("101010011"), BC("101010100"), BC("101010101"), BC("101010110"),
    BC("101010111"), BC("101011000"), BC("101011001"), BC("101011010"),
    BC("101011011"), BC("101011100"), BC("101011101"), BC("101011110"),
    BC("101011111"), BC("101100000"), BC("101100001"), BC("101100010"),
    BC("101100011"), BC("101100100"), BC("101100101"), BC("101100110"),
    BC("101100111"), BC("101101000"), BC("101101001"), BC("101101010"),
    BC("101101011"), BC("101101100"), BC("101101101"), BC("101101110"),
    BC("101101111"), BC("101110000"), BC("101110001"), BC("101110010"),
    BC("101110011"), BC("101110100"), BC("101110101"), BC("101110110"),
    BC("101110111"), BC("101111000"), BC("101111001"), BC("101111010"),
    BC("101111011"), BC("101111100"), BC("101111101"), BC("101111110"),
    BC("101111111"), BC("110000000"), BC("110000001"), BC("110000010"),
    BC("110000011"), BC("110000100"), BC("110000101"), BC("110000110"),
    BC("110000111"), BC("110001000"), BC("110001001"), BC("110001010"),
    BC("110001011"), BC("110001100"), BC("110001101"), BC("110001110"),
    BC("110001111"), BC("110010000"), BC("110010001"), BC("110010010"),
    BC("110010011"), BC("110010100"), BC("110010101"), BC("110010110"),
    BC("110010111"), BC("110011000"), BC("110011001"), BC("110011010"),
    BC("110011011"), BC("110011100"), BC("110011101"), BC("110011110"),
    BC("110011111"), BC("110100000"), BC("110100001"), BC("110100010"),
    BC("110100011"), BC("110100100"), BC("110100101"), BC("110100110"),
    BC("110100111"), BC("110101000"), BC("110101001"), BC("110101010"),
    BC("110101011"), BC("110101100"), BC("110101101"), BC("110101110"),
    BC("110101111"), BC("110110000"), BC("110110001"), BC("110110010"),
    BC("110110011"), BC("110110100"), BC("110110101"), BC("110110110"),
    BC("110110111"), BC("110111000"), BC("110111001"), BC("110111010"),
    BC("110111011"), BC("110111100"), BC("110111101"), BC("110111110"),
    BC("110111111"), BC("111000000"), BC("111000001"), BC("111000010"),
    BC("111000011"), BC("111000100"), BC("111000101"), BC("111000110"),
    BC("111000111"), BC("111001000"), BC("111001001"), BC("111001010"),
    BC("111001011"), BC("111001100"), BC("111001101"), BC("111001110"),
    BC("111001111"), BC("111010000"), BC("111010001"), BC("111010010"),
    BC("111010011"), BC("111010100"), BC("111010101"), BC("111010110"),
    BC("111010111"), BC("111011000"), BC("111011001"), BC("111011010"),
    BC("111011011"), BC("111011100"), BC("111011101"), BC("111011110"),
    BC("111011111"), BC("111100000"), BC("111100001"), BC("111100010"),
    BC("111100011"), BC("111100100"), BC("111100101"), BC("111100110"),
    BC("111100111"), BC("111101000"), BC("111101001"), BC("111101010"),
    BC("111101011"), BC("111101100"), BC("111101101"), BC("111101110"),
    BC("111101111"), BC("111110000"), BC("111110001"), BC("111110010")
}};

static const std::array<BinaryCode, 256> s_litByteChunkCodes = {{
    BC("000110"), BC("011110110"), BC("011110111"), BC("011111000"),
    BC("011111001"), BC("011111010"), BC("011111011"), BC("011111100"),
    BC("011111101"), BC("011111110"), BC("011111111"), BC("100000000"),
    BC("100000001"), BC("100000010"), BC("100000011"), BC("100000100"),
    BC("100000101"), BC("100000110"), BC("100000111"), BC("100001000"),
    BC("100001001"), BC("100001010"), BC("100001011"), BC("100001100"),
    BC("100001101"), BC("100001110"), BC("100001111"), BC("100010000"),
    BC("100010001"), BC("100010010"), BC("100010011"), BC("100010100"),
    BC("100010101"), BC("100010110"), BC("100010111"), BC("100011000"),
    BC("100011001"), BC("100011010"), BC("100011011"), BC("100011100"),
    BC("100011101"), BC("100011110"), BC("100011111"), BC("100100000"),
    BC("100100001"), BC("100100010"), BC("100100011"), BC("100100100"),
    BC("100100101"), BC("100100110"), BC("100100111"), BC("100101000"),
    BC("100101001"), BC("100101010"), BC("100101011"), BC("100101100"),
    BC("100101101"), BC("100101110"), BC("100101111"), BC("100110000"),
    BC("100110001"), BC("100110010"), BC("100110011"), BC("100110100"),
    BC("100110101"), BC("100110110"), BC("100110111"), BC("100111000"),
    BC("100111001"), BC("100111010"), BC("100111011"), BC("100111100"),
    BC("100111101"), BC("100111110"), BC("100111111"), BC("101000000"),
    BC("101000001"), BC("101000010"), BC("101000011"), BC("101000100"),
    BC("101000101"), BC("101000110"), BC("101000111"), BC("101001000"),
    BC("101001001"), BC("101001010"), BC("101001011"), BC("101001100"),
    BC("101001101"), BC("101001110"), BC("101001111"), BC("101010000"),
    BC("101010001"), BC("101010010"), BC("101010011"), BC("101010100"),
    BC("101010101"), BC("101010110"), BC("101010111"), BC("101011000"),
    BC("101011001"), BC("101011010"), BC("101011011"), BC("101011100"),
    BC("101011101"), BC("101011110"), BC("101011111"), BC("101100000"),
    BC("101100001"), BC("101100010"), BC("101100011"), BC("101100100"),
    BC("101100101"), BC("101100110"), BC("101100111"), BC("101101000"),
    BC("101101001"), BC("101101010"), BC("101101011"), BC("101101100"),
    BC("101101101"), BC("101101110"), BC("101101111"), BC("101110000"),
    BC("101110001"), BC("101110010"), BC("101110011"), BC("101110100"),
    BC("101110101"), BC("101110110"), BC("101110111"), BC("101111000"),
    BC("101111001"), BC("101111010"), BC("101111011"), BC("101111100"),
    BC("101111101"), BC("101111110"), BC("101111111"), BC("110000000"),
    BC("110000001"), BC("110000010"), BC("110000011"), BC("110000100"),
    BC("110000101"), BC("110000110"), BC("110000111"), BC("110001000"),
    BC("110001001"), BC("110001010"), BC("110001011"), BC("110001100"),
    BC("110001101"), BC("110001110"), BC("110001111"), BC("110010000"),
    BC("110010001"), BC("110010010"), BC("110010011"), BC("110010100"),
    BC("110010101"), BC("110010110"), BC("110010111"), BC("110011000"),
    BC("110011001"), BC("110011010"), BC("110011011"), BC("110011100"),
    BC("110011101"), BC("110011110"), BC("110011111"), BC("110100000"),
    BC("110100001"), BC("110100010"), BC("110100011"), BC("110100100"),
    BC("110100101"), BC("110100110"), BC("110100111"), BC("110101000"),
    BC("110101001"), BC("110101010"), BC("110101011"), BC("110101100"),
    BC("110101101"), BC("110101110"), BC("110101111"), BC("110110000"),
    BC("110110001"), BC("110110010"), BC("110110011"), BC("110110100"),
    BC("110110101"), BC("110110110"), BC("110110111"), BC("110111000"),
    BC("110111001"), BC("110111010"), BC("110111011"), BC("110111100"),
    BC("110111101"), BC("110111110"), BC("110111111"), BC("111000000"),
    BC("111000001"), BC("111000010"), BC("111000011"), BC("111000100"),
    BC("111000101"), BC("111000110"), BC("111000111"), BC("111001000"),
    BC("111001001"), BC("111001010"), BC("111001011"), BC("111001100"),
    BC("111001101"), BC("111001110"), BC("111001111"), BC("111010000"),
    BC("111010001"), BC("111010010"), BC("111010011"), BC("111010100"),
    BC("111010101"), BC("111010110"), BC("111010111"), BC("111011000"),
    BC("111011001"), BC("111011010"), BC("111011011"), BC("111011100"),
    BC("111011101"), BC("111011110"), BC("111011111"), BC("111100000"),
    BC("111100001"), BC("111100010"), BC("111100011"), BC("111100100"),
    BC("111100101"), BC("111100110"), BC("111100111"), BC("111101000"),
    BC("111101001"), BC("111101010"), BC("111101011"), BC("111101100"),
    BC("111101101"), BC("111101110"), BC("111101111"), BC("111110000"),
    BC("111110001"), BC("111110010"), BC("111110011"), BC("111110100")
}};

static const std::array<BinaryCode, EXTENDED_CRAMSUB> s_cramSubDictCodes = {{
    BC("00010"), BC("00011"), BC("00100"), BC("00101"),
    BC("00110"), BC("00111"), BC("010000"), BC("010001"),
    BC("010010"), BC("010011"), BC("010100"), BC("010101"),
    BC("0101110"), BC("0101111"), BC("0110000"), BC("0110001"),
    BC("0110010"), BC("0110011"), BC("0110100"), BC("01110000"),
    BC("01110001"), BC("01110010"), BC("01110011"), BC("01110100"),
    BC("01110101"), BC("111110011"), BC("111110100"), BC("111110101"),
    BC("111110110"), BC("111110111"), BC("111111000"), BC("111111001"),
    BC("1111110100"), BC("1111110101"), BC("1111110110"), BC("1111110111"),
    BC("11111110000"), BC("11111110001"), BC("11111110010"), BC("11111110011"),
    BC("11111110100"), BC("111111101010"), BC("111111101011"), BC("111111101100"),
    BC("111111101101"), BC("111111101110"), BC("111111101111"), BC("111111110000"),
    BC("111111110001"), BC("111111110010"), BC("111111110011"), BC("111111110100"),
    BC("111111110101"), BC("111111110110"), BC("111111110111"), BC("111111111000"),
    BC("111111111001"), BC("111111111010"), BC("111111111011"), BC("111111111100"),
    BC("111111111101"), BC("111111111110"), BC("111111111111"), BC("0110101"),
    BC("010110"), BC("0110110"), BC("0110111"), BC("01110110"),
    BC("01110111"), BC("01111000"), BC("01111001")
}};

static const std::array<BinaryCode, EXTENDED_CRAMSUB> s_cramSubChunkCodes = {{
    BC("0011000"), BC("0011001"), BC("0011010"), BC("0011011"),
    BC("0011100"), BC("000111"), BC("0011101"), BC("0011110"),
    BC("0011111"), BC("0100000"), BC("0100001"), BC("0100010"),
    BC("0100011"), BC("0100100"), BC("0100101"), BC("0100110"),
    BC("0100111"), BC("0101000"), BC("0101001"), BC("0101010"),
    BC("0101011"), BC("0101100"), BC("0101101"), BC("0101110"),
    BC("0101111"), BC("0110000"), BC("0110001"), BC("0110010"),
    BC("0110011"), BC("01101010"), BC("01101011"), BC("01101100"),
    BC("01101101"), BC("01101110"), BC("01101111"), BC("01110000"),
    BC("01110001"), BC("01110010"), BC("01110011"), BC("01110100"),
    BC("01110101"), BC("01110110"), BC("01110111"), BC("01111000"),
    BC("01111001"), BC("01111010"), BC("111110101"), BC("111110110"),
    BC("111110111"), BC("111111000"), BC("111111001"), BC("1111110100"),
    BC("1111110101"), BC("1111110110"), BC("1111110111"), BC("1111111000"),
    BC("1111111001"), BC("1111111010"), BC("1111111011"), BC("1111111100"),
    BC("1111111101"), BC("1111111110"), BC("1111111111"), BC("0110100"),
    BC("00000"), BC("00001"), BC("00010"), BC("001000"),
    BC("001001"), BC("001010"), BC("001011")
}};

// ------------------- Precomputed Code String Functions -------------------
static const std::array<std::string, 256>& getLitByteDictCodeStrs() {
    static const std::array<std::string, 256> arr = [](){
        std::array<std::string, 256> a;
        for (size_t i = 0; i < 256; i++) {
            a[i] = bitsetToString(s_litByteDictCodes[i].bits, s_litByteDictCodes[i].length);
        }
        return a;
    }();
    return arr;
}

static const std::array<std::string, 256>& getLitByteChunkCodeStrs() {
    static const std::array<std::string, 256> arr = [](){
        std::array<std::string, 256> a;
        for (size_t i = 0; i < 256; i++) {
            a[i] = bitsetToString(s_litByteChunkCodes[i].bits, s_litByteChunkCodes[i].length);
        }
        return a;
    }();
    return arr;
}

static const std::array<std::string, EXTENDED_CRAMSUB>& getCramSubDictCodeStrs() {
    static const std::array<std::string, EXTENDED_CRAMSUB> arr = [](){
        std::array<std::string, EXTENDED_CRAMSUB> a;
        for (size_t i = 0; i < EXTENDED_CRAMSUB; i++) {
            a[i] = bitsetToString(s_cramSubDictCodes[i].bits, s_cramSubDictCodes[i].length);
        }
        return a;
    }();
    return arr;
}

static const std::array<std::string, EXTENDED_CRAMSUB>& getCramSubChunkCodeStrs() {
    static const std::array<std::string, EXTENDED_CRAMSUB> arr = [](){
        std::array<std::string, EXTENDED_CRAMSUB> a;
        for (size_t i = 0; i < EXTENDED_CRAMSUB; i++) {
            a[i] = bitsetToString(s_cramSubChunkCodes[i].bits, s_cramSubChunkCodes[i].length);
        }
        return a;
    }();
    return arr;
}

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
    // Now these functions will convert the stored bitset to a trimmed string.
    virtual std::string dictBinaryRep() const = 0;
    virtual std::string chunkBinaryRep() const = 0;
    virtual int getDictBinaryLen() const = 0;
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

    std::string dictBinaryRep() const override { return bitsetToString(dictBinaryRep_, dictBinaryLen_); }
    std::string chunkBinaryRep() const override { return bitsetToString(chunkBinaryRep_, chunkBinaryLen_); }

    inline int getDictBinaryLen() const override { return dictBinaryLen_; }

    static std::string getPrefix() { return "0"; }
    static int getMaxVal() { return 255; }
    static int getMinVal() { return 0; }

    static std::pair<MetaByte*, std::string> decodeDictBinaryRep(const std::string &binary)
    {
        const auto &codeStrs = getLitByteDictCodeStrs();
        for (int i = 0; i < 256; i++) {
            const std::string &codeStr = codeStrs[i];
            if (codeStr.empty()) continue;
            if (binary.compare(0, codeStr.size(), codeStr) == 0) {
                return std::make_pair(getInstance(i), binary.substr(codeStr.size()));
            }
        }
        return std::make_pair(nullptr, binary);
    }

    static std::pair<MetaByte*, std::string> decodeChunkBinaryRep(const std::string &binary)
    {
        const auto &codeStrs = getLitByteChunkCodeStrs();
        for (int i = 0; i < 256; i++) {
            const std::string &codeStr = codeStrs[i];
            if (codeStr.empty()) continue;
            if (binary.compare(0, codeStr.size(), codeStr) == 0) {
                return std::make_pair(getInstance(i), binary.substr(codeStr.size()));
            }
        }
        return std::make_pair(nullptr, binary);
    }

private:
    explicit LitByte(int value)
        : value_(value),
          numEncoding_(value),
          reprStr_("LitByte: " + std::to_string(value)),
          dictBinaryRep_(s_litByteDictCodes[value].bits),
          chunkBinaryRep_(s_litByteChunkCodes[value].bits),
          dictBinaryLen_(s_litByteDictCodes[value].length),
          chunkBinaryLen_(s_litByteChunkCodes[value].length)
    {}

    static void initializeAll();

    int value_;
    int numEncoding_;
    std::string reprStr_;
    // Now we store the bitset representation (and we only convert to string on demand)
    std::bitset<MAX_CODE_BITS> dictBinaryRep_;
    std::bitset<MAX_CODE_BITS> chunkBinaryRep_;
    int dictBinaryLen_;  // cached length of the dictionary code
    int chunkBinaryLen_;

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
    std::string dictBinaryRep() const override { return bitsetToString(dictBinaryRep_, dictBinaryLen_); }
    std::string chunkBinaryRep() const override { return bitsetToString(chunkBinaryRep_, chunkBinaryLen_); }

    int subIndex() const { return value_; }

    inline int getDictBinaryLen() const override { return dictBinaryLen_; }

    static std::string getPrefix() { return "1"; }
    static int getMaxVal() { return EXTENDED_CRAMSUB; }
    static int getMinVal() { return 0; }

    static std::pair<MetaByte*, std::string> decodeDictBinaryRep(const std::string &binary)
    {
        const auto &codeStrs = getCramSubDictCodeStrs();
        for (int i = 0; i < EXTENDED_CRAMSUB; i++) {
            const std::string &codeStr = codeStrs[i];
            if (codeStr.empty()) continue;
            if (binary.compare(0, codeStr.size(), codeStr) == 0) {
                return std::make_pair(getInstance(i), binary.substr(codeStr.size()));
            }
        }
        return std::make_pair(nullptr, binary);
    }

    static std::pair<MetaByte*, std::string> decodeChunkBinaryRep(const std::string &binary)
    {
        const auto &codeStrs = getCramSubChunkCodeStrs();
        for (int i = 0; i < EXTENDED_CRAMSUB; i++) {
            const std::string &codeStr = codeStrs[i];
            if (codeStr.empty()) continue;
            if (binary.compare(0, codeStr.size(), codeStr) == 0) {
                return std::make_pair(getInstance(i), binary.substr(codeStr.size()));
            }
        }
        return std::make_pair(nullptr, binary);
    }

private:
    explicit CRAMSub(int value)
        : value_(value),
          numEncoding_((1 << 8) | value),
          reprStr_("CRAMSub: " + std::to_string(value)),
          dictBinaryRep_(s_cramSubDictCodes[value].bits),
          chunkBinaryRep_(s_cramSubChunkCodes[value].bits),
          dictBinaryLen_(s_cramSubDictCodes[value].length),
          chunkBinaryLen_(s_cramSubChunkCodes[value].length)
    {}

    static void initializeAll();

    int value_;
    int numEncoding_;
    std::string reprStr_;
    std::bitset<MAX_CODE_BITS> dictBinaryRep_;
    std::bitset<MAX_CODE_BITS> chunkBinaryRep_;
    int dictBinaryLen_;
    int chunkBinaryLen_;

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
