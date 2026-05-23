using Godot;
using System;
using System.Threading.Tasks;
using ChessAI.DataModels;
using ChessAI.Module.Services;

namespace ChessAI.Module.Core
{
    /// <summary>
    /// 闲聊Agent
    /// 处理玩家的普通聊天消息
    /// </summary>
    public class ChatAgent
    {
        private readonly LlmApiService _llmService;
        private readonly PromptLoader _promptLoader;
        private readonly MemoryService _memoryService;

        public ChatAgent(LlmApiService llmService, PromptLoader promptLoader, MemoryService memoryService)
        {
            _llmService = llmService;
            _promptLoader = promptLoader;
            _memoryService = memoryService;
        }

        /// <summary>
        /// 处理玩家消息
        /// </summary>
        public async Task<string> ProcessMessageAsync(string message, GameSession session)
        {
            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print("[ChatAgent] 处理玩家消息");
            }

            var systemPrompt = _promptLoader.LoadChatPrompt();
            var memoryPrompt = _memoryService?.BuildPromptMemory(session) ?? "";
            var userPrompt = BuildUserPrompt(message, session, memoryPrompt);

            var response = await _llmService.CompleteChatAsync(systemPrompt, userPrompt, AI_Module_Config.CHAT_MODEL);

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[ChatAgent] AI响应: {response}");
            }

            _memoryService?.RecordAIResponse(session, "chat", message, response);

