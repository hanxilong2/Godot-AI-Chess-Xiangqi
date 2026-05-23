using Godot;
using System;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using ChessAI.DataModels;
using ChessAI.Module.Services;

namespace ChessAI.Module.Core
{
    public class ReviewAgent
    {
        private readonly LlmApiService _llmService;
        private readonly PromptLoader _promptLoader;
        private readonly MemoryService _memoryService;

        public ReviewAgent(LlmApiService llmService, PromptLoader promptLoader, MemoryService memoryService)
        {
            _llmService = llmService;
            _promptLoader = promptLoader;
            _memoryService = memoryService;
        }

        public class ReviewResult
        {
            public string Content { get; set; }
            public string JsonData { get; set; }
            public string[] CriticalMistakes { get; set; }
        }

        public async Task<ReviewResult> GenerateReviewAsync(GameSession session, string result)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[ReviewAgent] Generating review report");
            }

            var systemPrompt = _promptLoader.LoadReviewPrompt();
            var memoryPrompt = _memoryService?.BuildPromptMemory(session) ?? "";
            var userPrompt = BuildUserPrompt(session, result, memoryPrompt);
            var response = await _llmService.CompleteChatAsync(systemPrompt, userPrompt, AI_Module_Config.REVIEW_MODEL);
            var reviewResult = ParseReviewResponse(response);
            _memoryService?.RecordAIResponse(session, "review", "", reviewResult.Content, $"Game result: {result}");

