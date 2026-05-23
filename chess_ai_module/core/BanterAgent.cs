using Godot;
using System;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using ChessAI.DataModels;
using ChessAI.Module.Services;

namespace ChessAI.Module.Core
{
    /// <summary>
    /// Proactive table-talk generator for Xiangqi moments such as a player move or undo.
    /// </summary>
    public class BanterAgent
    {
        private readonly LlmApiService _llmService;
        private readonly PromptLoader _promptLoader;
        private readonly MemoryService _memoryService;

        private enum GamePhase
        {
            Opening,
            Middlegame,
            Endgame,
        }

        public BanterAgent(LlmApiService llmService, PromptLoader promptLoader, MemoryService memoryService)
        {
            _llmService = llmService;
            _promptLoader = promptLoader;
            _memoryService = memoryService;
        }

        public static bool ShouldTriggerBanter()
        {
            return Random.Shared.NextDouble() < AI_Module_Config.BANTER_TRIGGER_PROBABILITY;
        }

        public async Task<string> ProcessMoveAsync(MoveRecord moveRecord, GameSession session)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[BanterAgent] Processing move banter.");
            }

            moveRecord ??= new MoveRecord();
            session ??= new GameSession();

            var systemPrompt = _promptLoader.LoadBanterPrompt();
            var memoryPrompt = _memoryService?.BuildPromptMemory(session) ?? "";
            var context = BuildBanterContext(session, GetBanterScore(moveRecord));
            var userPrompt = BuildUserPrompt(BanterTrigger.Move, moveRecord, session, context, memoryPrompt, 0, "");

