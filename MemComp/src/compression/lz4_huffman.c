#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>

#include <lz4_huffman.h>
#include <plugin_struct.h>

struct compression COMPRESSION_NODE_NAME;

static uint64_t h1lz4_compression(struct compression * c_p, uint8_t * start, uint16_t ** report)
{
    uint8_t temp[PAGE_SIZE*2];
    uint16_t tsize = PAGE_SIZE;
    uint64_t result = lz4_huffman1_encode(start, temp, &tsize);
    if (COMPRESSION_NODE_NAME.sharedv->validate)
    {
        uint8_t decompressed[PAGE_SIZE];
        uint64_t j = lz4_huffman1_decode(temp, decompressed, tsize);
        if (j != PAGE_SIZE)
            printf("lz4_huffman Error2: size=%ld!=%d\n", j, PAGE_SIZE);
        for (j = 0; j < PAGE_SIZE; j++)
            if (start[j] != decompressed[j])
            {
                printf("lz4_huffman Error: offset=%ld\n", j);
                return ERROR_SIZE;
            }
    }
    return result * 8;
}

struct compression COMPRESSION_NODE_NAME = {
    .next = NULL,
    .name = "lz4_huffman",
    .compress = (run_compression_t)h1lz4_compression
};
