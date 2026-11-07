#define COMPRESSION_NODE_NAME pg_compression

#ifndef SLICE
    #define SLICE 8
#endif
#define PAGE_SIZE (4096/SLICE)