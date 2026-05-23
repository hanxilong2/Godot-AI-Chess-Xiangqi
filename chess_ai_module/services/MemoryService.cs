using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using ChessAI.DataModels;

namespace ChessAI.Module.Services
{
    public class MemoryService
    {
        private const string CurrentStartMarker = "<!-- CURRENT_GAME_MEMORY_START -->";
        private const string CurrentEndMarker = "<!-- CURRENT_GAME_MEMORY_END -->";
        private const string GlobalStartMarker = "<!-- GLOBAL_GAME_MEMORY_START -->";
        private const string GlobalEndMarker = "<!-- GLOBAL_GAME_MEMORY_END -->";
        private const string EntryStartMarker = "<!-- GAME_MEMORY_ENTRY_START -->";
        private const string EntryEndMarker = "<!-- GAME_MEMORY_ENTRY_END -->";
        private const string CurrentInteractionStartMarker = "<!-- CURRENT_GAME_INTERACTIONS_START -->";
        private const string CurrentInteractionEndMarker = "<!-- CURRENT_GAME_INTERACTIONS_END -->";
        private const string InteractionEntryStartMarker = "<!-- CURRENT_GAME_INTERACTION_ENTRY_START -->";
        private const string InteractionEntryEndMarker = "<!-- CURRENT_GAME_INTERACTION_ENTRY_END -->";
        private static readonly object FileLock = new object();
        private string _currentGameMemoryMarkdown = CreateDefaultCurrentDocument();

        public MemoryService()
        {
            EnsureMemoryFiles();
        }

        public string BuildPromptMemory(GameSession session)
        {
            UpdateCurrentGameMemory(session);
            var currentMemory = LoadCurrentGameMemoryMarkdown();
            var globalMemory = LoadGlobalGameMemoryMarkdown(session);
            if (string.IsNullOrWhiteSpace(currentMemory) && string.IsNullOrWhiteSpace(globalMemory))
            {
                return "";
            }

            var promptBuilder = new StringBuilder();
            promptBuilder.AppendLine("Use the following Markdown memory as context. If it conflicts with the current request, live board state, or latest move data, trust the current request first.");
            promptBuilder.AppendLine();
            promptBuilder.AppendLine("Current in-memory game memory document:");
            promptBuilder.AppendLine(string.IsNullOrWhiteSpace(currentMemory) ? "(empty)" : currentMemory.Trim());
            promptBuilder.AppendLine();
            promptBuilder.AppendLine("Variant global game memory document:");
            promptBuilder.AppendLine(string.IsNullOrWhiteSpace(globalMemory) ? "(empty)" : globalMemory.Trim());

            return promptBuilder.ToString().Trim();
        }

        public string LoadCurrentGameMemoryMarkdown()
        {
            lock (FileLock)
            {
                EnsureCurrentMemoryDocumentUnsafe();
                return _currentGameMemoryMarkdown;
            }
        }

        public string LoadGlobalGameMemoryMarkdown()
        {
            return LoadGlobalGameMemoryMarkdown(null);
        }

        public string LoadGlobalGameMemoryMarkdown(GameSession session)
        {
            lock (FileLock)
            {
                EnsureMemoryFilesUnsafe();
                return ReadGlobalMemoryFileUnsafe(GetGlobalMemoryFilePath(session));
            }
        }

        public bool ClearGlobalMemory()
        {
            lock (FileLock)
            {
                EnsureStorageDirectory();
                var clearedChess = WriteGlobalMemoryFileUnsafe(AI_Module_Config.GLOBAL_CHESS_MEMORY_FILE_PATH, CreateDefaultGlobalDocument());
                var clearedXiangqi = WriteGlobalMemoryFileUnsafe(AI_Module_Config.GLOBAL_XIANGQI_MEMORY_FILE_PATH, CreateDefaultGlobalDocument());
                return clearedChess && clearedXiangqi;
            }
        }

        public bool ClearChessGlobalMemory()
        {
            lock (FileLock)
            {
                EnsureStorageDirectory();
                return WriteGlobalMemoryFileUnsafe(AI_Module_Config.GLOBAL_CHESS_MEMORY_FILE_PATH, CreateDefaultGlobalDocument());
            }
        }

