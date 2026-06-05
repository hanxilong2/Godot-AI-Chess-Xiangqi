using Godot;
using System;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace ChessAI.Module.Services
{
    public class LlmApiService : IDisposable
    {
        private readonly System.Net.Http.HttpClient _httpClient;
        private readonly CancellationTokenSource _shutdownCts = new CancellationTokenSource();
        private readonly JsonSerializerOptions _jsonOptions;
        private bool _disposed;

        public LlmApiService()
        {
            _httpClient = new System.Net.Http.HttpClient
            {
                Timeout = TimeSpan.FromMilliseconds(AI_Module_Config.API_TIMEOUT_MS)
            };
            _jsonOptions = new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
                WriteIndented = false
            };
        }

        public async Task<string> CompleteChatAsync(string systemPrompt, string userPrompt, string modelName = null, int maxTokens = -1)
        {
            ThrowIfDisposed();

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[LlmApiService] Sending chat completion request.");
                GD.Print($"[LlmApiService] Model: {modelName ?? AI_Module_Config.MODEL_NAME}");
            }

            if (AI_Module_Config.VERBOSE_CONTENT_LOGGING)
            {
                GD.Print($"[LlmApiService] System Prompt: {Preview(systemPrompt)}");
                GD.Print($"[LlmApiService] User Prompt: {Preview(userPrompt)}");
            }

            for (int retry = 0; retry < AI_Module_Config.API_RETRY_COUNT; retry++)
            {
                try
                {
                    var response = await SendRequestAsync(systemPrompt, userPrompt, modelName, maxTokens, _shutdownCts.Token);
                    if (AI_Module_Config.DEBUG_MODE)
                    {
                        GD.Print("[LlmApiService] Chat completion request succeeded.");
                    }
                    return response;
                }
                catch (OperationCanceledException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[LlmApiService] Chat completion request failed ({retry + 1}/{AI_Module_Config.API_RETRY_COUNT}): {ex.Message}");

                    if (IsConfigurationError(ex))
                    {
                        throw;
                    }

                    if (retry < AI_Module_Config.API_RETRY_COUNT - 1)
                    {
                        await Task.Delay(AI_Module_Config.API_RETRY_DELAY_MS, _shutdownCts.Token);
                    }
                    else
                    {
                        var message = AI_Module_Config.UseEnglishPrompts()
                            ? $"API request failed after {AI_Module_Config.API_RETRY_COUNT} retries"
                            : $"API\u8bf7\u6c42\u5931\u8d25\uff0c\u5df2\u91cd\u8bd5{AI_Module_Config.API_RETRY_COUNT}\u6b21";
                        throw new Exception(message, ex);
                    }
                }
            }

            return "";
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _shutdownCts.Cancel();
            _httpClient.Dispose();
            _shutdownCts.Dispose();
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
            {
                throw new ObjectDisposedException(nameof(LlmApiService));
            }
        }

        private async Task<string> SendRequestAsync(
            string systemPrompt,
            string userPrompt,
            string modelName = null,
            int maxTokens = -1,
            CancellationToken cancellationToken = default)
        {
            var requestBody = new
            {
                model = modelName ?? AI_Module_Config.MODEL_NAME,
                messages = new[]
                {
                    new { role = "system", content = systemPrompt },
                    new { role = "user", content = userPrompt }
                },
                temperature = AI_Module_Config.TEMPERATURE,
                max_tokens = maxTokens > 0 ? maxTokens : AI_Module_Config.MAX_TOKENS,
                enable_thinking = false,
                stream = false
            };

            var responseData = await SendChatRequestAsync(requestBody, cancellationToken);
            if (responseData?.Choices?.Length > 0)
            {
                return StripThinkingBlocks(responseData.Choices[0].Message?.Content ?? "");
            }

            throw UnexpectedFormatException();
        }

        private async Task<ApiResponse> SendChatRequestAsync(object requestBody, CancellationToken cancellationToken)
        {
            ThrowIfDisposed();
            cancellationToken.ThrowIfCancellationRequested();

            var apiKey = AI_Module_Config.GetApiKey();
            var apiKeyValidationError = AI_Module_Config.GetApiKeyValidationError(apiKey);
            if (!string.IsNullOrEmpty(apiKeyValidationError))
            {
                throw new Exception(apiKeyValidationError);
            }

            var jsonContent = JsonSerializer.Serialize(requestBody, _jsonOptions);
            var content = new System.Net.Http.StringContent(jsonContent, Encoding.UTF8, "application/json");

            var request = new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Post, AI_Module_Config.API_URL)
            {
                Content = content
            };
            request.Headers.Add("Authorization", $"Bearer {apiKey}");

            var response = await _httpClient.SendAsync(request, cancellationToken);
            var responseContent = await response.Content.ReadAsStringAsync(cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                var message = AI_Module_Config.UseEnglishPrompts()
                    ? $"API returned an error: {(int)response.StatusCode} {response.ReasonPhrase}; {responseContent}"
                    : $"API\u8fd4\u56de\u9519\u8bef: {(int)response.StatusCode} {response.ReasonPhrase}; {responseContent}";
                throw new Exception(message);
            }

            return JsonSerializer.Deserialize<ApiResponse>(responseContent, _jsonOptions);
        }

        private static string Preview(string text)
        {
            if (string.IsNullOrEmpty(text))
            {
                return "";
            }

            return text.Substring(0, Math.Min(120, text.Length)).Replace('\n', ' ') + (text.Length > 120 ? "..." : "");
        }

        private static string StripThinkingBlocks(string text)
        {
            var result = text ?? "";
            const string OpenTag = "<think>";
            const string CloseTag = "</think>";

            while (true)
            {
                var start = result.IndexOf(OpenTag, StringComparison.OrdinalIgnoreCase);
                if (start < 0)
                {
                    break;
                }

                var end = result.IndexOf(CloseTag, start, StringComparison.OrdinalIgnoreCase);
                if (end < 0)
                {
                    result = result.Substring(0, start);
                    break;
                }

                result = result.Remove(start, end + CloseTag.Length - start);
            }

            return result.Trim();
        }

        private static Exception UnexpectedFormatException()
        {
            return new Exception(AI_Module_Config.UseEnglishPrompts()
                ? "API returned an unexpected data format"
                : "API\u8fd4\u56de\u7684\u6570\u636e\u683c\u5f0f\u4e0d\u6b63\u786e");
        }

        private static bool IsConfigurationError(Exception ex)
        {
            return ex.Message.StartsWith("API\u5bc6\u94a5", StringComparison.Ordinal) ||
                ex.Message.StartsWith("API key", StringComparison.OrdinalIgnoreCase);
        }

        private sealed class ApiResponse
        {
            public Choice[] Choices { get; set; }
        }

        private sealed class Choice
        {
            public Message Message { get; set; }
        }

        private sealed class Message
        {
            public string Content { get; set; }
        }
    }
}
