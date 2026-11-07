#include <huffman1byte.h>
#include <lz4/lib/lz4.c>

__thread uint8_t temp[8192];
//Takes a page(4k) of data, produce compressed data in target(<5k)
//returns bytes produced by lz4 in lz4_bytes
//returns size of encoding in bytes
uint64_t lz4_huffman1_encode(uint8_t * data, uint8_t * target, uint16_t * lz4_bytes)
{
    int tsize = LZ4_compress_default((const char *)data, (char *)temp, *lz4_bytes, *lz4_bytes * 2);
    //printf("%d, %d\n", *lz4_bytes, tsize);
    *lz4_bytes = tsize;
    /*
    if (tsize <= 128 + tsize / 8)
    {
        int i;
        for (i = 0; i < tsize; i++)
            target[i] = temp[i];
        return tsize;
    }
    */
    return Huffman1_encode(temp, target, tsize);
}

//Takes a compressed page, a target page, and count of bytes that lz4 encoding produces
//writes decompressed page to target
//returns size of decompressed in bytes
uint64_t lz4_huffman1_decode(uint8_t * compressed, uint8_t * target, uint16_t lz4_bytes)
{
    uint8_t temp2[8192];
    /*
    if (lz4_bytes <= 128 + lz4_bytes / 8)
    {
        return LZ4_decompress_safe((const char *)compressed, (char *)target, lz4_bytes, 5000);
    }
    */
    Huffman1_decode(compressed, temp2, lz4_bytes);
    int i = LZ4_decompress_safe((const char *)temp2, (char *)target, lz4_bytes, 5000);
    if (i <= 0)
    {
        printf("lz4 size: %d\n", lz4_bytes);
        int j;
        for (j = 0; j < lz4_bytes; j++)
        {
            if (temp[j] != temp2[j])
            {
                printf("lh why? %d", j);
            }
        }
    }
    return i;
}