        public bool ClearXiangqiGlobalMemory()
        {
            lock (FileLock)
            {
                EnsureStorageDirectory();
                return WriteGlobalMemoryFileUnsafe(AI_Module_Config.GLOBAL_XIANGQI_MEMORY_FILE_PATH, CreateDefaultGlobalDocument());
            }
        }

        public bool ClearCurrentGameMemory()
        {
            lock (FileLock)
            {
                _currentGameMemoryMarkdown = CreateDefaultCurrentDocument();
                return true;
            }
        }

        public bool ClearCurrentGameMemory(GameSession session)
        {
            lock (FileLock)
            {
                if (session == null || string.IsNullOrWhiteSpace(session.SessionId))
                {
                    _currentGameMemoryMarkdown = CreateDefaultCurrentDocument();
                    return true;
                }

                EnsureCurrentMemoryDocumentUnsafe();
                var currentSection = ExtractSection(_currentGameMemoryMarkdown, CurrentStartMarker, CurrentEndMarker);
                var currentSessionId = ExtractCurrentSessionId(currentSection);
                if (!string.Equals(currentSessionId, CleanOneLine(session.SessionId), StringComparison.Ordinal))
                {
                    return true;
                }

                _currentGameMemoryMarkdown = CreateDefaultCurrentDocument();
                return true;
            }
        }

        public void UpdateCurrentGameMemory(GameSession session)
        {
            lock (FileLock)
            {
                EnsureCurrentMemoryDocumentUnsafe();
                var content = _currentGameMemoryMarkdown;
                var currentSection = ExtractSection(content, CurrentStartMarker, CurrentEndMarker);
                var interactionEntries = ShouldKeepCurrentInteractions(currentSection, session)
                    ? ExtractMarkedEntries(currentSection, InteractionEntryStartMarker, InteractionEntryEndMarker)
                    : new List<string>();

                content = ReplaceSection(content, CurrentStartMarker, CurrentEndMarker, BuildCurrentGameMemory(session, interactionEntries));
                _currentGameMemoryMarkdown = content;
            }
        }

        public void RecordAIResponse(GameSession session, string responseType, string playerMessage, string aiResponse, string contextLine = "")
        {
            if (string.IsNullOrWhiteSpace(aiResponse))
            {
                return;
            }

            lock (FileLock)
            {
                EnsureCurrentMemoryDocumentUnsafe();
                var content = _currentGameMemoryMarkdown;
                var currentSection = ExtractSection(content, CurrentStartMarker, CurrentEndMarker);
                var interactionEntries = ShouldKeepCurrentInteractions(currentSection, session)
                    ? ExtractMarkedEntries(currentSection, InteractionEntryStartMarker, InteractionEntryEndMarker)
                    : new List<string>();

                interactionEntries.Add(WrapInteractionEntry(responseType, playerMessage, aiResponse, contextLine));
                while (interactionEntries.Count > AI_Module_Config.CURRENT_MEMORY_INTERACTION_LIMIT)
                {
                    interactionEntries.RemoveAt(0);
                }

                content = ReplaceSection(content, CurrentStartMarker, CurrentEndMarker, BuildCurrentGameMemory(session, interactionEntries));
                _currentGameMemoryMarkdown = content;
            }
        }

        public bool AddGlobalGameMemory(GameSession session, string result, string memoryEntry)
        {
            lock (FileLock)
            {
                EnsureMemoryFilesUnsafe();
                var globalMemoryPath = GetGlobalMemoryFilePath(session);
                var content = ReadGlobalMemoryFileUnsafe(globalMemoryPath);
                var globalSection = ExtractSection(content, GlobalStartMarker, GlobalEndMarker);
                var entries = ExtractMarkedEntries(globalSection, EntryStartMarker, EntryEndMarker);

                entries.Add(WrapGlobalEntry(session, result, memoryEntry));
                while (entries.Count > AI_Module_Config.GLOBAL_MEMORY_ENTRY_LIMIT)
                {
                    entries.RemoveAt(0);
                }

                var newGlobalSection = BuildGlobalMemorySection(entries);
                content = ReplaceSection(content, GlobalStartMarker, GlobalEndMarker, newGlobalSection);
                return WriteGlobalMemoryFileUnsafe(globalMemoryPath, content);
            }
        }

        public static void AppendMemoryPrompt(StringBuilder promptBuilder, string memoryPrompt)
        {
            if (promptBuilder == null || string.IsNullOrWhiteSpace(memoryPrompt))
            {
                return;
            }

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("AI memory:");
            promptBuilder.AppendLine(memoryPrompt.Trim());
        }