            if (ShouldStoreGlobalMemory(session, result))
            {
                var currentGameMemory = _memoryService?.LoadCurrentGameMemoryMarkdown() ?? "";
                _ = SaveGlobalMemoryAsync(session, result, reviewResult, currentGameMemory);
            }

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[ReviewAgent] Review report generated");
                GD.Print($"[ReviewAgent] Critical mistake count: {reviewResult.CriticalMistakes.Length}");
            }

            return reviewResult;
        }

        public async Task ArchiveCurrentGameMemoryAsync(GameSession session, string result)
        {
            if (_memoryService == null)
            {
                return;
            }

            session ??= new GameSession();
            result = string.IsNullOrWhiteSpace(result) ? session.GameResult : result;

            _memoryService.UpdateCurrentGameMemory(session);
            var currentGameMemory = _memoryService.LoadCurrentGameMemoryMarkdown();

            var archiveNote = AI_Module_Config.UseEnglishPrompts()
                ? "The player actively left this game. No visible review was generated; summarize the Current Game Memory directly."
                : "玩家主动离开本局。没有生成可见复盘，请直接根据 Current Game Memory 总结。";
            var reviewResult = new ReviewResult
            {
                Content = archiveNote,
                JsonData = "",
                CriticalMistakes = Array.Empty<string>()
            };

            if (!AI_Module_Config.HasApiKey())
            {
                ClearCurrentMemoryAfterGlobalWrite(session, result, "");
                return;
            }

            await SaveGlobalMemoryAsync(session, result, reviewResult, currentGameMemory);
        }

        private string BuildUserPrompt(GameSession session, string result, string memoryPrompt)
        {
            return AI_Module_Config.UseEnglishPrompts()
                ? BuildEnglishUserPrompt(session, result, memoryPrompt)
                : BuildChineseUserPrompt(session, result, memoryPrompt);
        }

        private string BuildEnglishUserPrompt(GameSession session, string result, string memoryPrompt)
        {
            var promptBuilder = new System.Text.StringBuilder();
            var whiteClock = string.IsNullOrWhiteSpace(session.WhiteClockRemaining)
                ? FormatClockSeconds(session.WhiteClockRemainingSeconds)
                : session.WhiteClockRemaining;
            var blackClock = string.IsNullOrWhiteSpace(session.BlackClockRemaining)
                ? FormatClockSeconds(session.BlackClockRemainingSeconds)
                : session.BlackClockRemaining;
            var activeClock = session.ClockActiveSide == 0
                ? SideName(0, session)
                : session.ClockActiveSide == 1
                    ? SideName(1, session)
                    : "paused";
            var durationMinutes = EstimateDurationMinutes(session);
            var endType = NormalizeGameEndType(session.GameEndType);

            promptBuilder.AppendLine("Game basics:");
            promptBuilder.AppendLine($"- Variant: {session.GameVariant}");
            promptBuilder.AppendLine($"- Result: {NormalizeResult(result)}");
            if (!string.IsNullOrWhiteSpace(endType))
            {
                promptBuilder.AppendLine($"- End type: {endType}");
            }
            promptBuilder.AppendLine($"- Human side: {SideName(session.HumanSide, session)}");
            promptBuilder.AppendLine($"- Duration: {durationMinutes:F1} minutes");
            promptBuilder.AppendLine($"- Total plies: {session.GetMoveCount()}");
            promptBuilder.AppendLine($"- {SideName(0, session)} plies: {session.GetSideMoveCount(0)}");
            promptBuilder.AppendLine($"- {SideName(1, session)} plies: {session.GetSideMoveCount(1)}");

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("Clock:");
            promptBuilder.AppendLine($"- Time control: {session.TimeControl}");
            promptBuilder.AppendLine($"- Rule: {session.TimeControlDescription}");
            promptBuilder.AppendLine($"- Initial seconds: {session.ClockInitialSeconds:F0}");
            promptBuilder.AppendLine($"- Increment seconds per completed move: {session.ClockIncrementSeconds:F0}");
            promptBuilder.AppendLine($"- White remaining: {whiteClock} ({session.WhiteClockRemainingSeconds:F1}s)");
            promptBuilder.AppendLine($"- Black remaining: {blackClock} ({session.BlackClockRemainingSeconds:F1}s)");
            promptBuilder.AppendLine($"- Active clock: {activeClock}");
            promptBuilder.AppendLine($"- Clock running: {session.ClockRunning}");

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("Complete move list:");
            var fallbackPly = 1;
            foreach (var move in session.MoveHistory)
            {
                var ply = move.PlyIndex > 0 ? move.PlyIndex : fallbackPly;
                var notation = !string.IsNullOrWhiteSpace(move.ChineseNotation)
                    ? move.ChineseNotation
                    : move.CoordinateNotation;
                var captured = string.IsNullOrWhiteSpace(move.CapturedPiece) ? "-" : move.CapturedPiece;
                var bestMove = string.IsNullOrWhiteSpace(move.BestMove) ? "-" : move.BestMove;
                promptBuilder.AppendLine(
                    $"  Ply {ply}, move {move.MoveNumber}, {SideName(move.Side, session)}: {notation}; " +
                    $"coordinate={move.CoordinateNotation}; piece={move.Piece}; captured={captured}; " +
                    $"flags={move.Flags}; eval={move.EvaluationScore}; best={bestMove}");
                fallbackPly++;
            }

            MemoryService.AppendMemoryPrompt(promptBuilder, memoryPrompt);

            promptBuilder.AppendLine();
            if (IsInternationalChess(session))
            {
                promptBuilder.AppendLine("Please reply in one natural English paragraph, like a strong close friend seriously and calmly reviewing this chess game. No title, bullet list, numbering, or Markdown. Do not use roasts, sarcasm, memes, or jokes. Keep it conversational, professional, alive and human, around 230 to 320 words.");
            }
            else
            {
                promptBuilder.AppendLine("Please reply in one natural English paragraph, like a strong close friend seriously and calmly reviewing this game. No title, bullet list, numbering, or Markdown. Do not use roasts, sarcasm, memes, or jokes. Keep it conversational, professional, alive and human, around 230 to 320 words.");
            }

            return promptBuilder.ToString();
        }

        private string BuildChineseUserPrompt(GameSession session, string result, string memoryPrompt)
        {
            var promptBuilder = new System.Text.StringBuilder();
            var whiteClock = string.IsNullOrWhiteSpace(session.WhiteClockRemaining)
                ? FormatClockSeconds(session.WhiteClockRemainingSeconds)
                : session.WhiteClockRemaining;
            var blackClock = string.IsNullOrWhiteSpace(session.BlackClockRemaining)
                ? FormatClockSeconds(session.BlackClockRemainingSeconds)
                : session.BlackClockRemaining;
            var activeClock = session.ClockActiveSide == 0
                ? session.GetSideName(0)
                : session.ClockActiveSide == 1
                    ? session.GetSideName(1)
                    : "暂停";
            var durationMinutes = EstimateDurationMinutes(session);
            var endType = NormalizeGameEndType(session.GameEndType);
            if (!string.IsNullOrWhiteSpace(endType))
            {
                promptBuilder.AppendLine($"End type: {endType}");
            }

            promptBuilder.AppendLine("对局基本信息：");
            promptBuilder.AppendLine($"- 棋种：{session.GameVariant}");
            promptBuilder.AppendLine($"- 结果：{result}");
            promptBuilder.AppendLine($"- 玩家执：{session.GetSideName(session.HumanSide)}");
            promptBuilder.AppendLine($"- 用时：{durationMinutes:F1} 分钟");
            promptBuilder.AppendLine($"- 总手数：{session.GetMoveCount()}");
            promptBuilder.AppendLine($"- {session.GetSideName(0)}手数：{session.GetSideMoveCount(0)}");
            promptBuilder.AppendLine($"- {session.GetSideName(1)}手数：{session.GetSideMoveCount(1)}");

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("棋钟：");
            promptBuilder.AppendLine($"- 计时：{session.TimeControl}");
            promptBuilder.AppendLine($"- 规则：{session.TimeControlDescription}");
            promptBuilder.AppendLine($"- 初始秒数：{session.ClockInitialSeconds:F0}");
            promptBuilder.AppendLine($"- 每步加秒：{session.ClockIncrementSeconds:F0}");
            promptBuilder.AppendLine($"- 白方剩余：{whiteClock}（{session.WhiteClockRemainingSeconds:F1} 秒）");
            promptBuilder.AppendLine($"- 黑方剩余：{blackClock}（{session.BlackClockRemainingSeconds:F1} 秒）");
            promptBuilder.AppendLine($"- 当前计时方：{activeClock}");
            promptBuilder.AppendLine($"- 棋钟运行中：{session.ClockRunning}");

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("完整走法：");
            var fallbackPly = 1;
            foreach (var move in session.MoveHistory)
            {
                var ply = move.PlyIndex > 0 ? move.PlyIndex : fallbackPly;
                var notation = !string.IsNullOrWhiteSpace(move.ChineseNotation)
                    ? move.ChineseNotation
                    : move.CoordinateNotation;
                var captured = string.IsNullOrWhiteSpace(move.CapturedPiece) ? "-" : move.CapturedPiece;
                var bestMove = string.IsNullOrWhiteSpace(move.BestMove) ? "-" : move.BestMove;
                promptBuilder.AppendLine(
                    $"  第 {ply} 手，第 {move.MoveNumber} 回合，{session.GetSideName(move.Side)}：{notation}；" +
                    $"坐标={move.CoordinateNotation}；棋子={move.Piece}；吃子={captured}；" +
                    $"标记={move.Flags}；评估={move.EvaluationScore}；最佳={bestMove}");
                fallbackPly++;
            }

            promptBuilder.AppendLine();
            if (IsInternationalChess(session))
            {
                promptBuilder.AppendLine("请只输出一个自然段，像关系很好的强棋力朋友在认真、理智、专业地复盘这盘国际象棋。不要标题、列表、编号或 Markdown，不要吐槽、反讽、玩梗或讲冷笑话；用现代口语，要求有活人感，控制在350到450个汉字左右。");
            }
            else
            {
                promptBuilder.AppendLine("请只输出一个自然段，像关系很好的强棋力朋友在认真、理智、专业地复盘这盘棋。不要标题、列表、编号或 Markdown，不要吐槽、反讽、玩梗或讲冷笑话；用现代口语，要求有活人感，控制在350到450个汉字左右。");
            }

            MemoryService.AppendMemoryPrompt(promptBuilder, memoryPrompt);

            return promptBuilder.ToString();
        }

        private async Task SaveGlobalMemoryAsync(GameSession session, string result, ReviewResult reviewResult, string currentGameMemory)
        {
            if (_memoryService == null)
            {
                return;
            }

            try
            {
                if (string.IsNullOrWhiteSpace(currentGameMemory))
                {
                    currentGameMemory = _memoryService.LoadCurrentGameMemoryMarkdown();
                }

                var memoryEntry = await _llmService.CompleteChatAsync(
                    BuildMemorySummarySystemPrompt(session),
                    BuildMemorySummaryUserPrompt(session, result, reviewResult, currentGameMemory),
                    AI_Module_Config.CHAT_MODEL,
                    AI_Module_Config.MEMORY_SUMMARY_MAX_TOKENS);

                ClearCurrentMemoryAfterGlobalWrite(session, result, memoryEntry);
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[ReviewAgent] Failed to generate global memory entry: {ex.Message}");
                ClearCurrentMemoryAfterGlobalWrite(session, result, "");
            }
        }

        private void ClearCurrentMemoryAfterGlobalWrite(GameSession session, string result, string memoryEntry)
        {
            if (_memoryService?.AddGlobalGameMemory(session, result, memoryEntry) == true)
            {
                _memoryService.ClearCurrentGameMemory(session);
            }
        }

        private static bool ShouldStoreGlobalMemory(GameSession session, string result)
        {
            if (session?.IsGameOver == true)
            {
                return true;
            }

            if (string.IsNullOrWhiteSpace(result))
            {
                return false;
            }

            return !result.Contains("not finished", StringComparison.OrdinalIgnoreCase) &&
                !result.Contains("in progress", StringComparison.OrdinalIgnoreCase) &&
                !result.Contains("\u672a\u7ed3\u675f", StringComparison.Ordinal);
        }

        private static string BuildMemorySummarySystemPrompt(GameSession session)
        {
            var isInternationalChess = IsInternationalChess(session);
            if (AI_Module_Config.UseEnglishPrompts())
            {
                var companion = isInternationalChess ? "a chess companion" : "a Xiangqi companion";
                return $"You maintain long-term memory for {companion}. Based on the finished game and review, write exactly one compact Markdown memory entry. Use this template only:\n" +
                    "### yyyy-MM-dd | result\n" +
                    "- Outcome: ...\n" +
                    "- Style: ...\n" +
                    "- Weakness: ...\n" +
                    "- Next reminder: ...\n" +
                    "The title result and Outcome must use the player-perspective result label supplied by the user prompt, such as Player Black won or Player Red lost, not only side-wins labels. Summarize the Current Game Memory document, including board evidence and AI-player interactions when useful. Keep it concise, around 130 to 170 English words. Include the result, playing style, obvious weaknesses, and one next-game reminder. No extra sections, JSON, code fences, or commentary.";
            }

            var localizedCompanion = isInternationalChess ? "an international chess companion" : "a Xiangqi companion";
            return $"You maintain long-term memory for {localizedCompanion}. Based on the finished game and review, write exactly one compact Simplified Chinese Markdown memory entry. Use this template only, around 280 to 330 Chinese characters total:\n" +
                "### yyyy-MM-dd | result\n" +
                "- \u80dc\u8d1f: ...\n" +
                "- \u98ce\u683c: ...\n" +
                "- \u5f31\u70b9: ...\n" +
                "- \u4e0b\u6b21\u63d0\u9192: ...\n" +
                "The title result and \u80dc\u8d1f line must use the supplied player-perspective result label, such as \u73a9\u5bb6\u9ed1\u65b9\u80dc\u5229 or \u73a9\u5bb6\u7ea2\u65b9\u5931\u8d25, not only \u7ea2\u65b9/\u9ed1\u65b9\u80dc\u5229 labels. Summarize the Current Game Memory document, including board evidence and AI-player interactions when useful. It must include outcome, playing style, obvious weaknesses, and one next-game reminder. No extra sections, JSON, code fences, or commentary.";
        }

        private static string BuildMemorySummaryUserPrompt(GameSession session, string result, ReviewResult reviewResult, string currentGameMemory)
        {
            session ??= new GameSession();
            var promptBuilder = new System.Text.StringBuilder();
            var rawResult = string.IsNullOrWhiteSpace(result) ? session.GameResult : result;
            var titleResult = BuildMemoryResultLabel(session, rawResult);

            promptBuilder.AppendLine($"Use this entry title: ### {DateTime.Now:yyyy-MM-dd} | {CleanForPrompt(titleResult)}");
            promptBuilder.AppendLine();
            promptBuilder.AppendLine("Current Game Memory document to summarize:");
            promptBuilder.AppendLine(string.IsNullOrWhiteSpace(currentGameMemory) ? "(empty)" : currentGameMemory);
            promptBuilder.AppendLine();
            promptBuilder.AppendLine("Finished game data:");
            promptBuilder.AppendLine($"- Session id: {CleanForPrompt(session.SessionId)}");
            promptBuilder.AppendLine($"- Variant: {CleanForPrompt(session.GameVariant)}");
            promptBuilder.AppendLine($"- Result: {CleanForPrompt(rawResult)}");
            promptBuilder.AppendLine($"- Player result label: {CleanForPrompt(titleResult)}");
            var endType = NormalizeGameEndType(session.GameEndType);
            if (!string.IsNullOrWhiteSpace(endType))
            {
                promptBuilder.AppendLine($"- End type: {CleanForPrompt(endType)}");
            }
            promptBuilder.AppendLine($"- Human side: {CleanForPrompt(session.GetSideName(session.HumanSide))} ({session.HumanSide})");
            promptBuilder.AppendLine($"- Total plies: {session.GetMoveCount()}");
            promptBuilder.AppendLine($"- Side 0 plies: {session.GetSideMoveCount(0)}");
            promptBuilder.AppendLine($"- Side 1 plies: {session.GetSideMoveCount(1)}");
            promptBuilder.AppendLine($"- Duration minutes: {EstimateDurationMinutes(session):F1}");

            AppendMemorySummaryMoveEvidence(promptBuilder, session);

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("Review content:");
            promptBuilder.AppendLine(reviewResult?.Content ?? "");

            if (reviewResult?.CriticalMistakes?.Length > 0)
            {
                promptBuilder.AppendLine();
                promptBuilder.AppendLine("Detected critical mistake lines:");
                foreach (var mistake in reviewResult.CriticalMistakes.Take(8))
                {
                    promptBuilder.AppendLine($"- {CleanForPrompt(mistake)}");
                }
            }

            return promptBuilder.ToString();
        }

        private static void AppendMemorySummaryMoveEvidence(System.Text.StringBuilder promptBuilder, GameSession session)
        {
            var moves = session?.MoveHistory ?? new System.Collections.Generic.List<MoveRecord>();
            if (moves.Count == 0)
            {
                return;
            }

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("Opening and ending samples:");
            foreach (var move in moves.Take(6).Concat(moves.Skip(Math.Max(0, moves.Count - 6))))
            {
                promptBuilder.AppendLine(FormatMemoryMoveLine(move, session));
            }

            var notableMoves = moves
                .Where(move => move != null && Math.Abs(move.EvaluationScore) >= 100)
                .OrderByDescending(move => Math.Abs(move.EvaluationScore))
                .Take(8)
                .ToList();

            if (notableMoves.Count == 0)
            {
                return;
            }

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("Largest eval-loss moves:");
            foreach (var move in notableMoves)
            {
                promptBuilder.AppendLine(FormatMemoryMoveLine(move, session));
            }
        }

        private static string FormatMemoryMoveLine(MoveRecord move, GameSession session)
        {
            move ??= new MoveRecord();
            var notation = !string.IsNullOrWhiteSpace(move.ChineseNotation)
                ? move.ChineseNotation
                : move.CoordinateNotation;
            var bestMove = string.IsNullOrWhiteSpace(move.BestMove) ? "-" : move.BestMove;
            var ply = move.PlyIndex > 0 ? move.PlyIndex : Math.Max(1, move.MoveNumber * 2 - (move.Side == 0 ? 1 : 0));

            return $"- Ply {ply}; side={CleanForPrompt(session.GetSideName(move.Side))}; move={CleanForPrompt(notation)}; eval_loss={move.EvaluationScore}; best={CleanForPrompt(bestMove)}";
        }

        private static string BuildMemoryResultLabel(GameSession session, string result)
        {
            session ??= new GameSession();
            var cleanResult = CleanForPrompt(string.IsNullOrWhiteSpace(result) ? session.GameResult : result);
            var humanSide = NormalizeSide(session.HumanSide);
            var winningSide = DetermineWinningSide(session, cleanResult);

            if (AI_Module_Config.UseEnglishPrompts())
            {
                var sideName = SideName(humanSide, session);
                var outcome = winningSide.HasValue
                    ? (winningSide.Value == humanSide ? "won" : "lost")
                    : IsDrawResult(cleanResult)
                        ? "drew"
                        : IsLeftResult(cleanResult)
                            ? "left"
                            : "result";
                var label = $"Player {sideName} {outcome}";
                return AppendRawResultLabel(label, cleanResult, false);
            }

            var playerSideName = session.GetSideName(humanSide);
            var playerOutcome = winningSide.HasValue
                ? (winningSide.Value == humanSide ? "\u80dc\u5229" : "\u5931\u8d25")
                : IsDrawResult(cleanResult)
                    ? "\u548c\u68cb"
                    : IsLeftResult(cleanResult)
                        ? "\u4e3b\u52a8\u79bb\u5f00"
                        : "\u7ed3\u679c";
            var playerLabel = $"\u73a9\u5bb6{playerSideName}{playerOutcome}";
            return AppendRawResultLabel(playerLabel, cleanResult, true);
        }

        private static string AppendRawResultLabel(string playerLabel, string rawResult, bool useChineseParentheses)
        {
            if (string.IsNullOrWhiteSpace(rawResult) ||
                string.Equals(playerLabel, rawResult, StringComparison.OrdinalIgnoreCase))
            {
                return playerLabel;
            }

            return useChineseParentheses
                ? $"{playerLabel}\uff08{rawResult}\uff09"
                : $"{playerLabel} ({rawResult})";
        }

        private static int NormalizeSide(int side)
        {
            return side == 1 ? 1 : 0;
        }

        private static int? DetermineWinningSide(GameSession session, string result)
        {
            var endTypeWinner = DetermineWinnerFromEndType(session?.GameEndType);
            if (endTypeWinner.HasValue)
            {
                return endTypeWinner.Value;
            }

            var clean = result ?? "";
            if (IsDrawResult(clean))
            {
                return null;
            }

            if (IsFirstSideLossResult(clean))
            {
                return 1;
            }
            if (IsSecondSideLossResult(clean))
            {
                return 0;
            }
            if (IsFirstSideWinResult(clean))
            {
                return 0;
            }
            if (IsSecondSideWinResult(clean))
            {
                return 1;
            }

            return null;
        }

        private static int? DetermineWinnerFromEndType(string endType)
        {
            var clean = (endType ?? "").Trim().ToLowerInvariant();
            return clean switch
            {
                "checkmate_white" => 0,
                "checkmate_red" => 0,
                "checkmate_black" => 1,
                "timeout_white" => 1,
                "timeout_red" => 1,
                "timeout_black" => 0,
                _ => null
            };
        }

        private static bool IsFirstSideWinResult(string result)
        {
            var lower = (result ?? "").ToLowerInvariant();
            return lower.Contains("red wins", StringComparison.Ordinal) ||
                lower.Contains("red won", StringComparison.Ordinal) ||
                lower.Contains("red victory", StringComparison.Ordinal) ||
                lower.Contains("red checkmate", StringComparison.Ordinal) ||
                lower.Contains("white wins", StringComparison.Ordinal) ||
                lower.Contains("white won", StringComparison.Ordinal) ||
                lower.Contains("white victory", StringComparison.Ordinal) ||
                lower.Contains("white checkmate", StringComparison.Ordinal) ||
                result.Contains("\u7ea2\u80dc", StringComparison.Ordinal) ||
                result.Contains("\u767d\u80dc", StringComparison.Ordinal) ||
                ContainsChineseSideOutcome(result, "\u7ea2\u65b9", true) ||
                ContainsChineseSideOutcome(result, "\u767d\u65b9", true);
        }

        private static bool IsSecondSideWinResult(string result)
        {
            var lower = (result ?? "").ToLowerInvariant();
            return lower.Contains("black wins", StringComparison.Ordinal) ||
                lower.Contains("black won", StringComparison.Ordinal) ||
                lower.Contains("black victory", StringComparison.Ordinal) ||
                lower.Contains("black checkmate", StringComparison.Ordinal) ||
                result.Contains("\u9ed1\u80dc", StringComparison.Ordinal) ||
                ContainsChineseSideOutcome(result, "\u9ed1\u65b9", true);
        }

        private static bool IsFirstSideLossResult(string result)
        {
            var lower = (result ?? "").ToLowerInvariant();
            return lower.Contains("red lost", StringComparison.Ordinal) ||
                lower.Contains("red loses", StringComparison.Ordinal) ||
                lower.Contains("red loss", StringComparison.Ordinal) ||
                lower.Contains("white lost", StringComparison.Ordinal) ||
                lower.Contains("white loses", StringComparison.Ordinal) ||
                lower.Contains("white loss", StringComparison.Ordinal) ||
                result.Contains("\u7ea2\u8d25", StringComparison.Ordinal) ||
                result.Contains("\u767d\u8d25", StringComparison.Ordinal) ||
                ContainsChineseSideOutcome(result, "\u7ea2\u65b9", false) ||
                ContainsChineseSideOutcome(result, "\u767d\u65b9", false);
        }

        private static bool IsSecondSideLossResult(string result)
        {
            var lower = (result ?? "").ToLowerInvariant();
            return lower.Contains("black lost", StringComparison.Ordinal) ||
                lower.Contains("black loses", StringComparison.Ordinal) ||
                lower.Contains("black loss", StringComparison.Ordinal) ||
                result.Contains("\u9ed1\u8d25", StringComparison.Ordinal) ||
                ContainsChineseSideOutcome(result, "\u9ed1\u65b9", false);
        }

        private static bool ContainsChineseSideOutcome(string result, string sideName, bool isWin)
        {
            if (string.IsNullOrWhiteSpace(result) || !result.Contains(sideName, StringComparison.Ordinal))
            {
                return false;
            }

            return isWin
                ? result.Contains("\u80dc", StringComparison.Ordinal) || result.Contains("\u8d62", StringComparison.Ordinal)
                : result.Contains("\u8d25", StringComparison.Ordinal) || result.Contains("\u8f93", StringComparison.Ordinal);
        }

        private static bool IsDrawResult(string result)
        {
            return (result ?? "").Contains("Draw", StringComparison.OrdinalIgnoreCase) ||
                (result ?? "").Contains("\u548c\u68cb", StringComparison.Ordinal) ||
                (result ?? "").Contains("\u5e73\u5c40", StringComparison.Ordinal);
        }

        private static bool IsLeftResult(string result)
        {
            return (result ?? "").Contains("Left game", StringComparison.OrdinalIgnoreCase) ||
                (result ?? "").Contains("\u4e3b\u52a8\u79bb\u5f00", StringComparison.Ordinal);
        }

        private static string CleanForPrompt(string value)
        {
            return (value ?? "")
                .Replace("\r", " ", StringComparison.Ordinal)
                .Replace("\n", " ", StringComparison.Ordinal)
                .Trim();
        }

        private static bool IsInternationalChess(GameSession session)
        {
            var variant = session.GameVariant ?? "";
            return variant.Contains("\u56fd\u9645\u8c61\u68cb") ||
                variant.Contains("鍥介檯璞℃") ||
                variant.Contains("Chess", StringComparison.OrdinalIgnoreCase);
        }

        private static double EstimateDurationMinutes(GameSession session)
        {
            var wallClockMinutes = session.GetGameDuration().TotalMinutes;
            if (wallClockMinutes > 0.05)
            {
                return wallClockMinutes;
            }

            if (session.ClockInitialSeconds <= 0)
            {
                return wallClockMinutes;
            }

            var incrementTotal = session.ClockIncrementSeconds * Math.Max(0, session.MoveHistory.Count);
            var consumedSeconds = session.ClockInitialSeconds * 2.0 +
                incrementTotal -
                session.WhiteClockRemainingSeconds -
                session.BlackClockRemainingSeconds;
            return Math.Max(0.0, consumedSeconds / 60.0);
        }

        private static string FormatClockSeconds(double seconds)
        {
            var clamped = Math.Max(0, seconds);
            var wholeSeconds = (int)Math.Round(clamped);
            return $"{wholeSeconds / 60:00}:{wholeSeconds % 60:00}";
        }

        private static string SideName(int side, GameSession session)
        {
            if (!AI_Module_Config.UseEnglishPrompts())
            {
                return session.GetSideName(side);
            }

            return IsInternationalChess(session)
                ? (side == 0 ? "White" : "Black")
                : (side == 0 ? "Red" : "Black");
        }

        private static string NormalizeGameEndType(string endType)
        {
            var clean = (endType ?? "").Trim();
            if (string.IsNullOrWhiteSpace(clean))
            {
                return "";
            }

            return clean switch
            {
                "checkmate_white" => "White won by checkmate",
                "checkmate_black" => "Black won by checkmate",
                "timeout_white" => "White lost on time",
                "timeout_black" => "Black lost on time",
                "stalemate_white" => "Stalemate",
                "stalemate_black" => "Stalemate",
                "50_moves" => "50-move draw",
                "not_enough_piece" => "Insufficient material draw",
                _ => clean
            };
        }

        private static string NormalizeResult(string result)
        {
            if (!AI_Module_Config.UseEnglishPrompts() || string.IsNullOrWhiteSpace(result))
            {
                return result;
            }
            if (result.Contains("Draw", StringComparison.OrdinalIgnoreCase) || result.Contains("\u548c\u68cb"))
            {
                return "Draw";
            }
            if (result.Contains("Red", StringComparison.OrdinalIgnoreCase) || result.Contains("\u7ea2\u80dc"))
            {
                return "Red wins";
            }
            if (result.Contains("White", StringComparison.OrdinalIgnoreCase) || result.Contains("\u767d\u80dc"))
            {
                return "White wins";
            }
            if (result.Contains("Black", StringComparison.OrdinalIgnoreCase) || result.Contains("\u9ed1\u80dc"))
            {
                return "Black wins";
            }
            return result;
        }

        private ReviewResult ParseReviewResponse(string response)
        {
            var result = new ReviewResult
            {
                Content = response,
                JsonData = "",
                CriticalMistakes = Array.Empty<string>()
            };

            try
            {
                var lines = response.Split('\n');
                var mistakes = new System.Collections.Generic.List<string>();

                foreach (var line in lines)
                {
                    if (line.Contains("critical", StringComparison.OrdinalIgnoreCase) ||
                        line.Contains("mistake", StringComparison.OrdinalIgnoreCase) ||
                        line.Contains("\u5931\u8bef") ||
                        line.Contains("\u5173\u952e"))
                    {
                        mistakes.Add(line.Trim());
                    }
                }

                result.CriticalMistakes = mistakes.ToArray();

                var jsonData = new
                {
                    review_content = response,
                    critical_mistakes = mistakes.ToArray(),
                    generated_at = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")
                };

                result.JsonData = JsonSerializer.Serialize(jsonData, new JsonSerializerOptions
                {
                    PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
                    WriteIndented = true
                });
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[ReviewAgent] Failed to parse review response: {ex.Message}");
            }

            return result;
        }
    }
}
