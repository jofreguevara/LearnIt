#ifndef LEARNIT_CORE_H
#define LEARNIT_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

const char *learnit_core_version(void);
char *learnit_demo_reply(const char *input, const char *language);
void learnit_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
