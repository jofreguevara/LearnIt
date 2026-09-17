#include "llama_adapter.h"

#include <algorithm>
#include <array>
#include <clocale>
#include <fstream>
#include <limits>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include <nlohmann/json.hpp>

#include "llama.h"

namespace {

using json = nlohmann::json;

std::string language_from_request(const json &request) {
  const auto value = request.value("language", "en");
  if (value == "es") {
    return "es";
  }
  return "en";
}

std::string build_system_prompt(const json &request) {
  const auto companion =
      request.contains("companion") && request["companion"].is_object()
          ? request["companion"]
          : json::object();
  const std::string name = companion.value("name", "Alex");
  const std::string personality =
      companion.value("personality", "amable y curioso");
  const std::string correction_mode =
      companion.value("correction_mode", "gentle");
  const std::string level = request.value("level", "A1");

  std::ostringstream prompt;
  prompt << "You are " << name
         << ", a warm and concise English practice companion. Your "
            "personality is "
         << personality << ". The learner level is " << level << ". "
         << "Correction mode is " << correction_mode << ".\n"
         << "Answer the learner's latest turn helpfully. Keep the answer "
            "short enough to say aloud in one or two sentences.\n"
         << "Return only one JSON object, with no Markdown and no analysis, "
            "using this exact shape:\n"
         << R"({"segments":[{"text":"...","language":"en"}],"corrections":[],"topics":[],"memory_proposals":[]})"
         << "\nEach segment language must be \"en\" or \"es\". Put a "
            "correction in corrections only when correction mode is not "
            "\"off\". A memory proposal must contain key, value, and reason; "
            "do not invent personal facts.";
  return prompt.str();
}

bool make_prompt(const llama_model *model,
                 const std::string &system_prompt,
                 const std::string &user_prompt,
                 std::string *prompt,
                 std::string *error_message) {
  if (prompt == nullptr || error_message == nullptr) {
    return false;
  }
  const char *template_name = llama_model_chat_template(model, nullptr);
  if (template_name == nullptr || template_name[0] == '\0') {
    *prompt = "System:\n" + system_prompt + "\nUser:\n" + user_prompt +
              "\nAssistant:\n";
    return true;
  }

  std::vector<llama_chat_message> messages = {
      {"system", system_prompt.c_str()},
      {"user", user_prompt.c_str()},
  };
  const int32_t required = llama_chat_apply_template(
      template_name, messages.data(), messages.size(), true, nullptr, 0);
  if (required < 0) {
    *error_message = "llama.cpp no pudo aplicar la plantilla de chat.";
    return false;
  }
  std::vector<char> formatted(static_cast<size_t>(required) + 1U, '\0');
  const int32_t written = llama_chat_apply_template(
      template_name, messages.data(), messages.size(), true, formatted.data(),
      static_cast<int32_t>(formatted.size()));
  if (written < 0 || written > required) {
    *error_message = "llama.cpp produjo un prompt de chat inválido.";
    return false;
  }
  prompt->assign(formatted.data(), static_cast<size_t>(written));
  return true;
}

bool tokenize(const llama_vocab *vocab,
              const std::string &prompt,
              std::vector<llama_token> *tokens,
              std::string *error_message) {
  if (prompt.size() > static_cast<size_t>(std::numeric_limits<int32_t>::max())) {
    *error_message = "El prompt del diálogo excede el tamaño permitido.";
    return false;
  }
  const int32_t token_count = -llama_tokenize(
      vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()), nullptr, 0,
      true, true);
  if (token_count <= 0) {
    *error_message = "llama.cpp no pudo tokenizar el prompt.";
    return false;
  }
  tokens->resize(static_cast<size_t>(token_count));
  if (llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                     tokens->data(), token_count, true, true) < 0) {
    *error_message = "llama.cpp no pudo completar la tokenización.";
    return false;
  }
  return true;
}