            var response = await _llmService.CompleteChatAsync(
                systemPrompt,
                userPrompt,
                AI_Module_Config.BANTER_MODEL,
                AI_Module_Config.BANTER_MAX_TOKENS);

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[BanterAgent] AI response: {response}");
            }

            _memoryService?.RecordAIResponse(
                session,
                "banter",
                "",
                response,
                $"Move banter: {ReadableMove(moveRecord)}; score={context.ReferenceScore}");

            return response;
        }

        public async Task<string> ProcessUndoAsync(GameSession session, int undoneCount, string undoneMoveText)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[BanterAgent] Processing undo banter.");
            }

            session ??= new GameSession();
            undoneCount = Math.Max(1, undoneCount);

            var systemPrompt = _promptLoader.LoadBanterPrompt();
            var memoryPrompt = _memoryService?.BuildPromptMemory(session) ?? "";
            var context = BuildBanterContext(session, 0);
            var userPrompt = BuildUserPrompt(BanterTrigger.Undo, null, session, context, memoryPrompt, undoneCount, undoneMoveText ?? "");

            var response = await _llmService.CompleteChatAsync(
                systemPrompt,
                userPrompt,
                AI_Module_Config.BANTER_MODEL,
                AI_Module_Config.BANTER_MAX_TOKENS);

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[BanterAgent] AI undo response: {response}");
            }

            _memoryService?.RecordAIResponse(
                session,
                "banter",
                "",
                response,
                $"Undo banter: undone_count={undoneCount}; undone_moves={undoneMoveText}");

            return response;
        }

        private string BuildUserPrompt(
            BanterTrigger trigger,
            MoveRecord moveRecord,
            GameSession session,
            BanterContext context,
            string memoryPrompt,
            int undoneCount,
            string undoneMoveText)
        {
            return AI_Module_Config.UseEnglishPrompts()
                ? BuildEnglishUserPrompt(trigger, moveRecord, session, context, memoryPrompt, undoneCount, undoneMoveText)
                : BuildChineseUserPrompt(trigger, moveRecord, session, context, memoryPrompt, undoneCount, undoneMoveText);
        }

        private string BuildChineseUserPrompt(
            BanterTrigger trigger,
            MoveRecord moveRecord,
            GameSession session,
            BanterContext context,
            string memoryPrompt,
            int undoneCount,
            string undoneMoveText)
        {
            var promptBuilder = new StringBuilder();

            promptBuilder.AppendLine("当前棋局：");
            promptBuilder.AppendLine($"- 当前FEN: {session.CurrentFEN}");
            promptBuilder.AppendLine($"- 当前行棋方: {session.CurrentPlayerName}");
            promptBuilder.AppendLine($"- 玩家执方: {session.HumanSideName}");
            promptBuilder.AppendLine($"- 我执方/AI对手方: {session.GetSideName(OpponentSide(session.HumanSide))}");
            promptBuilder.AppendLine("- 称谓规则: 你=玩家；我=玩家的对手。");
            promptBuilder.AppendLine($"- 当前阶段: {context.PhaseLabel}");
            promptBuilder.AppendLine($"- 已走手数: {session.GetMoveCount()}");

            promptBuilder.AppendLine();
            if (trigger == BanterTrigger.Undo)
            {
                promptBuilder.AppendLine("触发事件：玩家刚悔棋。");
                promptBuilder.AppendLine($"- 悔棋步数: {undoneCount}");
                promptBuilder.AppendLine($"- 被悔掉的走法: {EmptyAsDash(undoneMoveText)}");
                promptBuilder.AppendLine("可以围绕悔棋动作搭话：比如被玩家这波操作整无语、假装关心对方是不是顶不住了，或者根据当前棋局和记忆找一个能继续施压的点。");
            }
            else
            {
                moveRecord ??= new MoveRecord();
                var rawScoreDiff = Math.Abs(moveRecord.EvaluationScore);
                promptBuilder.AppendLine("触发事件：玩家刚走了一步棋。");
                promptBuilder.AppendLine($"- 走法: {ReadableMove(moveRecord)}");
                promptBuilder.AppendLine($"- 移动棋子: {ChinesePieceName(moveRecord.Piece)}");
                promptBuilder.AppendLine($"- 被吃掉的棋子: {ChinesePieceName(moveRecord.CapturedPiece)}");
                promptBuilder.AppendLine($"- 本手事实: {FormatMoveFact(moveRecord, session)}");
                promptBuilder.AppendLine($"- 原始评估损失: {rawScoreDiff}");
                promptBuilder.AppendLine($"- 搭话参考分: {context.ReferenceScore}");
                promptBuilder.AppendLine($"- 引擎推荐: {EmptyAsDash(moveRecord.BestMove)}");
                promptBuilder.AppendLine($"- 皮卡鱼原始分析: {SerializePikafishAnalysis(moveRecord)}");
                promptBuilder.AppendLine("可以围绕当前棋局搭话：吐槽这手离谱、假装关心玩家是不是下完就后悔了，或者根据当前棋局和记忆找一个能继续施压的点。");
            }

            AppendRecentMoves(promptBuilder, session, false);
            MemoryService.AppendMemoryPrompt(promptBuilder, memoryPrompt);

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("主动搭话要求：");
            promptBuilder.AppendLine("- 这不是讲课，不要套固定模板。");
            promptBuilder.AppendLine("- 只输出一句自然中文，50到100个汉字，不要标题、分点、Markdown、引号或旁观解说。");
            promptBuilder.AppendLine("- 语气现代、生动、活泼，可以有梗和讥讽，也可以表现“我被你这手棋整无语了”。");
            promptBuilder.AppendLine("- 如果涉及棋局判断，要站在我这个对手自己的利益上盘算，不要替玩家出谋划策。");
            promptBuilder.AppendLine("- 要对玩家嘘寒问暖：表面假惺惺关心玩家的心态、手感和压力，实际根据当前棋局、当前棋局记忆和全局记忆找压力点，顺势施压。");
            promptBuilder.AppendLine("- 讥讽只针对棋步、局面、悔棋动作或思路，不攻击玩家本人，不骂人，不羞辱现实身份，不要太冒犯。");
            promptBuilder.AppendLine("- 不要机械复述分数，不要直接给完整下一手坐标或长变化；要像棋桌对面突然搭一句话。");

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[BanterAgent] trigger={trigger}, phase={context.PhaseLabel}, score={context.ReferenceScore}");
            }

            return promptBuilder.ToString();
        }

        private string BuildEnglishUserPrompt(
            BanterTrigger trigger,
            MoveRecord moveRecord,
            GameSession session,
            BanterContext context,
            string memoryPrompt,
            int undoneCount,
            string undoneMoveText)
        {
            var promptBuilder = new StringBuilder();

            promptBuilder.AppendLine("Current game:");
            promptBuilder.AppendLine($"- Current FEN: {session.CurrentFEN}");
            promptBuilder.AppendLine($"- Side to move: {EnglishSideName(session.CurrentPlayer, session)}");
            promptBuilder.AppendLine($"- Human side: {EnglishSideName(session.HumanSide, session)}");
            promptBuilder.AppendLine($"- My side / AI opponent side: {EnglishSideName(OpponentSide(session.HumanSide), session)}");
            promptBuilder.AppendLine("- Pronoun rule: you=human player; I=the opponent across the board.");
            promptBuilder.AppendLine($"- Phase: {EnglishPhase(context.PhaseLabel)}");
            promptBuilder.AppendLine($"- Total plies: {session.GetMoveCount()}");

            promptBuilder.AppendLine();
            if (trigger == BanterTrigger.Undo)
            {
                promptBuilder.AppendLine("Trigger: the player just undid a move.");
                promptBuilder.AppendLine($"- Undone plies: {undoneCount}");
                promptBuilder.AppendLine($"- Undone move text: {EmptyAsDash(undoneMoveText)}");
                promptBuilder.AppendLine("You may react to the undo, fake-check on whether the player is cracking, or use the position and memory to find a pressure point.");
            }
            else
            {
                moveRecord ??= new MoveRecord();
                var rawScoreDiff = Math.Abs(moveRecord.EvaluationScore);
                promptBuilder.AppendLine("Trigger: the player just made a move.");
                promptBuilder.AppendLine($"- Move: {ReadableMove(moveRecord)}");
                promptBuilder.AppendLine($"- Piece: {EnglishPieceName(moveRecord.Piece, session)}");
                promptBuilder.AppendLine($"- Captured: {EnglishPieceName(moveRecord.CapturedPiece, session)}");
                promptBuilder.AppendLine($"- Raw evaluation loss: {rawScoreDiff}");
                promptBuilder.AppendLine($"- Banter reference score: {context.ReferenceScore}");
                promptBuilder.AppendLine($"- Engine recommendation: {EmptyAsDash(moveRecord.BestMove)}");
                promptBuilder.AppendLine($"- Raw Pikafish analysis: {SerializePikafishAnalysis(moveRecord)}");
                promptBuilder.AppendLine("You may react to the current position, lightly roast the move, fake-check on whether the player regrets it, or use the position and memory to find a pressure point.");
            }

            AppendRecentMoves(promptBuilder, session, true);
            MemoryService.AppendMemoryPrompt(promptBuilder, memoryPrompt);

            promptBuilder.AppendLine();
            promptBuilder.AppendLine("Proactive banter requirement:");
            promptBuilder.AppendLine("- This is not a lesson. Do not split the reply into encouragement, hinting, reminder, or guidance.");
            promptBuilder.AppendLine("- Write one natural English sentence, 20 to 45 words. No title, bullets, Markdown, quotes, or spectator commentary.");
            promptBuilder.AppendLine("- Sound modern, vivid, and playful. Memes and light roasts are allowed; being a little speechless at the move is allowed.");
            promptBuilder.AppendLine("- If you judge the position, judge it from your own side's interests. Do not give the player a helpful plan.");
            promptBuilder.AppendLine("- Check in on the player in a fake-caring way: mention nerves, confidence, or pressure, while using the current position, current-game memory, and global memory to find pressure points.");
            promptBuilder.AppendLine("- Roast only the move, position, undo, or idea. Do not insult the player as a person, identity, intelligence, or real-life traits.");
            promptBuilder.AppendLine("- Do not mechanically cite the score, and do not give a full next-move coordinate or long line.");

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[BanterAgent] trigger={trigger}, phase={EnglishPhase(context.PhaseLabel)}, score={context.ReferenceScore}");
            }

            return promptBuilder.ToString();
        }

        private static int GetBanterScore(MoveRecord moveRecord)
        {
            if (moveRecord == null)
            {
                return 0;
            }

            if (moveRecord.TeachingScore > 0)
            {
                return ClampScore(moveRecord.TeachingScore);
            }

            var analysisScore = GetBanterScoreFromAnalysis(moveRecord);
            var evaluationScore = Math.Abs(moveRecord.EvaluationScore);
            return ClampScore(Math.Max(analysisScore, evaluationScore));
        }

        private static int GetBanterScoreFromAnalysis(MoveRecord moveRecord)
        {
            if (moveRecord?.PikafishAnalysis == null || moveRecord.PikafishAnalysis.Count == 0)
            {
                return 0;
            }

            try
            {
                using var document = JsonDocument.Parse(JsonSerializer.Serialize(moveRecord.PikafishAnalysis));
                var root = document.RootElement;

                var explicitScore = ReadJsonInt(root, "banter_score", "BanterScore", "teaching_score", "TeachingScore", "teachingScore");
                if (explicitScore > 0)
                {
                    return explicitScore;
                }

                var analysisLoss = Math.Abs(ReadJsonInt(root, "evaluation_score", "EvaluationScore", "eval_loss"));
                var beforeExpected = ReadNestedJsonInt(root, "before", "expected_score_permille", "expectedScorePermille");
                var afterExpected = ReadNestedJsonInt(root, "after", "expected_score_permille", "expectedScorePermille");
                var expectedSwing = beforeExpected >= 0 && afterExpected >= 0
                    ? Math.Abs(beforeExpected - afterExpected)
                    : 0;

                var beforeLoss = ReadNestedJsonInt(root, "before", "wdl_loss", "wdlLoss");
                var afterLoss = ReadNestedJsonInt(root, "after", "wdl_loss", "wdlLoss");
                var lossSwing = beforeLoss >= 0 && afterLoss >= 0
                    ? Math.Max(0, afterLoss - beforeLoss)
                    : 0;

                return Math.Max(analysisLoss, Math.Max(expectedSwing, lossSwing));
            }
            catch (Exception ex)
            {
                if (AI_Module_Config.DEBUG_MODE)
                {
                    GD.PrintErr($"[BanterAgent] Failed to read banter score from analysis: {ex.Message}");
                }

                return 0;
            }
        }

        private static int ReadNestedJsonInt(JsonElement root, string objectName, params string[] propertyNames)
        {
            if (!TryGetJsonProperty(root, out var nested, objectName) || nested.ValueKind != JsonValueKind.Object)
            {
                return -1;
            }

            return ReadJsonInt(nested, -1, propertyNames);
        }

        private static int ReadJsonInt(JsonElement element, params string[] propertyNames)
        {
            return ReadJsonInt(element, 0, propertyNames);
        }

        private static int ReadJsonInt(JsonElement element, int fallback, params string[] propertyNames)
        {
            if (!TryGetJsonProperty(element, out var value, propertyNames))
            {
                return fallback;
            }

            return value.ValueKind switch
            {
                JsonValueKind.Number when value.TryGetInt32(out var intValue) => intValue,
                JsonValueKind.Number when value.TryGetDouble(out var doubleValue) => (int)Math.Round(doubleValue),
                JsonValueKind.String when int.TryParse(value.GetString(), out var parsed) => parsed,
                _ => fallback
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

        private static BanterContext BuildBanterContext(GameSession session, int referenceScore)
        {
            return new BanterContext(
                GetPhaseLabel(DetermineGamePhase(session)),
                ClampScore(referenceScore));
        }

        private static GamePhase DetermineGamePhase(GameSession session)
        {
            var moveCount = session?.MoveHistory?.Count ?? 0;
            var nonKingPieceCount = CountNonKingPieces(session);

            if (nonKingPieceCount <= 0)
            {
                if (moveCount <= 14)
                {
                    return GamePhase.Opening;
                }

                return moveCount >= 28 ? GamePhase.Endgame : GamePhase.Middlegame;
            }

            if (moveCount <= 14 && nonKingPieceCount >= 24)
            {
                return GamePhase.Opening;
            }

            if (nonKingPieceCount <= 12 || (moveCount >= 28 && nonKingPieceCount <= 18))
            {
                return GamePhase.Endgame;
            }

            return GamePhase.Middlegame;
        }

        private static int CountNonKingPieces(GameSession session)
        {
            if (session?.Board == null)
            {
                return 0;
            }

            var count = 0;
            foreach (var piece in session.Board)
            {
                if (string.IsNullOrWhiteSpace(piece) || piece == "K" || piece == "k")
                {
                    continue;
                }

                count++;
            }

            return count;
        }

        private static string GetPhaseLabel(GamePhase phase)
        {
            return phase switch
            {
                GamePhase.Opening => "开局",
                GamePhase.Middlegame => "中局",
                _ => "残局",
            };
        }

        private static void AppendRecentMoves(StringBuilder promptBuilder, GameSession session, bool english)
        {
            if (session?.MoveHistory == null || session.MoveHistory.Count == 0)
            {
                return;
            }

            promptBuilder.AppendLine();
            promptBuilder.AppendLine(english ? "Recent moves:" : "最近走法：");
            var recentMoves = Math.Min(6, session.MoveHistory.Count);
            for (int i = session.MoveHistory.Count - recentMoves; i < session.MoveHistory.Count; i++)
            {
                var move = session.MoveHistory[i] ?? new MoveRecord();
                var notation = !string.IsNullOrWhiteSpace(move.ChineseNotation)
                    ? move.ChineseNotation
                    : move.CoordinateNotation;
                var side = english ? EnglishSideName(move.Side, session) : session.GetSideName(move.Side);
                promptBuilder.AppendLine(english
                    ? $"  Ply {SafePly(move, i)}, move {move.MoveNumber}, {side}: {notation}; moving_piece={EnglishPieceName(move.Piece, session)}; captured_piece={EnglishPieceName(move.CapturedPiece, session)}"
                    : $"  第{SafePly(move, i)}手，第{move.MoveNumber}回合，{side}: {notation}；移动棋子={ChinesePieceName(move.Piece)}；被吃掉的棋子={ChinesePieceName(move.CapturedPiece)}");
            }
        }

        private static int SafePly(MoveRecord move, int index)
        {
            return move.PlyIndex > 0 ? move.PlyIndex : index + 1;
        }

        private static int ClampScore(int score)
        {
            return Math.Min(500, Math.Max(0, score));
        }

        private static string ReadableMove(MoveRecord moveRecord)
        {
            if (moveRecord == null)
            {
                return "-";
            }

            if (!string.IsNullOrWhiteSpace(moveRecord.ChineseNotation))
            {
                return moveRecord.ChineseNotation;
            }

            if (!string.IsNullOrWhiteSpace(moveRecord.CoordinateNotation))
            {
                return moveRecord.CoordinateNotation;
            }

            return $"{moveRecord.FromIndex}->{moveRecord.ToIndex}";
        }

        private static string EmptyAsDash(string value)
        {
            return string.IsNullOrWhiteSpace(value) ? "-" : value;
        }

        private static int OpponentSide(int humanSide)
        {
            return humanSide == 1 ? 0 : 1;
        }

        private static string FormatMoveFact(MoveRecord move, GameSession session)
        {
            move ??= new MoveRecord();
            var side = session.GetSideName(move.Side);
            var movingPiece = ChinesePieceName(move.Piece);
            var capturedPiece = ChinesePieceName(move.CapturedPiece);
            var readableMove = ReadableMove(move);
            return string.IsNullOrWhiteSpace(move.CapturedPiece)
                ? $"{side}用{movingPiece}走了{readableMove}；这手没有吃子。"
                : $"{side}用{movingPiece}走了{readableMove}，吃掉的是{capturedPiece}。不要把移动棋子{movingPiece}误说成被吃掉的棋子。";
        }

        private static string ChinesePieceName(string piece)
        {
            if (string.IsNullOrWhiteSpace(piece))
            {
                return "-";
            }

            return piece switch
            {
                "K" => "红帅",
                "A" => "红仕",
                "E" => "红相",
                "H" => "红马",
                "R" => "红车",
                "C" => "红炮",
                "P" => "红兵",
                "k" => "黑将",
                "a" => "黑士",
                "e" => "黑象",
                "h" => "黑马",
                "r" => "黑车",
                "c" => "黑炮",
                "p" => "黑卒",
                _ => piece
            };
        }

        private static string SerializePikafishAnalysis(MoveRecord moveRecord)
        {
            if (moveRecord?.PikafishAnalysis == null || moveRecord.PikafishAnalysis.Count == 0)
            {
                return "{}";
            }

            return JsonSerializer.Serialize(moveRecord.PikafishAnalysis);
        }

        private static string EnglishSideName(int side, GameSession session)
        {
            var isChess = IsInternationalChess(session);
            return isChess
                ? (side == 0 ? "White" : "Black")
                : (side == 0 ? "Red" : "Black");
        }

        private static bool IsInternationalChess(GameSession session)
        {
            var variant = session?.GameVariant ?? "";
            return variant.Contains("国际象棋", StringComparison.Ordinal) ||
                variant.Contains("鍥介檯璞℃", StringComparison.Ordinal) ||
                variant.Contains("Chess", StringComparison.OrdinalIgnoreCase);
        }

        private static string EnglishPieceName(string piece, GameSession session)
        {
            if (string.IsNullOrWhiteSpace(piece))
            {
                return "-";
            }

            if (IsInternationalChess(session))
            {
                return piece.ToUpperInvariant() switch
                {
                    "K" => "king",
                    "Q" => "queen",
                    "R" => "rook",
                    "B" => "bishop",
                    "N" => "knight",
                    "P" => "pawn",
                    _ => piece
                };
            }

            return piece switch
            {
                "K" => "red general",
                "A" => "red advisor",
                "E" => "red elephant",
                "H" => "red horse",
                "R" => "red rook",
                "C" => "red cannon",
                "P" => "red pawn",
                "k" => "black general",
                "a" => "black advisor",
                "e" => "black elephant",
                "h" => "black horse",
                "r" => "black rook",
                "c" => "black cannon",
                "p" => "black pawn",
                _ => piece
            };
        }

        private static string EnglishPhase(string phaseLabel)
        {
            return phaseLabel switch
            {
                "开局" => "opening",
                "中局" => "middlegame",
                _ => "endgame",
            };
        }

        private enum BanterTrigger
        {
            Move,
            Undo,
        }

        private readonly struct BanterContext
        {
            public BanterContext(string phaseLabel, int referenceScore)
            {
                PhaseLabel = phaseLabel;
                ReferenceScore = referenceScore;
            }

            public string PhaseLabel { get; }
            public int ReferenceScore { get; }
        }
    }
}