        private static string BuildCurrentGameMemory(GameSession session, IReadOnlyList<string> interactionEntries)
        {
            session ??= new GameSession();
            var promptBuilder = new StringBuilder();
            var moves = session.MoveHistory ?? new List<MoveRecord>();

            promptBuilder.AppendLine("## Current Game Memory");
            promptBuilder.AppendLine();
            promptBuilder.AppendLine($"- Session id: {CleanOneLine(session.SessionId)}");
            promptBuilder.AppendLine($"- Updated at: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            promptBuilder.AppendLine($"- Variant: {CleanOneLine(session.GameVariant)}");
            promptBuilder.AppendLine($"- Status: {CleanOneLine(session.GameStatus)}");
            promptBuilder.AppendLine($"- Result: {CleanOneLine(string.IsNullOrWhiteSpace(session.GameResult) ? "not finished" : session.GameResult)}");
            promptBuilder.AppendLine($"- Human side: {CleanOneLine(session.GetSideName(session.HumanSide))} ({session.HumanSide})");
            promptBuilder.AppendLine($"- Side to move: {CleanOneLine(session.GetSideName(session.CurrentPlayer))} ({session.CurrentPlayer})");
            promptBuilder.AppendLine($"- Move count: {moves.Count}");
            promptBuilder.AppendLine($"- Current FEN: {CleanOneLine(session.CurrentFEN)}");
            promptBuilder.AppendLine($"- Board: {FormatBoard(session.Board)}");

            AppendClockMemory(promptBuilder, session);
            AppendMoveMemory(promptBuilder, session, moves);
            AppendNotableMoveMemory(promptBuilder, session, moves);
            AppendInteractionMemory(promptBuilder, interactionEntries);

            return promptBuilder.ToString().Trim();
        }

        private static void AppendInteractionMemory(StringBuilder promptBuilder, IReadOnlyList<string> interactionEntries)
        {
            promptBuilder.AppendLine();
            promptBuilder.AppendLine(CurrentInteractionStartMarker);
            promptBuilder.AppendLine("### AI Interaction Memory");
            promptBuilder.AppendLine();

            if (interactionEntries == null || interactionEntries.Count == 0)
            {
                promptBuilder.AppendLine("No AI interactions recorded yet.");
            }
            else
            {
                foreach (var entry in interactionEntries)
                {
                    promptBuilder.AppendLine(entry.Trim());
                    promptBuilder.AppendLine();
                }
            }

            promptBuilder.AppendLine(CurrentInteractionEndMarker);
        }

        private static void AppendClockMemory(StringBuilder promptBuilder, GameSession session)
        {
            if (string.IsNullOrWhiteSpace(session.TimeControl) &&
                session.ClockInitialSeconds <= 0 &&
                session.WhiteClockRemainingSeconds <= 0 &&
                session.BlackClockRemainingSeconds <= 0)
            {
                return;
            }

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("### Clock");
            promptBuilder.AppendLine($"- Time control: {CleanOneLine(session.TimeControl)}");
            promptBuilder.AppendLine($"- Rule: {CleanOneLine(session.TimeControlDescription)}");
            promptBuilder.AppendLine($"- Initial seconds: {session.ClockInitialSeconds:F0}");
            promptBuilder.AppendLine($"- Increment seconds: {session.ClockIncrementSeconds:F0}");
            promptBuilder.AppendLine($"- Side 0 remaining: {CleanOneLine(session.WhiteClockRemaining)} ({session.WhiteClockRemainingSeconds:F1}s)");
            promptBuilder.AppendLine($"- Side 1 remaining: {CleanOneLine(session.BlackClockRemaining)} ({session.BlackClockRemainingSeconds:F1}s)");
        }

        private static void AppendMoveMemory(StringBuilder promptBuilder, GameSession session, List<MoveRecord> moves)
        {
            if (moves.Count == 0)
            {
                promptBuilder.AppendLine();
                promptBuilder.AppendLine("### Move Memory");
                promptBuilder.AppendLine("- No moves recorded yet.");
                return;
            }

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("### Recent Move Memory");
            var startIndex = Math.Max(0, moves.Count - 20);
            if (startIndex > 0)
            {
                promptBuilder.AppendLine($"- Earlier moves omitted from current-game memory: {startIndex}");
            }

            for (var i = startIndex; i < moves.Count; i++)
            {
                var move = moves[i] ?? new MoveRecord();
                promptBuilder.AppendLine(
                    $"- Ply {SafePly(move, i)}; move {move.MoveNumber}; side={CleanOneLine(session.GetSideName(move.Side))}; " +
                    $"notation={CleanOneLine(ReadableMove(move))}; piece={CleanOneLine(move.Piece)}; " +
                    $"captured={CleanOneLine(EmptyAsDash(move.CapturedPiece))}; eval_loss={move.EvaluationScore}; banter_score={move.TeachingScore}; best={CleanOneLine(EmptyAsDash(move.BestMove))}");
            }
        }

        private static void AppendNotableMoveMemory(StringBuilder promptBuilder, GameSession session, List<MoveRecord> moves)
        {
            var notableMoves = moves
                .Where(move => move != null && Math.Max(Math.Abs(move.EvaluationScore), move.TeachingScore) >= 100)
                .OrderByDescending(move => Math.Max(Math.Abs(move.EvaluationScore), move.TeachingScore))
                .Take(8)
                .ToList();

            if (notableMoves.Count == 0)
            {
                return;
            }

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("### Notable Evaluation Swings");
            foreach (var move in notableMoves)
            {
                promptBuilder.AppendLine(
                    $"- Ply {move.PlyIndex}; side={CleanOneLine(session.GetSideName(move.Side))}; " +
                    $"notation={CleanOneLine(ReadableMove(move))}; eval_loss={move.EvaluationScore}; banter_score={move.TeachingScore}; best={CleanOneLine(EmptyAsDash(move.BestMove))}");
            }
        }

        private static bool ShouldKeepCurrentInteractions(string currentSection, GameSession session)
        {
            var existingSessionId = ExtractCurrentSessionId(currentSection);
            var incomingSessionId = CleanOneLine(session?.SessionId);

            if (string.IsNullOrWhiteSpace(existingSessionId) || string.IsNullOrWhiteSpace(incomingSessionId))
            {
                return false;
            }

            return string.Equals(existingSessionId, incomingSessionId, StringComparison.Ordinal);
        }

        private static string GetGlobalMemoryFilePath(GameSession session)
        {
            return IsInternationalChess(session)
                ? AI_Module_Config.GLOBAL_CHESS_MEMORY_FILE_PATH
                : AI_Module_Config.GLOBAL_XIANGQI_MEMORY_FILE_PATH;
        }

        private static bool IsInternationalChess(GameSession session)
        {
            var variant = CleanOneLine(session?.GameVariant);
            return variant.Contains("\u56fd\u9645\u8c61\u68cb", StringComparison.Ordinal) ||
                variant.Contains("鍥介檯璞℃", StringComparison.Ordinal) ||
                variant.Contains("Chess", StringComparison.OrdinalIgnoreCase);
        }

        private static string ExtractCurrentSessionId(string currentSection)
        {
            if (string.IsNullOrWhiteSpace(currentSection))
            {
                return "";
            }

            var lines = currentSection.Split('\n');
            foreach (var line in lines)
            {
                var trimmedLine = line.Trim();
                const string Prefix = "- Session id:";
                if (trimmedLine.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase))
                {
                    return CleanOneLine(trimmedLine.Substring(Prefix.Length));
                }
            }

            return "";
        }

