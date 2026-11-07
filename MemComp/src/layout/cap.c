#include <inttypes.h>

#include <plugin_struct.h>

struct layout LAYOUT_NODE_NAME;

#define PAGE_MAX (3604*8)
#define CL_MAX (CACHELINE_SIZE*8)

#define PAGE_CALC(a) (a > PAGE_MAX ? PAGE_SIZE * 8 : a)
#define CL_CALC(a) (NORM_CACHELINE(a) > CL_MAX ? CACHELINE_SIZE * 8 : a)

struct linked_compressions_record
{
    struct compression * comp;
    struct linked_compressions_record * next;
    uint64_t size;
    uint16_t * page_report;
};

struct linked_compressions_record * records = NULL;
__thread struct linked_compressions_record * run_r = NULL;
__thread struct linked_compressions_record * recycle = NULL;

static uint64_t cap_cp(struct compression * c_p, uint8_t * start, uint16_t ** report);

static void cap_fr()
{   return;}

static void cap_init(struct compression ** c_p)
{
    if (*c_p == NULL)
        return;
    int i;
    struct compression * cp = *c_p;
    for (i = 0; ; cp = cp->next)
    {
        struct compression * p = malloc(sizeof(struct compression));
        p->name = cp->name;
        p->next = LAYOUT_NODE_NAME.reports;
        p->compress = (run_compression_t) cap_cp;
        LAYOUT_NODE_NAME.reports = p;
        LAYOUT_NODE_NAME.report_count++;
        struct linked_compressions_record * r = malloc(sizeof(struct linked_compressions_record));
        r->comp = cp;
        r->next = records;
        records = r;
        if (cp->next == NULL)
        {
            cp->next = LAYOUT_NODE_NAME.reports;
            break;
        }
        i++;
    }
}

static void cap_pr(struct compression * c_p, uint16_t * cl_list, uint16_t page_size)
{
    struct linked_compressions_record * p;
    for (p = records; p != NULL; p = p->next)
    {
        if (p->comp == c_p)
        {
            struct linked_compressions_record * nr;
            if (recycle == NULL)
                nr = malloc(sizeof(struct linked_compressions_record));
            else
            {
                nr = recycle;
                recycle = recycle->next;
            }
            nr->size = PAGE_CALC(page_size);
            nr->comp = c_p;
            if (cl_list == NULL)
                nr->page_report = NULL;
            else
            {
                nr->page_report = malloc(sizeof(uint16_t) * (PAGE_SIZE / CACHELINE_SIZE));
                int i;
                for (i = 0; cl_list != NULL && i < PAGE_SIZE / CACHELINE_SIZE; i++)
                    nr->page_report[i] = CL_CALC(cl_list[i]);
            }
            nr->next = run_r;
            run_r = nr;
            break;
        }
    }
}

static uint64_t cap_cp(struct compression * c_p, uint8_t * start, uint16_t ** report)
{
    struct linked_compressions_record * p, * r = run_r;
    uint64_t ret = 0;
    for (p = run_r; p != NULL; p = p->next)
    {
        if (p->comp->name == c_p->name)
        {
            *report = p->page_report;
            ret = p->size;
            if (p == run_r)
                run_r = p->next;
            else
                r->next = p->next;
            p->next = recycle;
            recycle = p;
            return ret;
        }
        r = p;
    }
    printf("cap error: compression not found\n");
    return ERROR_SIZE;
}

static void cap_tcr()
{
    struct linked_compressions_record * p, *r;
    for (p = recycle; p != NULL; p = r)
    {
        r = p->next;
        free(p);
    }
    for (p = run_r; p != NULL; p = r)
    {
        r = p->next;
        if (p->page_report != NULL)
            free(p->page_report);
        free(p);
    }
    return;
}

static void cap_cr()
{
    struct linked_compressions_record * p, * r;
    for (p = records; p != NULL; p = r)
    {
        r = p->next;
        free(p);
    }
    return;
}

struct layout LAYOUT_NODE_NAME = {
    .next = NULL,
    .name = "cap",
    .L_init = (layout_init_t) cap_init,
    .L_page_r = (layout_page_report_t) cap_pr,
    .L_final_r = (layout_final_report_t) cap_fr,
    .L_thread_clean_r = (layout_thread_clean_t) cap_tcr,
    .L_clean_r = (layout_clean_t) cap_cr,
    .reports = NULL,
    .report_count = 0,
    .priority = -100
};