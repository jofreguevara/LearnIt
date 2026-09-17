#ifndef LEARNIT_CORE_H
#define LEARNIT_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *learnit_core_version(void);
const char *learnit_core_capabilities(void);
char *learnit_demo_reply(const char *input, const char *language);
void learnit_free_string(char *value);

// Opaque native session and asynchronous transcription job handles. The
// implementation owns all model state; callers only retain these pointers.
typedef struct learnit_core_session learnit_core_session_t;
typedef uint64_t learnit_core_job_id_t;

// Creates a session without loading the model. Loading is lazy and happens
// on the first worker job, so a Dart UI thread never waits for model I/O.
// The path must point to a locally verified Whisper ggml model. Passing NULL
// is useful for capability/error handling and creates an unusable session.
learnit_core_session_t *learnit_core_session_create(
    const char *whisper_model_path,
    int32_t whisper_threads);

// Joins pending native workers and releases the model/context.
void learnit_core_session_destroy(learnit_core_session_t *session);

// Loads the configured Whisper model synchronously. The asynchronous
// transcription entry point performs the same load lazily; this function is
// provided for host tooling and explicit warm-up flows.
int32_t learnit_core_session_load(learnit_core_session_t *session);
int32_t learnit_core_session_is_ready(const learnit_core_session_t *session);
const char *learnit_core_session_last_error(
    const learnit_core_session_t *session);

// Synchronous form for native host tests and simple integrations. The input
// is signed 16-bit mono PCM at exactly 16 kHz and the returned UTF-8 JSON must
// be released with learnit_free_string().
char *learnit_core_transcribe(
    learnit_core_session_t *session,
    const int16_t *samples,
    int32_t sample_count,
    int32_t sample_rate,
    const char *language_hint);

// Starts a copy-owning worker job. The caller may release its input buffer as
// soon as this function returns. Polling returns NULL while running and an
// allocated JSON result when complete; that result must be freed with
// learnit_free_string(). Job id 0 indicates invalid input.
learnit_core_job_id_t learnit_core_transcribe_start(
    learnit_core_session_t *session,
    const int16_t *samples,
    int32_t sample_count,
    int32_t sample_rate,
    const char *language_hint);
char *learnit_core_job_poll(
    learnit_core_session_t *session,
    learnit_core_job_id_t job_id);
int32_t learnit_core_job_cancel(
    learnit_core_session_t *session,
    learnit_core_job_id_t job_id);
void learnit_core_session_cancel(learnit_core_session_t *session);

#ifdef __cplusplus
}
#endif

#endif