bool append_piece(const llama_vocab *vocab,
                  llama_token token,
                  std::string *output,
                  std::string *error_message) {
  std::array<char, 256> buffer{};
  int32_t count = llama_token_to_piece(vocab, token, buffer.data(),
                                       static_cast<int32_t>(buffer.size()), 0,
                                       false);
  if (count < 0) {
    buffer.fill('\0');
    std::vector<char> resized(static_cast<size_t>(-count) + 1U, '\0');
    count = llama_token_to_piece(
        vocab, token, resized.data(), static_cast<int32_t>(resized.size()), 0,
        false);
    if (count < 0) {
      *error_message = "llama.cpp no pudo decodificar un token.";
      return false;
    }
    output->append(resized.data(), static_cast<size_t>(count));
    return true;
  }
  output->append(buffer.data(), static_cast<size_t>(count));
  return true;
}

}  // namespace

LearnItLlamaAdapter::LearnItLlamaAdapter(std::string model_path,
                                         int32_t threads)
    : model_path_(std::move(model_path)),
      threads_(std::clamp<int32_t>(threads, 1, 8)) {
  std::ifstream model(model_path_, std::ios::binary);
  if (!model.good()) {
    error_code_ = "model_file_missing";
    error_message_ = "No se pudo abrir el modelo GGUF local.";
    return;
  }

  static std::once_flag backend_once;
  std::call_once(backend_once, []() {
    std::setlocale(LC_NUMERIC, "C");
    llama_backend_init();
  });

  auto model_params = llama_model_default_params();
  model_params.n_gpu_layers = 0;
  model_params.vocab_only = false;
  model_ = llama_model_load_from_file(model_path_.c_str(), model_params);
  if (model_ == nullptr) {
    error_code_ = "model_load_failed";
    error_message_ = "llama.cpp no pudo cargar el modelo GGUF indicado.";
  }
}

LearnItLlamaAdapter::~LearnItLlamaAdapter() {
  if (model_ != nullptr) {
    llama_model_free(model_);
    model_ = nullptr;
  }
}

bool LearnItLlamaAdapter::ready() const { return model_ != nullptr; }

const std::string &LearnItLlamaAdapter::error_code() const {
  return error_code_;
}

const std::string &LearnItLlamaAdapter::error_message() const {
  return error_message_;
}

bool LearnItLlamaAdapter::abort_callback(void *user_data) {
  if (user_data == nullptr) {
    return false;
  }
  const auto *cancel_requested =
      static_cast<const std::atomic<bool> *>(user_data);
  return cancel_requested->load(std::memory_order_relaxed);
}

