using Godot;
using System;
using ChessAI.DataModels;
using ChessAI.Module.Services;

namespace ChessAI.Module.Core
{
    /// <summary>
    /// AI router. Player messages go to chat, some move/undo moments trigger proactive banter,
    /// and finished games go to review.
    /// </summary>
    public class AgentOrchestrator : IDisposable
    {
        private readonly LlmApiService _llmService;
        private readonly PromptLoader _promptLoader;
        private readonly MemoryService _memoryService;
        private readonly ChatAgent _chatAgent;
        private readonly BanterAgent _banterAgent;
        private readonly ReviewAgent _reviewAgent;
        private bool _disposed;

        public event EventHandler<AIResponseEventArgs> OnAIResponse;
        public event EventHandler<ReviewGeneratedEventArgs> OnReviewGenerated;

        public AgentOrchestrator(LlmApiService llmService, PromptLoader promptLoader, MemoryService memoryService)
        {
            _llmService = llmService;
            _promptLoader = promptLoader;
            _memoryService = memoryService;
            _chatAgent = new ChatAgent(_llmService, _promptLoader, _memoryService);
            _banterAgent = new BanterAgent(_llmService, _promptLoader, _memoryService);
            _reviewAgent = new ReviewAgent(_llmService, _promptLoader, _memoryService);

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AgentOrchestrator] AI router initialized.");
            }
        }

        public async void HandlePlayerMessage(string message, GameSession session)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AgentOrchestrator] Handling player message with fixed chat route.");
            }

            try
            {
                if (_disposed)
                {
                    return;
                }

                if (!AI_Module_Config.HasApiKey())
                {
                    RaiseAIResponse("error", ApiKeyRequiredMessage());
                    return;
                }

                var response = await _chatAgent.ProcessMessageAsync(message ?? "", session ?? new GameSession());
                RaiseAIResponse("chat", response);
            }
            catch (OperationCanceledException) when (_disposed)
            {
            }
            catch (Exception ex)
            {
                if (_disposed)
                {
                    return;
                }

                GD.PrintErr($"[AgentOrchestrator] Player message failed: {ex.Message}");
                RaiseAIResponse("error", GenericFailureMessage());
            }
        }

        public async void HandleMovePlayed(MoveRecord moveRecord, GameSession session)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AgentOrchestrator] Handling move banter trigger.");
            }

            try
            {
                if (_disposed)
                {
                    return;
                }

                var safeMove = moveRecord ?? new MoveRecord();
                var safeSession = session ?? new GameSession();

                if (safeSession.IsGameOver)
                {
                    RaiseAIResponse("none", "no_response");
                    return;
                }

                if (!BanterAgent.ShouldTriggerBanter())
                {
                    if (AI_Module_Config.DEBUG_MODE)
                    {
                        GD.Print("[AgentOrchestrator] Move banter skipped by probability.");
                    }

                    RaiseAIResponse("none", "no_response");
                    return;
                }

                if (!AI_Module_Config.HasApiKey())
                {
                    RaiseAIResponse("error", ApiKeyRequiredMessage());
                    return;
                }

                var response = await _banterAgent.ProcessMoveAsync(safeMove, safeSession);
                RaiseAIResponse("banter", response);
            }
            catch (OperationCanceledException) when (_disposed)
            {
            }
            catch (Exception ex)
            {
                if (_disposed)
                {
                    return;
                }

                GD.PrintErr($"[AgentOrchestrator] Move handling failed: {ex.Message}");
                RaiseAIResponse("error", BanterFailureMessage(ex));
            }
        }

        public async void HandleUndoPerformed(GameSession session, int undoneCount, string undoneMoveText)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AgentOrchestrator] Handling undo banter trigger.");
            }

            try
            {
                if (_disposed)
                {
                    return;
                }

                var safeSession = session ?? new GameSession();
                if (safeSession.IsGameOver)
                {
                    RaiseAIResponse("none", "no_response");
                    return;
                }

                if (!BanterAgent.ShouldTriggerBanter())
                {
                    if (AI_Module_Config.DEBUG_MODE)
                    {
                        GD.Print("[AgentOrchestrator] Undo banter skipped by probability.");
                    }

                    RaiseAIResponse("none", "no_response");
                    return;
                }

                if (!AI_Module_Config.HasApiKey())
                {
                    RaiseAIResponse("error", ApiKeyRequiredMessage());
                    return;
                }

                var response = await _banterAgent.ProcessUndoAsync(safeSession, undoneCount, undoneMoveText ?? "");
                RaiseAIResponse("banter", response);
            }
            catch (OperationCanceledException) when (_disposed)
            {
            }
            catch (Exception ex)
            {
                if (_disposed)
                {
                    return;
                }

                GD.PrintErr($"[AgentOrchestrator] Undo handling failed: {ex.Message}");
                RaiseAIResponse("error", BanterFailureMessage(ex));
            }
        }

        public async void HandleGameEnded(GameSession session, string result)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AgentOrchestrator] Handling game end with fixed review route.");
            }

            try
            {
                if (_disposed)
                {
                    return;
                }

                if (!AI_Module_Config.HasApiKey())
                {
                    RaiseAIResponse("error", ApiKeyRequiredMessage());
                    return;
                }

                var safeSession = session ?? new GameSession();
                var review = await _reviewAgent.GenerateReviewAsync(safeSession, result ?? safeSession.GameResult);
                RaiseReviewGenerated(review);
            }
            catch (OperationCanceledException) when (_disposed)
            {
            }
            catch (Exception ex)
            {
                if (_disposed)
                {
                    return;
                }

                GD.PrintErr($"[AgentOrchestrator] Game-end handling failed: {ex.Message}");
                RaiseAIResponse("error", ReviewFailureMessage(ex));
            }
        }

        public async void ArchiveCurrentGameMemory(GameSession session, string result)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AgentOrchestrator] Archiving current game memory in the background.");
            }

            try
            {
                if (_disposed)
                {
                    return;
                }

                var safeSession = session ?? new GameSession();
                result = string.IsNullOrWhiteSpace(result) ? safeSession.GameResult : result;
                safeSession.EndTime = DateTime.Now;
                safeSession.GameStatus = AI_Module_Config.UseEnglishPrompts() ? "Finished" : "结束";
                safeSession.GameResult = result;

                await _reviewAgent.ArchiveCurrentGameMemoryAsync(safeSession, result);
            }
            catch (OperationCanceledException) when (_disposed)
            {
            }
            catch (Exception ex)
            {
                if (_disposed)
                {
                    return;
                }

                GD.PrintErr($"[AgentOrchestrator] Background memory archive failed: {ex.Message}");
            }
        }

        private static string ApiKeyRequiredMessage()
        {
            return AI_Module_Config.UseEnglishPrompts()
                ? "Please enter an API key first."
                : "请先填写API密钥。";
        }

        private static string GenericFailureMessage()
        {
            return AI_Module_Config.UseEnglishPrompts()
                ? "Sorry, something went wrong. Please try again later."
                : "抱歉，我遇到了一些问题，请稍后再试。";
        }

        private static string BanterFailureMessage(Exception ex)
        {
            return AI_Module_Config.UseEnglishPrompts()
                ? $"AI banter request failed: {ex.Message}"
                : $"AI搭话请求失败: {ex.Message}";
        }

        private static string ReviewFailureMessage(Exception ex)
        {
            return AI_Module_Config.UseEnglishPrompts()
                ? $"AI review request failed: {ex.Message}"
                : $"AI复盘请求失败: {ex.Message}";
        }

        private void RaiseAIResponse(string responseType, string content)
        {
            if (_disposed)
            {
                return;
            }

            var args = new AIResponseEventArgs
            {
                ResponseType = responseType,
                Content = content,
                ShowInUI = true
            };

            OnAIResponse?.Invoke(this, args);
        }

        private void RaiseReviewGenerated(ReviewAgent.ReviewResult result)
        {
            if (_disposed || result == null)
            {
                return;
            }

            var args = new ReviewGeneratedEventArgs
            {
                ReviewContent = result.Content,
                ReviewData = result.JsonData,
                CriticalMistakes = result.CriticalMistakes
            };

            OnReviewGenerated?.Invoke(this, args);
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            OnAIResponse = null;
            OnReviewGenerated = null;
        }
    }
}
