using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace ChessAI.Module.Services
{
    public sealed class ChatToolDefinition
    {
        public ChatToolDefinition(string name, string description, object parameters)
        {
            Name = name;
            Description = description;
            Parameters = parameters;
        }

        public string Name { get; }
        public string Description { get; }
        public object Parameters { get; }

        public object ToApiShape()
        {
            return new
            {
                type = "function",
                function = new
                {
                    name = Name,
                    description = Description,
                    parameters = Parameters
                }
            };
        }
    }

    public sealed class ToolCallDecision
    {
        public string ToolName { get; set; } = "";
        public string ArgumentsJson { get; set; } = "";
        public string Content { get; set; } = "";

        public bool HasToolCall => !string.IsNullOrWhiteSpace(ToolName);
    }

    /// <summary>
    /// LLM API service. Wraps OpenAI-compatible DashScope chat completions.
    /// </summary>
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
                GD.Print("[LlmApiService] Sending chat completion request...");
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
                            : $"API请求失败，已重试{AI_Module_Config.API_RETRY_COUNT}次";
                        throw new Exception(message, ex);
                    }
                }
            }

            return "";
        }

        public async Task<ToolCallDecision> SelectToolAsync(
            string systemPrompt,
            string userPrompt,
            IReadOnlyList<ChatToolDefinition> tools,
            string modelName = null,
            int maxTokens = -1)
        {
            ThrowIfDisposed();

            if (tools == null || tools.Count == 0)
            {
                throw new ArgumentException("At least one tool definition is required.", nameof(tools));
            }

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[LlmApiService] Sending tool-selection request...");
                GD.Print($"[LlmApiService] Model: {modelName ?? AI_Module_Config.AGENT_MODEL}");
                GD.Print($"[LlmApiService] Tools: {string.Join(", ", tools.Select(tool => tool.Name))}");
            }

            if (AI_Module_Config.VERBOSE_CONTENT_LOGGING)
            {
                GD.Print($"[LlmApiService] User Prompt: {Preview(userPrompt)}");
            }

            for (int retry = 0; retry < AI_Module_Config.API_RETRY_COUNT; retry++)
            {
                try
                {
                    return await SendToolSelectionRequestAsync(systemPrompt, userPrompt, tools, modelName, maxTokens, _shutdownCts.Token);
                }
                catch (OperationCanceledException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    GD.PrintErr($"[LlmApiService] Tool-selection request failed ({retry + 1}/{AI_Module_Config.API_RETRY_COUNT}): {ex.Message}");

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
                            ? $"Tool-selection request failed after {AI_Module_Config.API_RETRY_COUNT} retries"
                            : $"Agent工具选择请求失败，已重试{AI_Module_Config.API_RETRY_COUNT}次";
                        throw new Exception(message, ex);
                    }
                }
            }

            return new ToolCallDecision();
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

        private async Task<string> SendRequestAsync(string systemPrompt, string userPrompt, string modelName = null, int maxTokens = -1, CancellationToken cancellationToken = default)
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

        private async Task<ToolCallDecision> SendToolSelectionRequestAsync(
            string systemPrompt,
            string userPrompt,
            IReadOnlyList<ChatToolDefinition> tools,
            string modelName = null,
            int maxTokens = -1,
            CancellationToken cancellationToken = default)
        {
            var requestBody = new
            {
                model = modelName ?? AI_Module_Config.AGENT_MODEL,
                messages = new[]
                {
                    new { role = "system", content = systemPrompt },
                    new { role = "user", content = userPrompt }
                },
                tools = tools.Select(tool => tool.ToApiShape()).ToArray(),
                tool_choice = "auto",
                temperature = AI_Module_Config.AGENT_TEMPERATURE,
                max_tokens = maxTokens > 0 ? maxTokens : AI_Module_Config.AGENT_MAX_TOKENS,
                enable_thinking = false,
                stream = false
            };

            var responseData = await SendChatRequestAsync(requestBody, cancellationToken);
            if (responseData?.Choices?.Length <= 0 || responseData.Choices[0].Message == null)
            {
                throw UnexpectedFormatException();
            }

            var message = responseData.Choices[0].Message;
            var cleanContent = StripThinkingBlocks(message.Content ?? "");
            var toolCall = message.ToolCalls?.FirstOrDefault(call => call?.Function != null);
            if (toolCall?.Function != null)
            {
                return new ToolCallDecision
                {
                    ToolName = toolCall.Function.Name ?? "",
                    ArgumentsJson = ReadArgumentsJson(toolCall.Function.Arguments),
                    Content = cleanContent
                };
            }

            if (message.FunctionCall != null)
            {
                return new ToolCallDecision
                {
                    ToolName = message.FunctionCall.Name ?? "",
                    ArgumentsJson = ReadArgumentsJson(message.FunctionCall.Arguments),
                    Content = cleanContent
                };
            }

            return new ToolCallDecision
            {
                Content = cleanContent
            };
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
                    : $"API返回错误: {(int)response.StatusCode} {response.ReasonPhrase}; {responseContent}";
                throw new Exception(message);
            }

            return JsonSerializer.Deserialize<ApiResponse>(responseContent, _jsonOptions);
        }

        private static string ReadArgumentsJson(JsonElement arguments)
        {
            return arguments.ValueKind switch
            {
                JsonValueKind.String => arguments.GetString() ?? "",
                JsonValueKind.Undefined => "",
                JsonValueKind.Null => "",
                _ => arguments.GetRawText()
            };
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
                : "API返回的数据格式不正确");
        }

        private static bool IsConfigurationError(Exception ex)
        {
            return ex.Message.StartsWith("API密钥", StringComparison.Ordinal) ||
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
            public ToolCall[] ToolCalls { get; set; }
            public FunctionCall FunctionCall { get; set; }
        }

        private sealed class ToolCall
        {
            public string Type { get; set; }
            public FunctionCall Function { get; set; }
        }

        private sealed class FunctionCall
        {
            public string Name { get; set; }
            public JsonElement Arguments { get; set; }
        }
    }
}