bool LearnItLlamaAdapter::generate(
    const std::string &request_json,
    const std::atomic<bool> &cancel_requested,
    LearnItLlamaResult *result,
    std::string *error_code,
    std::string *error_message) {
  if (result == nullptr || error_code == nullptr || error_message == nullptr) {
    return false;
  }
  if (!ready()) {
    *error_code = error_code_.empty() ? "model_not_loaded" : error_code_;
    *error_message = error_message_.empty()
                         ? "El modelo llama.cpp no está disponible."
                         : error_message_;
    return false;
  }
  if (cancel_requested.load(std::memory_order_relaxed)) {
    *error_code = "cancelled";
    *error_message = "La generación fue cancelada.";
    return false;
  }

  json request;
  try {
    request = json::parse(request_json);
  } catch (const json::exception &) {
    *error_code = "invalid_request";
    *error_message = "La solicitud de diálogo no es JSON válido.";
    return false;
  }
  if (!request.is_object()) {
    *error_code = "invalid_request";
    *error_message = "La solicitud de diálogo debe ser un objeto JSON.";
    return false;
  }
  const std::string input = request.value("text", "");
  if (input.find_first_not_of(" \t\r\n") == std::string::npos) {
    *error_code = "empty_text";
    *error_message = "No se recibió texto para el diálogo.";
    return false;
  }

  std::lock_guard<std::mutex> lock(inference_mutex_);
  const std::string system_prompt = build_system_prompt(request);
  const std::string user_prompt =
      "Latest learner turn:\n" + input +
      "\nUse this verified app context when relevant:\n" + request.dump();
  std::string prompt;
  if (!make_prompt(model_, system_prompt, user_prompt, &prompt,
                   error_message)) {
    *error_code = "prompt_failed";
    return false;
  }

  const llama_vocab *vocab = llama_model_get_vocab(model_);
  std::vector<llama_token> prompt_tokens;
  if (!tokenize(vocab, prompt, &prompt_tokens, error_message)) {
    *error_code = "tokenization_failed";
    return false;
  }

  constexpr int32_t kContextTokens = 2048;
  constexpr int32_t kMaxGeneratedTokens = 160;
  if (prompt_tokens.size() + kMaxGeneratedTokens >= kContextTokens) {
    *error_code = "context_overflow";
    *error_message = "El contexto del diálogo excede los 2048 tokens.";
    return false;
  }

  auto context_params = llama_context_default_params();
  context_params.n_ctx = kContextTokens;
  context_params.n_batch = kContextTokens;
  context_params.n_threads = threads_;
  context_params.n_threads_batch = threads_;
  context_params.abort_callback = &LearnItLlamaAdapter::abort_callback;
  context_params.abort_callback_data =
      const_cast<std::atomic<bool> *>(&cancel_requested);
  llama_context *context = llama_init_from_model(model_, context_params);
  if (context == nullptr) {
    *error_code = "context_create_failed";
    *error_message = "llama.cpp no pudo crear el contexto de diálogo.";
    return false;
  }

  auto sampler_params = llama_sampler_chain_default_params();
  sampler_params.no_perf = true;
  llama_sampler *sampler = llama_sampler_chain_init(sampler_params);
  if (sampler == nullptr) {
    llama_free(context);
    *error_code = "sampler_create_failed";
    *error_message = "llama.cpp no pudo crear el muestreador.";
    return false;
  }
  llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

  llama_batch batch = llama_batch_get_one(
      prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()));
  if (llama_decode(context, batch) != 0) {
    llama_sampler_free(sampler);
    llama_free(context);
    if (cancel_requested.load(std::memory_order_relaxed)) {
      *error_code = "cancelled";
      *error_message = "La generación fue cancelada.";
    } else {
      *error_code = "decode_failed";
      *error_message = "llama.cpp no pudo evaluar el prompt.";
    }
    return false;
  }

  std::string generated;
  for (int32_t index = 0; index < kMaxGeneratedTokens; ++index) {
    if (cancel_requested.load(std::memory_order_relaxed)) {
      llama_sampler_free(sampler);
      llama_free(context);
      *error_code = "cancelled";
      *error_message = "La generación fue cancelada.";
      return false;
    }
    llama_token token = llama_sampler_sample(sampler, context, -1);
    if (llama_vocab_is_eog(vocab, token)) {
      break;
    }
    if (!append_piece(vocab, token, &generated, error_message)) {
      llama_sampler_free(sampler);
      llama_free(context);
      *error_code = "detokenization_failed";
      return false;
    }
    batch = llama_batch_get_one(&token, 1);
    if (llama_decode(context, batch) != 0) {
      llama_sampler_free(sampler);
      llama_free(context);
      if (cancel_requested.load(std::memory_order_relaxed)) {
        *error_code = "cancelled";
        *error_message = "La generación fue cancelada.";
      } else {
        *error_code = "decode_failed";
        *error_message = "llama.cpp no pudo generar la respuesta.";
      }
      return false;
    }
  }

  llama_sampler_free(sampler);
  llama_free(context);
  if (generated.find_first_not_of(" \t\r\n") == std::string::npos) {
    *error_code = "empty_response";
    *error_message = "llama.cpp no produjo una respuesta utilizable.";
    return false;
  }

  result->text = std::move(generated);
  result->language = language_from_request(request);
  return true;
}
