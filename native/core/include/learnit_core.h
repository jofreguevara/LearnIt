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

// Opaque native session and asynchronous inference job handles. The
// implementation owns all model state; callers only retain these pointers.
typedef struct learnit_core_session learnit_core_session_t;
typedef uint64_t learnit_core_job_id_t;

// Compatibility constructor for a session with only Whisper configured.
learnit_core_session_t *learnit_core_session_create(
    const char *whisper_model_path,
    int32_t whisper_threads);

// Creates a session with independently optional STT, LLM, and TTS resources.
// All paths must point to locally verified files/directories. Model loading is
// lazy and runs on native worker jobs.
learnit_core_session_t *learnit_core_session_create_ex(
    const char *whisper_model_path,
    const char *dialogue_model_path,
    const char *supertonic_model_dir,
    const char *supertonic_voice_style_path,
    int32_t threads);

// Joins pending native workers and releases the model/context.
void learnit_core_session_destroy(learnit_core_session_t *session);

// Loads every configured component synchronously. The asynchronous entry
// points perform the same load lazily; this function is for explicit warm-up
// and host tooling.
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

// Starts a dialogue request. request_json is copied before this function
// returns and should contain text, language, level, companion, memories, and
// last_summary. Polling returns a JSON envelope with type "dialogue".
learnit_core_job_id_t learnit_core_dialogue_start(
    learnit_core_session_t *session,
    const char *request_json);

// Starts Supertonic synthesis. Text and options are copied before return.
// Polling returns a JSON envelope with type "audio" and a base64 WAV payload.
learnit_core_job_id_t learnit_core_tts_start(
    learnit_core_session_t *session,
    const char *text,
    const char *language,
    const char *voice_style_id,
    float speaking_rate);

#ifdef __cplusplus
}
#endif

#endif