        private static string WrapInteractionEntry(string responseType, string playerMessage, string aiResponse, string contextLine)
        {
            var promptBuilder = new StringBuilder();
            promptBuilder.AppendLine(InteractionEntryStartMarker);
            promptBuilder.AppendLine($"- Time: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            promptBuilder.AppendLine($"- Type: {CleanOneLine(responseType)}");

            if (!string.IsNullOrWhiteSpace(contextLine))
            {
                promptBuilder.AppendLine($"- Context: {CleanInteractionText(contextLine, 500)}");
            }

            if (!string.IsNullOrWhiteSpace(playerMessage))
            {
                promptBuilder.AppendLine($"- Player: {CleanInteractionText(playerMessage, 800)}");
            }

            promptBuilder.AppendLine($"- AI: {CleanInteractionText(aiResponse, 1400)}");
            promptBuilder.AppendLine(InteractionEntryEndMarker);

            return promptBuilder.ToString().Trim();
        }

        private static string WrapGlobalEntry(GameSession session, string result, string memoryEntry)
        {
            var safeSessionId = CleanOneLine(session?.SessionId);
            if (string.IsNullOrWhiteSpace(safeSessionId))
            {
                safeSessionId = Guid.NewGuid().ToString();
            }

            var safeResult = CleanOneLine(result);
            var cleanedEntry = SanitizeEntry(memoryEntry);
            if (string.IsNullOrWhiteSpace(cleanedEntry))
            {
                cleanedEntry = BuildFallbackGlobalEntry(session, result);
            }

            return $"{EntryStartMarker}\n" +
                $"<!-- session_id: {safeSessionId}; saved_at: {DateTime.Now:yyyy-MM-dd HH:mm:ss}; result: {safeResult} -->\n" +
                $"{cleanedEntry}\n" +
                $"{EntryEndMarker}";
        }

        private static string BuildFallbackGlobalEntry(GameSession session, string result)
        {
            session ??= new GameSession();
            var rawResult = string.IsNullOrWhiteSpace(result) ? session.GameResult : result;
            var titleResult = BuildMemoryResultLabel(session, rawResult);
            var promptBuilder = new StringBuilder();

            promptBuilder.AppendLine($"### {DateTime.Now:yyyy-MM-dd} | {CleanOneLine(titleResult)}");
            promptBuilder.AppendLine($"- \u80dc\u8d1f: {CleanOneLine(titleResult)}.");
            promptBuilder.AppendLine("- \u98ce\u683c: \u672c\u5c40\u5df2\u5b8c\u6210\u5f52\u6863\uff0c\u4f46\u672a\u80fd\u751f\u6210\u66f4\u7ec6\u7684\u6a21\u578b\u6458\u8981\uff1b\u5168\u5c40\u8bb0\u5fc6\u5148\u4fdd\u7559\u53ef\u8fc1\u79fb\u7684\u68cb\u98ce\u7ed3\u8bba\uff0c\u540e\u7eed\u5bf9\u5c40\u53ef\u5c06\u8fd9\u6761\u89c6\u4f5c\u4f4e\u7cbe\u5ea6\u53c2\u8003\uff0c\u4ee5\u5b9e\u65f6\u68cb\u76d8\u548c\u590d\u76d8\u539f\u6587\u4e3a\u4e3b\u3002");
            promptBuilder.AppendLine("- \u5f31\u70b9: \u7ee7\u7eed\u5173\u6ce8\u5927\u5b50\u4f4d\u7f6e\u3001\u5c06\u5e05\u5b89\u5168\u3001\u8f66\u9a6c\u70ae\u8054\u7edc\u6216\u5b50\u529b\u534f\u8c03\uff1b\u5173\u952e\u56de\u5408\u5148\u68c0\u67e5\u5bf9\u65b9\u7684\u5c06\u519b\u3001\u5403\u5b50\u548c\u7275\u5236\uff0c\u907f\u514d\u56e0\u4e00\u624b\u6025\u653b\u628a\u5c40\u9762\u4e3b\u52a8\u6743\u9001\u56de\u53bb\u3002");
            promptBuilder.AppendLine("- \u4e0b\u6b21\u63d0\u9192: \u8d70\u5b50\u524d\u5148\u7528\u4e24\u4e2a\u95ee\u9898\u8fc7\u4e00\u904d\uff1a\u8fd9\u624b\u662f\u5426\u6539\u5584\u81ea\u5df1\u6700\u5dee\u7684\u5b50\uff0c\u5bf9\u624b\u6700\u5f3a\u53cd\u51fb\u662f\u4ec0\u4e48\u3002\u82e5\u7b54\u6848\u4e0d\u6e05\u695a\uff0c\u5148\u9009\u62e9\u7a33\u5b9a\u9632\u5b88\u6216\u589e\u52a0\u534f\u540c\uff0c\u518d\u627e\u8fdb\u653b\u673a\u4f1a\u3002");

            return promptBuilder.ToString().Trim();
        }

        private static string BuildMemoryResultLabel(GameSession session, string result)
        {
            session ??= new GameSession();
            var cleanResult = CleanOneLine(string.IsNullOrWhiteSpace(result) ? session.GameResult : result);
            var humanSide = session.HumanSide == 1 ? 1 : 0;
            var winner = DetermineWinningSide(session, cleanResult);
            var sideName = CleanOneLine(session.GetSideName(humanSide));
            var outcome = winner.HasValue
                ? (winner.Value == humanSide ? "\u80dc\u5229" : "\u5931\u8d25")
                : IsDrawResult(cleanResult)
                    ? "\u548c\u68cb"
                    : IsLeftResult(cleanResult)
                        ? "\u4e3b\u52a8\u79bb\u5f00"
                        : "\u7ed3\u679c";
            var playerLabel = $"\u73a9\u5bb6{sideName}{outcome}";
            if (string.IsNullOrWhiteSpace(cleanResult) ||
                string.Equals(playerLabel, cleanResult, StringComparison.OrdinalIgnoreCase))
            {
                return playerLabel;
            }

            return $"{playerLabel}\uff08{cleanResult}\uff09";
        }

        private static int? DetermineWinningSide(GameSession session, string result)
        {
            var endType = (session?.GameEndType ?? "").Trim().ToLowerInvariant();
            switch (endType)
            {
                case "checkmate_white":
                case "checkmate_red":
                    return 0;
                case "checkmate_black":
                    return 1;
                case "timeout_white":
                case "timeout_red":
                    return 1;
                case "timeout_black":
                    return 0;
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

        private static string SanitizeEntry(string memoryEntry)
        {
            var cleaned = (memoryEntry ?? "")
                .Replace(EntryStartMarker, "", StringComparison.Ordinal)
                .Replace(EntryEndMarker, "", StringComparison.Ordinal)
                .Replace(CurrentStartMarker, "", StringComparison.Ordinal)
                .Replace(CurrentEndMarker, "", StringComparison.Ordinal)
                .Replace(GlobalStartMarker, "", StringComparison.Ordinal)
                .Replace(GlobalEndMarker, "", StringComparison.Ordinal)
                .Replace(CurrentInteractionStartMarker, "", StringComparison.Ordinal)
                .Replace(CurrentInteractionEndMarker, "", StringComparison.Ordinal)
                .Replace(InteractionEntryStartMarker, "", StringComparison.Ordinal)
                .Replace(InteractionEntryEndMarker, "", StringComparison.Ordinal)
                .Trim();

            if (cleaned.Length > 900)
            {
                cleaned = cleaned.Substring(0, 900).Trim();
            }

            return cleaned;
        }

        private static string BuildGlobalMemorySection(IReadOnlyList<string> entries)
        {
            var promptBuilder = new StringBuilder();
            promptBuilder.AppendLine("## Global Game Memory");
            promptBuilder.AppendLine();
            promptBuilder.AppendLine($"Stored entries: {entries.Count}/{AI_Module_Config.GLOBAL_MEMORY_ENTRY_LIMIT}. Oldest entries are removed first.");
            promptBuilder.AppendLine();

            if (entries.Count == 0)
            {
                promptBuilder.AppendLine("No completed game memory yet.");
                return promptBuilder.ToString().Trim();
            }

            foreach (var entry in entries)
            {
                promptBuilder.AppendLine(entry.Trim());
                promptBuilder.AppendLine();
            }

            return promptBuilder.ToString().Trim();
        }

        private static List<string> ExtractMarkedEntries(string text, string startMarker, string endMarker)
        {
            var entries = new List<string>();
            var searchIndex = 0;
            text ??= "";

            while (searchIndex < text.Length)
            {
                var startIndex = text.IndexOf(startMarker, searchIndex, StringComparison.Ordinal);
                if (startIndex < 0)
                {
                    break;
                }

                var endIndex = text.IndexOf(endMarker, startIndex + startMarker.Length, StringComparison.Ordinal);
                if (endIndex < 0)
                {
                    break;
                }

                endIndex += endMarker.Length;
                entries.Add(text.Substring(startIndex, endIndex - startIndex).Trim());
                searchIndex = endIndex;
            }

            return entries;
        }

        private static string ExtractSection(string content, string startMarker, string endMarker)
        {
            var text = content ?? "";
            var startIndex = text.IndexOf(startMarker, StringComparison.Ordinal);
            if (startIndex < 0)
            {
                return "";
            }

            startIndex += startMarker.Length;
            var endIndex = text.IndexOf(endMarker, startIndex, StringComparison.Ordinal);
            if (endIndex < 0)
            {
                return "";
            }

            return text.Substring(startIndex, endIndex - startIndex).Trim();
        }

        private static string ReplaceSection(string content, string startMarker, string endMarker, string newSection)
        {
            var text = string.IsNullOrWhiteSpace(content) ? DefaultDocumentFor(startMarker) : content;
            var startIndex = text.IndexOf(startMarker, StringComparison.Ordinal);
            var endIndex = startIndex >= 0
                ? text.IndexOf(endMarker, startIndex + startMarker.Length, StringComparison.Ordinal)
                : -1;

            if (startIndex < 0 || endIndex < 0)
            {
                text = DefaultDocumentFor(startMarker);
                startIndex = text.IndexOf(startMarker, StringComparison.Ordinal);
                endIndex = text.IndexOf(endMarker, startIndex + startMarker.Length, StringComparison.Ordinal);
            }

            var before = text.Substring(0, startIndex + startMarker.Length);
            var after = text.Substring(endIndex);
            return $"{before}\n{(newSection ?? "").Trim()}\n{after}";
        }

        private static string DefaultDocumentFor(string sectionStartMarker)
        {
            return sectionStartMarker == GlobalStartMarker
                ? CreateDefaultGlobalDocument()
                : CreateDefaultCurrentDocument();
        }

        private static string CreateDefaultCurrentDocument()
        {
            return "# Current Game Memory\n\n" +
                "This Markdown document is maintained in memory by the AI module. It stores detailed memory for the current game only.\n\n" +
                $"{CurrentStartMarker}\n" +
                "## Current Game Memory\n\nNo active game has been recorded yet.\n\n" +
                $"{CurrentInteractionStartMarker}\n" +
                "### AI Interaction Memory\n\nNo AI interactions recorded yet.\n" +
                $"{CurrentInteractionEndMarker}\n" +
                $"{CurrentEndMarker}\n";
        }

        private static string CreateDefaultGlobalDocument()
        {
            return "# Global Game Memory\n\n" +
                "This Markdown file is maintained by the AI module. It stores concise summaries of completed games only.\n\n" +
                $"{GlobalStartMarker}\n" +
                $"## Global Game Memory\n\nStored entries: 0/{AI_Module_Config.GLOBAL_MEMORY_ENTRY_LIMIT}. Oldest entries are removed first.\n\nNo completed game memory yet.\n" +
                $"{GlobalEndMarker}\n";
        }

        private static string FormatBoard(string[] board)
        {
            if (board == null || board.Length == 0)
            {
                return "[]";
            }

            return "[" + string.Join(",", board.Select(piece => string.IsNullOrWhiteSpace(piece) ? "." : CleanOneLine(piece))) + "]";
        }

        private static int SafePly(MoveRecord move, int fallbackIndex)
        {
            return move.PlyIndex > 0 ? move.PlyIndex : fallbackIndex + 1;
        }

        private static string ReadableMove(MoveRecord move)
        {
            if (!string.IsNullOrWhiteSpace(move?.ChineseNotation))
            {
                return move.ChineseNotation;
            }
            if (!string.IsNullOrWhiteSpace(move?.CoordinateNotation))
            {
                return move.CoordinateNotation;
            }
            return move == null ? "-" : $"{move.FromIndex}->{move.ToIndex}";
        }

        private static string EmptyAsDash(string value)
        {
            return string.IsNullOrWhiteSpace(value) ? "-" : value;
        }

        private static string CleanOneLine(string value)
        {
            return (value ?? "")
                .Replace("\r", " ", StringComparison.Ordinal)
                .Replace("\n", " ", StringComparison.Ordinal)
                .Replace(CurrentStartMarker, "", StringComparison.Ordinal)
                .Replace(CurrentEndMarker, "", StringComparison.Ordinal)
                .Replace(GlobalStartMarker, "", StringComparison.Ordinal)
                .Replace(GlobalEndMarker, "", StringComparison.Ordinal)
                .Replace(EntryStartMarker, "", StringComparison.Ordinal)
                .Replace(EntryEndMarker, "", StringComparison.Ordinal)
                .Replace(CurrentInteractionStartMarker, "", StringComparison.Ordinal)
                .Replace(CurrentInteractionEndMarker, "", StringComparison.Ordinal)
                .Replace(InteractionEntryStartMarker, "", StringComparison.Ordinal)
                .Replace(InteractionEntryEndMarker, "", StringComparison.Ordinal)
                .Trim();
        }

        private static string CleanInteractionText(string value, int maxLength)
        {
            var cleaned = CleanOneLine(value);
            if (maxLength > 0 && cleaned.Length > maxLength)
            {
                cleaned = cleaned.Substring(0, maxLength).Trim() + "...";
            }

            return cleaned;
        }

        private void EnsureMemoryFiles()
        {
            lock (FileLock)
            {
                EnsureCurrentMemoryDocumentUnsafe();
                EnsureMemoryFilesUnsafe();
            }
        }

        private void EnsureCurrentMemoryDocumentUnsafe()
        {
            if (string.IsNullOrWhiteSpace(_currentGameMemoryMarkdown) ||
                !_currentGameMemoryMarkdown.Contains(CurrentStartMarker, StringComparison.Ordinal) ||
                !_currentGameMemoryMarkdown.Contains(CurrentEndMarker, StringComparison.Ordinal))
            {
                _currentGameMemoryMarkdown = CreateDefaultCurrentDocument();
            }
        }

        private static void EnsureMemoryFilesUnsafe()
        {
            EnsureStorageDirectory();

            EnsureGlobalMemoryFileUnsafe(AI_Module_Config.GLOBAL_CHESS_MEMORY_FILE_PATH);
            EnsureGlobalMemoryFileUnsafe(AI_Module_Config.GLOBAL_XIANGQI_MEMORY_FILE_PATH);

            ValidateGlobalMemoryFileUnsafe(AI_Module_Config.GLOBAL_CHESS_MEMORY_FILE_PATH);
            ValidateGlobalMemoryFileUnsafe(AI_Module_Config.GLOBAL_XIANGQI_MEMORY_FILE_PATH);
        }

        private static void EnsureGlobalMemoryFileUnsafe(string filePath)
        {
            if (!FileAccess.FileExists(filePath))
            {
                WriteGlobalMemoryFileUnsafe(filePath, CreateDefaultGlobalDocument());
            }
        }

        private static void ValidateGlobalMemoryFileUnsafe(string filePath)
        {
            var globalContent = ReadGlobalMemoryFileUnsafe(filePath);
            if (string.IsNullOrWhiteSpace(globalContent) ||
                !globalContent.Contains(GlobalStartMarker, StringComparison.Ordinal) ||
                !globalContent.Contains(GlobalEndMarker, StringComparison.Ordinal))
            {
                WriteGlobalMemoryFileUnsafe(filePath, CreateDefaultGlobalDocument());
            }
        }

        private static void EnsureStorageDirectory()
        {
            try
            {
                var globalPath = ProjectSettings.GlobalizePath(AI_Module_Config.STORAGE_FOLDER_PATH);
                if (!string.IsNullOrWhiteSpace(globalPath))
                {
                    System.IO.Directory.CreateDirectory(globalPath);
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[MemoryService] Failed to create storage directory through System.IO: {ex.Message}");
            }

            var dir = DirAccess.Open(AI_Module_Config.STORAGE_FOLDER_PATH);
            if (dir == null)
            {
                DirAccess.MakeDirRecursiveAbsolute(AI_Module_Config.STORAGE_FOLDER_PATH);
            }
        }

        private static string ReadGlobalMemoryFileUnsafe(string filePath)
        {
            return ReadMemoryFileUnsafe(filePath);
        }

        private static string ReadMemoryFileUnsafe(string filePath)
        {
            FileAccess file = null;
            try
            {
                file = FileAccess.Open(filePath, FileAccess.ModeFlags.Read);
                if (file == null)
                {
                    return "";
                }

                return file.GetAsText();
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[MemoryService] Failed to read memory file: {ex.Message}");
                return "";
            }
            finally
            {
                file?.Close();
            }
        }

        private static bool WriteGlobalMemoryFileUnsafe(string filePath, string content)
        {
            return WriteMemoryFileUnsafe(filePath, content);
        }

        private static bool WriteMemoryFileUnsafe(string filePath, string content)
        {
            FileAccess file = null;
            try
            {
                file = FileAccess.Open(filePath, FileAccess.ModeFlags.Write);
                if (file == null)
                {
                    GD.PrintErr($"[MemoryService] Failed to open memory file for writing: {filePath}");
                    return false;
                }

                file.StoreString(content ?? "");
                return true;
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[MemoryService] Failed to write memory file: {ex.Message}");
                return false;
            }
            finally
            {
                file?.Close();
            }
        }
    }
}