            return response;
        }

        /// <summary>
        /// 构建用户Prompt
        /// </summary>
        private string BuildUserPrompt(string message, GameSession session, string memoryPrompt)
        {
            if (AI_Module_Config.UseEnglishPrompts())
            {
                return BuildEnglishUserPrompt(message, session, memoryPrompt);
            }

            var promptBuilder = new System.Text.StringBuilder();

            promptBuilder.AppendLine("当前游戏状态:");
            promptBuilder.AppendLine($"- 当前FEN: {session.CurrentFEN}");
            promptBuilder.AppendLine($"- 当前行棋方: {session.CurrentPlayerName}");
            promptBuilder.AppendLine($"- 玩家控制方: {session.HumanSideName}");
            promptBuilder.AppendLine($"- 我执方/AI对手方: {session.GetSideName(OpponentSide(session.HumanSide))}");
            promptBuilder.AppendLine("- 称谓规则: 你=玩家；我=玩家的对手。");
            promptBuilder.AppendLine($"- 游戏状态: {session.GameStatus}");
            promptBuilder.AppendLine($"- 走法数量: {session.GetMoveCount()}");

            promptBuilder.AppendLine($"- \u6e38\u620f\u7ed3\u679c: {FormatGameResult(session)}");
            var humanOutcome = DescribeHumanOutcome(session);
            if (!string.IsNullOrWhiteSpace(humanOutcome))
            {
                promptBuilder.AppendLine($"- \u73a9\u5bb6\u5f53\u524d\u7ed3\u5c40: {humanOutcome}");
            }

            if (session.GetMoveCount() > 0)
            {
                var latestMove = session.MoveHistory[session.MoveHistory.Count - 1];
                promptBuilder.AppendLine();
                promptBuilder.AppendLine($"上一手事实: {FormatMoveFact(latestMove, session)}");
                promptBuilder.AppendLine("\n最近走法:");
                var recentMoves = Math.Min(5, session.MoveHistory.Count);
                for (int i = session.MoveHistory.Count - recentMoves; i < session.MoveHistory.Count; i++)
                {
                    var move = session.MoveHistory[i];
                    promptBuilder.AppendLine(
                        $"  第{SafePly(move, i)}手，第{move.MoveNumber}回合，{session.GetSideName(move.Side)}: {ReadableMove(move)}；" +
                        $"移动棋子={ChinesePieceName(move.Piece)}；被吃掉的棋子={ChinesePieceName(move.CapturedPiece)}");
                }
            }

            promptBuilder.AppendLine($"\n玩家消息: {message}");

            MemoryService.AppendMemoryPrompt(promptBuilder, memoryPrompt);

            return promptBuilder.ToString();
        }

        private string BuildEnglishUserPrompt(string message, GameSession session, string memoryPrompt)
        {
            var promptBuilder = new System.Text.StringBuilder();

            promptBuilder.AppendLine("Current game state:");
            promptBuilder.AppendLine($"- Current FEN: {session.CurrentFEN}");
            promptBuilder.AppendLine($"- Side to move: {SideName(session.CurrentPlayer, session)}");
            promptBuilder.AppendLine($"- Human side: {SideName(session.HumanSide, session)}");
            promptBuilder.AppendLine($"- My side / AI opponent side: {SideName(OpponentSide(session.HumanSide), session)}");
            promptBuilder.AppendLine("- Pronoun rule: you=human player; I=the opponent across the board.");
            promptBuilder.AppendLine($"- Game status: {NormalizeStatus(session.GameStatus)}");
            promptBuilder.AppendLine($"- Move count: {session.GetMoveCount()}");
            promptBuilder.AppendLine($"- Game result: {FormatGameResult(session)}");

            var humanOutcome = DescribeHumanOutcome(session);
            if (!string.IsNullOrWhiteSpace(humanOutcome))
            {
                promptBuilder.AppendLine($"- Human outcome: {humanOutcome}");
            }

            if (session.GetMoveCount() > 0)
            {
                promptBuilder.AppendLine();
                var latestMove = session.MoveHistory[session.MoveHistory.Count - 1];
                promptBuilder.AppendLine($"Latest move fact: {FormatEnglishMoveFact(latestMove, session)}");
                promptBuilder.AppendLine();
                promptBuilder.AppendLine("Recent moves:");
                var recentMoves = Math.Min(5, session.MoveHistory.Count);
                for (int i = session.MoveHistory.Count - recentMoves; i < session.MoveHistory.Count; i++)
                {
                    var move = session.MoveHistory[i];
                    var notation = string.IsNullOrWhiteSpace(move.CoordinateNotation)
                        ? move.ChineseNotation
                        : move.CoordinateNotation;
                    promptBuilder.AppendLine(
                        $"  Ply {SafePly(move, i)}, move {move.MoveNumber}, {SideName(move.Side, session)}: {notation}; " +
                        $"moving_piece={EnglishPieceName(move.Piece, session)}; captured_piece={EnglishPieceName(move.CapturedPiece, session)}");
                }
            }

            promptBuilder.AppendLine();
            promptBuilder.AppendLine($"Player message: {message}");
            MemoryService.AppendMemoryPrompt(promptBuilder, memoryPrompt);

            return promptBuilder.ToString();
        }

        private static string FormatGameResult(GameSession session)
        {
            if (AI_Module_Config.UseEnglishPrompts())
            {
                return NormalizeResult(session.GameResult);
            }
            return string.IsNullOrWhiteSpace(session.GameResult)
                ? "\u672a\u7ed3\u675f"
                : session.GameResult;
        }

        private static string DescribeHumanOutcome(GameSession session)
        {
            var result = session.GameResult ?? "";
            if (string.IsNullOrWhiteSpace(result))
            {
                return "";
            }
            if (AI_Module_Config.UseEnglishPrompts())
            {
                if (IsDrawResult(result))
                {
                    return "Draw";
                }
                if (IsFirstSideWin(result))
                {
                    return session.HumanSide == 0 ? "Won" : "Lost";
                }
                if (IsSecondSideWin(result))
                {
                    return session.HumanSide == 1 ? "Won" : "Lost";
                }
                return "";
            }
            if (result.Contains("\u548c\u68cb"))
            {
                return "\u548c\u68cb";
            }
            if (result.Contains("\u7ea2\u80dc") || result.Contains("\u767d\u80dc"))
            {
                return session.HumanSide == 0 ? "\u5df2\u83b7\u80dc" : "\u5df2\u8f93\u6389";
            }
            if (result.Contains("\u9ed1\u80dc"))
            {
                return session.HumanSide == 1 ? "\u5df2\u83b7\u80dc" : "\u5df2\u8f93\u6389";
            }

            return "";
        }

        private static int OpponentSide(int humanSide)
        {
            return humanSide == 1 ? 0 : 1;
        }

        private static int SafePly(MoveRecord move, int index)
        {
            return move.PlyIndex > 0 ? move.PlyIndex : index + 1;
        }

        private static string ReadableMove(MoveRecord move)
        {
            if (move == null)
            {
                return "-";
            }

            if (!string.IsNullOrWhiteSpace(move.ChineseNotation))
            {
                return move.ChineseNotation;
            }

            if (!string.IsNullOrWhiteSpace(move.CoordinateNotation))
            {
                return move.CoordinateNotation;
            }

            return $"{move.FromIndex}->{move.ToIndex}";
        }

        private static string EmptyAsDash(string value)
        {
            return string.IsNullOrWhiteSpace(value) ? "-" : value;
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

        private static string FormatEnglishMoveFact(MoveRecord move, GameSession session)
        {
            move ??= new MoveRecord();
            var side = SideName(move.Side, session);
            var movingPiece = EnglishPieceName(move.Piece, session);
            var capturedPiece = EnglishPieceName(move.CapturedPiece, session);
            var readableMove = ReadableMove(move);
            return string.IsNullOrWhiteSpace(move.CapturedPiece)
                ? $"{side} moved {movingPiece}: {readableMove}; no piece was captured."
                : $"{side} moved {movingPiece}: {readableMove}, and the captured piece was {capturedPiece}. Do not confuse the moving piece with the captured piece.";
        }

        private static string SideName(int side, GameSession session)
        {
            var variant = session.GameVariant ?? "";
            var isChess = variant.Contains("Chess", StringComparison.OrdinalIgnoreCase) ||
                variant.Contains("\u56fd\u9645\u8c61\u68cb");
            if (AI_Module_Config.UseEnglishPrompts())
            {
                return isChess
                    ? (side == 0 ? "White" : "Black")
                    : (side == 0 ? "Red" : "Black");
            }
            return session.GetSideName(side);
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

        private static bool IsInternationalChess(GameSession session)
        {
            var variant = session.GameVariant ?? "";
            return variant.Contains("国际象棋", StringComparison.Ordinal) ||
                variant.Contains("\u56fd\u9645\u8c61\u68cb", StringComparison.Ordinal) ||
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

        private static string NormalizeStatus(string status)
        {
            if (string.IsNullOrWhiteSpace(status))
            {
                return "In progress";
            }
            if (status.Contains("\u7ed3\u675f") || status.Contains("finished", StringComparison.OrdinalIgnoreCase))
            {
                return "Finished";
            }
            return "In progress";
        }

        private static string NormalizeResult(string result)
        {
            if (string.IsNullOrWhiteSpace(result))
            {
                return "Not finished";
            }
            if (IsDrawResult(result))
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

        private static bool IsDrawResult(string result)
        {
            return result.Contains("Draw", StringComparison.OrdinalIgnoreCase) || result.Contains("\u548c\u68cb");
        }

        private static bool IsFirstSideWin(string result)
        {
            return result.Contains("Red", StringComparison.OrdinalIgnoreCase) ||
                result.Contains("White", StringComparison.OrdinalIgnoreCase) ||
                result.Contains("\u7ea2\u80dc") ||
                result.Contains("\u767d\u80dc");
        }

        private static bool IsSecondSideWin(string result)
        {
            return result.Contains("Black", StringComparison.OrdinalIgnoreCase) || result.Contains("\u9ed1\u80dc");
        }
    }
}
