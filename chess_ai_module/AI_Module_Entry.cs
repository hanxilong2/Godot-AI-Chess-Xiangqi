using Godot;
using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using ChessAI.DataModels;
using ChessAI.Module.Core;
using ChessAI.Module.Services;

namespace ChessAI.Module
{
    public partial class AI_Module_Entry : Node, IChessAI
    {
        [Signal]
        public delegate void AiResponseReceivedEventHandler(string responseType, string content);

        [Signal]
        public delegate void ReviewGeneratedReceivedEventHandler(string reviewContent, string reviewData);

        private LlmApiService _llmService;
        private PromptLoader _promptLoader;
        private MemoryService _memoryService;
        private ChatAgent _chatAgent;
        private BanterAgent _banterAgent;
        private ReviewAgent _reviewAgent;
        private bool _isExiting;
        private readonly JsonSerializerOptions _jsonOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            NumberHandling = JsonNumberHandling.AllowReadingFromString
        };

        public override void _Ready()
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AI_Module_Entry] Initializing AI module.");
            }

            InitializeServices();
            InitializeAgents();

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AI_Module_Entry] AI module initialized.");
            }
        }

        private void InitializeServices()
        {
            _llmService = new LlmApiService();
            _promptLoader = new PromptLoader();
            _memoryService = new MemoryService();

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AI_Module_Entry] Services initialized.");
            }
        }

        private void InitializeAgents()
        {
            _chatAgent = new ChatAgent(_llmService, _promptLoader, _memoryService);
            _banterAgent = new BanterAgent(_llmService, _promptLoader, _memoryService);
            _reviewAgent = new ReviewAgent(_llmService, _promptLoader, _memoryService);

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AI_Module_Entry] Chat, banter, and review agents initialized.");
            }
        }

        public async void OnPlayerMessage(string message, GameSession session)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AI_Module_Entry] Player chat requested.");
            }

            try
            {
                if (_isExiting)
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
            catch (OperationCanceledException) when (_isExiting)
            {
            }
            catch (ObjectDisposedException) when (_isExiting)
            {
            }
            catch (Exception ex)
            {
                if (_isExiting)
                {
                    return;
                }

                GD.PrintErr($"[AI_Module_Entry] Player chat failed: {ex.Message}");
                RaiseAIResponse("error", GenericFailureMessage());
            }
        }

        public void OnPlayerMessageJson(string message, string sessionJson)
        {
            var session = DeserializeSession(sessionJson);
            OnPlayerMessage(message, session);
        }

        public async void OnMovePlayed(MoveRecord moveRecord, GameSession session)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[AI_Module_Entry] Move banter trigger: {moveRecord?.ChineseNotation}");
            }

            try
            {
                if (_isExiting)
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
                        GD.Print("[AI_Module_Entry] Move banter skipped by probability.");
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
            catch (OperationCanceledException) when (_isExiting)
            {
            }
            catch (ObjectDisposedException) when (_isExiting)
            {
            }
            catch (Exception ex)
            {
                if (_isExiting)
                {
                    return;
                }

                GD.PrintErr($"[AI_Module_Entry] Move banter failed: {ex.Message}");
                RaiseAIResponse("error", BanterFailureMessage(ex));
            }
        }

        public void OnMovePlayedJson(string moveRecordJson, string sessionJson)
        {
            var moveRecord = DeserializeMoveRecord(moveRecordJson);
            var session = DeserializeSession(sessionJson);
            OnMovePlayed(moveRecord, session);
        }

        public async void OnUndoPerformed(GameSession session, int undoneCount, string undoneMoveText)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[AI_Module_Entry] Undo banter trigger: {undoneCount}; {undoneMoveText}");
            }

            try
            {
                if (_isExiting)
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
                        GD.Print("[AI_Module_Entry] Undo banter skipped by probability.");
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
            catch (OperationCanceledException) when (_isExiting)
            {
            }
            catch (ObjectDisposedException) when (_isExiting)
            {
            }
            catch (Exception ex)
            {
                if (_isExiting)
                {
                    return;
                }

                GD.PrintErr($"[AI_Module_Entry] Undo banter failed: {ex.Message}");
                RaiseAIResponse("error", BanterFailureMessage(ex));
            }
        }

        public void OnUndoPerformedJson(string sessionJson, int undoneCount, string undoneMoveText)
        {
            var session = DeserializeSession(sessionJson);
            OnUndoPerformed(session, undoneCount, undoneMoveText);
        }

        public async void OnGameEnded(GameSession session, string result)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[AI_Module_Entry] Review requested for finished game: {result}");
            }

            try
            {
                if (_isExiting)
                {
                    return;
                }

                var safeSession = PrepareFinishedSession(session, result);

                if (!AI_Module_Config.HasApiKey())
                {
                    RaiseAIResponse("error", ApiKeyRequiredMessage());
                    return;
                }

                var review = await _reviewAgent.GenerateReviewAsync(safeSession, result ?? safeSession.GameResult);
                RaiseReviewGenerated(review);
            }
            catch (OperationCanceledException) when (_isExiting)
            {
            }
            catch (ObjectDisposedException) when (_isExiting)
            {
            }
            catch (Exception ex)
            {
                if (_isExiting)
                {
                    return;
                }

                GD.PrintErr($"[AI_Module_Entry] Review generation failed: {ex.Message}");
                RaiseAIResponse("error", ReviewFailureMessage(ex));
            }
        }

        public void OnGameEndedJson(string sessionJson, string result)
        {
            var session = DeserializeSession(sessionJson);
            OnGameEnded(session, result);
        }

        public async void ArchiveCurrentGameMemory(GameSession session, string result)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[AI_Module_Entry] Archiving current game memory: {result}");
            }

            try
            {
                if (_isExiting)
                {
                    return;
                }

                var safeSession = PrepareFinishedSession(session, result);
                await _reviewAgent.ArchiveCurrentGameMemoryAsync(safeSession, safeSession.GameResult);
            }
            catch (OperationCanceledException) when (_isExiting)
            {
            }
            catch (ObjectDisposedException) when (_isExiting)
            {
            }
            catch (Exception ex)
            {
                if (_isExiting)
                {
                    return;
                }

                GD.PrintErr($"[AI_Module_Entry] Background memory archive failed: {ex.Message}");
            }
        }

        public void ArchiveCurrentGameMemoryJson(string sessionJson, string result)
        {
            var session = DeserializeSession(sessionJson);
            ArchiveCurrentGameMemory(session, result);
        }

        public bool IsModuleReady()
        {
            return _llmService != null &&
                _promptLoader != null &&
                _memoryService != null &&
                _chatAgent != null &&
                _banterAgent != null &&
                _reviewAgent != null;
        }

        public bool SetApiKey(string apiKey)
        {
            var saved = AI_Module_Config.SetRuntimeApiKey(apiKey, true);
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print(saved && AI_Module_Config.HasApiKey()
                    ? "[AI_Module_Entry] API key saved."
                    : "[AI_Module_Entry] API key save failed.");
            }

            return saved;
        }

        public bool ClearApiKey()
        {
            var cleared = AI_Module_Config.ClearRuntimeApiKey(true);
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print(cleared
                    ? "[AI_Module_Entry] Local API key cleared."
                    : "[AI_Module_Entry] Local API key clear failed.");
            }

            return cleared;
        }

        public string GetApiSettingsPath()
        {
            return AI_Module_Config.GetGlobalApiSettingsFilePath();
        }

        public bool ClearMemory()
        {
            return _memoryService?.ClearGlobalMemory() ?? false;
        }

        public bool ClearChessMemory()
        {
            return _memoryService?.ClearChessGlobalMemory() ?? false;
        }

        public bool ClearXiangqiMemory()
        {
            return _memoryService?.ClearXiangqiGlobalMemory() ?? false;
        }

        public bool HasApiKey()
        {
            return AI_Module_Config.HasApiKey();
        }

        public bool HasSavedApiKey()
        {
            return !string.IsNullOrWhiteSpace(AI_Module_Config.GetPersistentApiKey());
        }

        public void SetBanterPlayerSide(int playerSide)
        {
            AI_Module_Config.SetBanterPlayerSide(playerSide);
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[AI_Module_Entry] Banter side set to {AI_Module_Config.GetBanterPlayerSideName()}.");
            }
        }

        public void SetChatPlayerSide(int playerSide)
        {
            AI_Module_Config.SetChatPlayerSide(playerSide);
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[AI_Module_Entry] Chat side set to {AI_Module_Config.GetChatPlayerSideName()}.");
            }
        }

        public void SetReviewPlayerSide(int playerSide)
        {
            AI_Module_Config.SetReviewPlayerSide(playerSide);
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[AI_Module_Entry] Review side set to {AI_Module_Config.GetReviewPlayerSideName()}.");
            }
        }

        public void TestAI()
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AI_Module_Entry] TestAI OK.");
            }
        }

        public event EventHandler<AIResponseEventArgs> OnAIResponse;
        public event EventHandler<ReviewGeneratedEventArgs> OnReviewGenerated;

        public void EmitAiResponseSignal(string responseType, string content)
        {
            EmitSignal(SignalName.AiResponseReceived, responseType, content);
        }

        public void EmitReviewGeneratedSignal(string reviewContent, string reviewData)
        {
            EmitSignal(SignalName.ReviewGeneratedReceived, reviewContent, reviewData);
        }

        private GameSession PrepareFinishedSession(GameSession session, string result)
        {
            var safeSession = session ?? new GameSession();
            safeSession.EndTime = DateTime.Now;
            safeSession.GameStatus = AI_Module_Config.UseEnglishPrompts() ? "Finished" : "\u7ed3\u675f";
            safeSession.GameResult = string.IsNullOrWhiteSpace(result) ? safeSession.GameResult : result;
            return safeSession;
        }

        private void RaiseAIResponse(string responseType, string content)
        {
            if (_isExiting || !IsInsideTree())
            {
                return;
            }

            var args = new AIResponseEventArgs
            {
                ResponseType = responseType,
                Content = content ?? "",
                ShowInUI = true
            };

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[AI_Module_Entry] AI response: {args.ResponseType}");
            }

            if (AI_Module_Config.VERBOSE_CONTENT_LOGGING)
            {
                GD.Print($"[AI_Module_Entry] Content: {args.Content}");
            }

            OnAIResponse?.Invoke(this, args);
            CallDeferred(nameof(EmitAiResponseSignal), args.ResponseType, args.Content);
        }

        private void RaiseReviewGenerated(ReviewAgent.ReviewResult result)
        {
            if (_isExiting || !IsInsideTree() || result == null)
            {
                return;
            }

            var args = new ReviewGeneratedEventArgs
            {
                ReviewContent = result.Content ?? "",
                ReviewData = result.JsonData ?? "",
                CriticalMistakes = result.CriticalMistakes ?? Array.Empty<string>()
            };

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AI_Module_Entry] Review generated.");
            }

            if (AI_Module_Config.VERBOSE_CONTENT_LOGGING)
            {
                GD.Print($"[AI_Module_Entry] Review content: {args.ReviewContent}");
            }

            OnReviewGenerated?.Invoke(this, args);
            CallDeferred(nameof(EmitReviewGeneratedSignal), args.ReviewContent, args.ReviewData);
        }

        private static string ApiKeyRequiredMessage()
        {
            return AI_Module_Config.UseEnglishPrompts()
                ? "Please enter an API key first."
                : "\u8bf7\u5148\u586b\u5199 API Key\u3002";
        }

        private static string GenericFailureMessage()
        {
            return AI_Module_Config.UseEnglishPrompts()
                ? "Sorry, something went wrong. Please try again later."
                : "\u62b1\u6b49\uff0c\u6211\u9047\u5230\u4e86\u4e00\u4e9b\u95ee\u9898\uff0c\u8bf7\u7a0d\u540e\u518d\u8bd5\u3002";
        }

        private static string BanterFailureMessage(Exception ex)
        {
            return AI_Module_Config.UseEnglishPrompts()
                ? $"AI banter request failed: {ex.Message}"
                : $"AI\u642d\u8bdd\u8bf7\u6c42\u5931\u8d25: {ex.Message}";
        }

        private static string ReviewFailureMessage(Exception ex)
        {
            return AI_Module_Config.UseEnglishPrompts()
                ? $"AI review request failed: {ex.Message}"
                : $"AI\u590d\u76d8\u8bf7\u6c42\u5931\u8d25: {ex.Message}";
        }

        private GameSession DeserializeSession(string sessionJson)
        {
            if (string.IsNullOrWhiteSpace(sessionJson))
            {
                return new GameSession();
            }

            GameSession session;
            try
            {
                session = JsonSerializer.Deserialize<GameSession>(sessionJson, _jsonOptions) ?? new GameSession();
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[AI_Module_Entry] Session JSON parse failed: {ex.Message}");
                session = new GameSession();
            }

            ApplySessionJsonFallback(session, sessionJson);

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[AI_Module_Entry] Session parsed: variant={session.GameVariant}, moves={session.MoveHistory.Count}, fen={session.CurrentFEN}");
            }

            return session;
        }

        private MoveRecord DeserializeMoveRecord(string moveRecordJson)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(moveRecordJson))
                {
                    return new MoveRecord();
                }

                return JsonSerializer.Deserialize<MoveRecord>(moveRecordJson, _jsonOptions) ?? new MoveRecord();
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[AI_Module_Entry] Move JSON parse failed: {ex.Message}");
                return new MoveRecord();
            }
        }

        private void ApplySessionJsonFallback(GameSession session, string sessionJson)
        {
            try
            {
                using var document = JsonDocument.Parse(sessionJson);
                var root = document.RootElement;

                session.CurrentFEN = GetJsonString(root, session.CurrentFEN, "CurrentFEN", "current_fen");
                session.InitialFEN = GetJsonString(root, session.InitialFEN, "InitialFEN", "initial_fen");
                session.GameVariant = GetJsonString(root, session.GameVariant, "GameVariant", "game_variant");
                session.GameStatus = GetJsonString(root, session.GameStatus, "GameStatus", "game_status");
                session.GameResult = GetJsonString(root, session.GameResult, "GameResult", "game_result");
                session.GameEndType = GetJsonString(root, session.GameEndType, "GameEndType", "game_end_type");
                session.TimeControl = GetJsonString(root, session.TimeControl, "TimeControl", "time_control");
                session.TimeControlDescription = GetJsonString(root, session.TimeControlDescription, "TimeControlDescription", "time_control_description");
                session.WhiteClockRemaining = GetJsonString(root, session.WhiteClockRemaining, "WhiteClockRemaining", "white_clock_remaining");
                session.BlackClockRemaining = GetJsonString(root, session.BlackClockRemaining, "BlackClockRemaining", "black_clock_remaining");
                session.SessionId = GetJsonString(root, session.SessionId, "SessionId", "session_id");

                session.CurrentPlayer = GetJsonInt(root, session.CurrentPlayer, "CurrentPlayer", "current_player");
                session.HumanSide = GetJsonInt(root, session.HumanSide, "HumanSide", "human_side");
                session.HalfmoveClock = GetJsonInt(root, session.HalfmoveClock, "HalfmoveClock", "halfmove_clock");
                session.FullmoveNumber = GetJsonInt(root, session.FullmoveNumber, "FullmoveNumber", "fullmove_number");
                session.ClockActiveSide = GetJsonInt(root, session.ClockActiveSide, "ClockActiveSide", "clock_active_side");

                session.ClockInitialSeconds = GetJsonDouble(root, session.ClockInitialSeconds, "ClockInitialSeconds", "clock_initial_seconds");
                session.ClockIncrementSeconds = GetJsonDouble(root, session.ClockIncrementSeconds, "ClockIncrementSeconds", "clock_increment_seconds");
                session.WhiteClockRemainingSeconds = GetJsonDouble(root, session.WhiteClockRemainingSeconds, "WhiteClockRemainingSeconds", "white_clock_remaining_seconds");
                session.BlackClockRemainingSeconds = GetJsonDouble(root, session.BlackClockRemainingSeconds, "BlackClockRemainingSeconds", "black_clock_remaining_seconds");

                session.AIEnabled = GetJsonBool(root, session.AIEnabled, "AIEnabled", "ai_enabled");
                session.ClockRunning = GetJsonBool(root, session.ClockRunning, "ClockRunning", "clock_running");

                if (TryGetJsonProperty(root, out var boardElement, "Board", "board") && boardElement.ValueKind == JsonValueKind.Array)
                {
                    var board = new List<string>();
                    foreach (var item in boardElement.EnumerateArray())
                    {
                        board.Add(ReadJsonString(item, ""));
                    }
                    session.Board = board.ToArray();
                }

                if (TryGetJsonProperty(root, out var movesElement, "MoveHistory", "moves", "move_history") && movesElement.ValueKind == JsonValueKind.Array)
                {
                    var moves = new List<MoveRecord>();
                    foreach (var moveElement in movesElement.EnumerateArray())
                    {
                        if (moveElement.ValueKind == JsonValueKind.Object)
                        {
                            moves.Add(ParseMoveRecord(moveElement));
                        }
                    }

                    session.MoveHistory = moves;
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[AI_Module_Entry] Session fallback parse failed: {ex.Message}");
            }
        }

        private MoveRecord ParseMoveRecord(JsonElement element)
        {
            return new MoveRecord
            {
                FromIndex = GetJsonInt(element, -1, "FromIndex", "from_index"),
                ToIndex = GetJsonInt(element, -1, "ToIndex", "to_index"),
                Piece = GetJsonString(element, "", "Piece", "piece"),
                CapturedPiece = GetJsonString(element, "", "CapturedPiece", "captured_piece"),
                Flags = GetJsonInt(element, 0, "Flags", "flags"),
                ChineseNotation = GetJsonString(element, "", "ChineseNotation", "chinese_notation"),
                CoordinateNotation = GetJsonString(element, "", "CoordinateNotation", "coordinate_notation"),
                Side = GetJsonInt(element, 0, "Side", "side"),
                PlyIndex = GetJsonInt(element, 0, "PlyIndex", "ply_index"),
                MoveNumber = GetJsonInt(element, 1, "MoveNumber", "move_number"),
                EvaluationScore = GetJsonInt(element, 0, "EvaluationScore", "evaluation_score"),
                TeachingScore = GetJsonInt(element, 0, "TeachingScore", "teaching_score", "teachingScore"),
                BestMove = GetJsonString(element, "", "BestMove", "best_move"),
                PikafishAnalysis = GetJsonObject(element, "PikafishAnalysis", "pikafish_analysis")
            };
        }

        private static bool TryGetJsonProperty(JsonElement element, out JsonElement value, params string[] names)
        {
            if (element.ValueKind == JsonValueKind.Object)
            {
                foreach (var property in element.EnumerateObject())
                {
                    foreach (var name in names)
                    {
                        if (string.Equals(property.Name, name, StringComparison.OrdinalIgnoreCase))
                        {
                            value = property.Value;
                            return true;
                        }
                    }
                }
            }

            value = default;
            return false;
        }

        private static string GetJsonString(JsonElement element, string fallback, params string[] names)
        {
            return TryGetJsonProperty(element, out var value, names) ? ReadJsonString(value, fallback) : fallback;
        }

        private static string ReadJsonString(JsonElement value, string fallback)
        {
            return value.ValueKind switch
            {
                JsonValueKind.String => value.GetString() ?? fallback,
                JsonValueKind.Number => value.GetRawText(),
                JsonValueKind.True => "true",
                JsonValueKind.False => "false",
                _ => fallback
            };
        }

        private static int GetJsonInt(JsonElement element, int fallback, params string[] names)
        {
            if (!TryGetJsonProperty(element, out var value, names))
            {
                return fallback;
            }

            if (value.ValueKind == JsonValueKind.Number)
            {
                if (value.TryGetInt32(out var intValue))
                {
                    return intValue;
                }
                if (value.TryGetDouble(out var doubleValue))
                {
                    return (int)Math.Round(doubleValue);
                }
            }

            if (value.ValueKind == JsonValueKind.String && int.TryParse(value.GetString(), out var parsed))
            {
                return parsed;
            }

            return fallback;
        }

        private static double GetJsonDouble(JsonElement element, double fallback, params string[] names)
        {
            if (!TryGetJsonProperty(element, out var value, names))
            {
                return fallback;
            }

            if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var doubleValue))
            {
                return doubleValue;
            }

            if (value.ValueKind == JsonValueKind.String && double.TryParse(value.GetString(), out var parsed))
            {
                return parsed;
            }

            return fallback;
        }

        private static bool GetJsonBool(JsonElement element, bool fallback, params string[] names)
        {
            if (!TryGetJsonProperty(element, out var value, names))
            {
                return fallback;
            }

            if (value.ValueKind == JsonValueKind.True)
            {
                return true;
            }
            if (value.ValueKind == JsonValueKind.False)
            {
                return false;
            }
            if (value.ValueKind == JsonValueKind.String && bool.TryParse(value.GetString(), out var parsed))
            {
                return parsed;
            }

            return fallback;
        }

        private static Dictionary<string, object> GetJsonObject(JsonElement element, params string[] names)
        {
            if (!TryGetJsonProperty(element, out var value, names) || value.ValueKind != JsonValueKind.Object)
            {
                return new Dictionary<string, object>();
            }

            return ReadJsonObject(value);
        }

        private static Dictionary<string, object> ReadJsonObject(JsonElement element)
        {
            var result = new Dictionary<string, object>();
            foreach (var property in element.EnumerateObject())
            {
                result[property.Name] = ReadJsonValue(property.Value);
            }

            return result;
        }

        private static object ReadJsonValue(JsonElement value)
        {
            return value.ValueKind switch
            {
                JsonValueKind.Object => ReadJsonObject(value),
                JsonValueKind.Array => ReadJsonArray(value),
                JsonValueKind.String => value.GetString() ?? "",
                JsonValueKind.Number => value.TryGetInt64(out var longValue)
                    ? longValue
                    : value.TryGetDouble(out var doubleValue)
                        ? doubleValue
                        : value.GetRawText(),
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                _ => null
            };
        }

        private static List<object> ReadJsonArray(JsonElement element)
        {
            var result = new List<object>();
            foreach (var item in element.EnumerateArray())
            {
                result.Add(ReadJsonValue(item));
            }

            return result;
        }

        public override void _ExitTree()
        {
            _isExiting = true;
            _chatAgent = null;
            _banterAgent = null;
            _reviewAgent = null;
            _llmService?.Dispose();
            _llmService = null;
            _promptLoader = null;
            _memoryService = null;
            OnAIResponse = null;
            OnReviewGenerated = null;

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[AI_Module_Entry] AI module exited.");
            }
        }
    }
}
