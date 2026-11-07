#include <inttypes.h>
#include <string.h>
#include <sys/types.h>
#include <dlfcn.h>
#include <limits.h>
#include <termios.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>

#include <plugin_struct.h>

struct layout LAYOUT_NODE_NAME;

#define pg_comp_node_name "pg_compression"
#ifndef SLICE
    #define SLICE 8
#endif
#define FEED_SIZE (4096/SLICE)

struct compression * pg_comp;
struct compression * dummy;
static uint64_t pg_cp(struct compression * c_p, uint8_t * start, uint16_t ** report);

static void pg_init(struct compression ** c_p)
{
    dummy = NULL;
    pg_comp = NULL;
    int count = 0;
    char strtmp[PATH_MAX + 1];
    strtmp[0] = '\0';
    strcpy(strtmp, layout_folder);
    strcat(strtmp, "/");
    strcat(strtmp, "page-granularity");

    DIR * dir = opendir(strtmp);
    if (dir == NULL)
        return;
    struct dirent * dentry;
    void *handle;
    while ((dentry = readdir(dir)) != NULL)
    {
        if (!strstr(dentry->d_name, ".so"))
            continue;
        char modname[PATH_MAX + 1];
        snprintf(modname, sizeof modname, "./%s/%s", strtmp, dentry->d_name);
        handle = dlopen(modname, RTLD_LAZY);
        if (handle == NULL)
        {
            printf("pg: can't open %s:%s\n", modname, dlerror());
            return;
        }
        struct compression * p = dlsym(handle, pg_comp_node_name);
        if (p == NULL)
        {
            printf("pg: can't open node in %s:%s\n", modname, dlerror());
            dlclose(handle);
            return;
        }
        p->next = pg_comp;
        pg_comp = p;
        count++;
        struct compression * temp = malloc(sizeof(struct compression));
        temp->next = dummy;
        dummy = temp;
        dummy->name = pg_comp->name;
        dummy->sharedv = LAYOUT_NODE_NAME.sharedv;
        pg_comp->sharedv = LAYOUT_NODE_NAME.sharedv;
        dummy->compress = (run_compression_t) pg_cp;
    }
    LAYOUT_NODE_NAME.reports = dummy;
    if (pg_comp == NULL)
        return;
    LAYOUT_NODE_NAME.report_count = count;
    if (*c_p == NULL)
    {
        *c_p = dummy;
        return;
    }
    struct compression * cp = *c_p;
    for (; cp->next != NULL; cp = cp->next) {}
    cp->next = dummy;
}

static uint64_t pg_cp(struct compression * c_p, uint8_t * start, uint16_t ** report)
{
    uint64_t i, sum = 0;
    uint16_t * r = NULL;
    struct compression * cp = pg_comp;
    for (; cp != NULL && cp->name != c_p->name; cp = cp->next) {}
    if (cp == NULL)
        printf("?\n");
    for (i = 0; i < PAGE_SIZE; i += FEED_SIZE)
    {
        sum += cp->compress(cp, start + i, &r);
        if (r != NULL)
            free(r);
        r = NULL;
    }
    //if (sum > FEED_SIZE * 8)
    //    printf("?%ld\n", sum/8);
    return sum;
}

static void pg_pr(struct compression * c_p, uint16_t * cl_list, uint16_t page_size)
{   return;}

static void pg_fr()     {return;}

static void pg_tcr()    {return;}

static void pg_cr()     {return;}

struct compression COMPRESSION_NODE_NAME = {
    .next = NULL,
    .name = "comp",
    .compress = (run_compression_t)pg_cp
};

struct layout LAYOUT_NODE_NAME = {
    .next = NULL,
    .name = "pg",
    .L_init = (layout_init_t) pg_init,
    .L_page_r = (layout_page_report_t) pg_pr,
    .L_final_r = (layout_final_report_t) pg_fr,
    .L_thread_clean_r = (layout_thread_clean_t) pg_tcr,
    .L_clean_r = (layout_clean_t) pg_cr,
    .reports = &COMPRESSION_NODE_NAME,
    .report_count = 0,
    .priority = 100
};