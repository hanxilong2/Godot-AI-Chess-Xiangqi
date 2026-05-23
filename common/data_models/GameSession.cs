using System;
using System.Collections.Generic;

namespace ChessAI.DataModels
{
    /// <summary>
    /// 整局游戏会话数据
    /// 对应GDScript中的棋局状态和临时代码输出的游戏状态信息
    /// </summary>
    public class GameSession
    {
        /// <summary>
        /// 当前FEN字符串
        /// </summary>
        public string CurrentFEN { get; set; } = "";

        /// <summary>
        /// 初始FEN字符串
        /// </summary>
        public string InitialFEN { get; set; } = "";

        /// <summary>
        /// 棋种名称（中国象棋/国际象棋）
        /// </summary>
        public string GameVariant { get; set; } = "中国象棋";

        /// <summary>
        /// 棋盘数组（中国象棋为90个位置，国际象棋为64个位置）
        /// </summary>
        public string[] Board { get; set; } = new string[90];

        /// <summary>
        /// 当前行棋方 (0=先手/红方/白方, 1=后手/黑方)
        /// </summary>
        public int CurrentPlayer { get; set; } = 0;

        /// <summary>
        /// 玩家控制的方 (0=先手/红方/白方, 1=后手/黑方)
        /// </summary>
        public int HumanSide { get; set; } = 0;

        /// <summary>
        /// 半回合计数器
        /// </summary>
        public int HalfmoveClock { get; set; } = 0;

        /// <summary>
        /// 完整回合数
        /// </summary>
        public int FullmoveNumber { get; set; } = 1;

        /// <summary>
        /// 走法历史记录
        /// </summary>
        public List<MoveRecord> MoveHistory { get; set; } = new List<MoveRecord>();

        /// <summary>
        /// 游戏状态（进行中/结束/暂停）
        /// </summary>
        public string GameStatus { get; set; } = "进行中";

        /// <summary>
        /// 游戏结果（红胜/黑胜/和棋）
        /// </summary>
        public string GameResult { get; set; } = "";

        public string GameEndType { get; set; } = "";

        public string TimeControl { get; set; } = "";

        public string TimeControlDescription { get; set; } = "";

        public double ClockInitialSeconds { get; set; } = 0;

        public double ClockIncrementSeconds { get; set; } = 0;

        public double WhiteClockRemainingSeconds { get; set; } = 0;

        public double BlackClockRemainingSeconds { get; set; } = 0;

        public string WhiteClockRemaining { get; set; } = "";

        public string BlackClockRemaining { get; set; } = "";

        public int ClockActiveSide { get; set; } = -1;

        public bool ClockRunning { get; set; } = false;

        /// <summary>
        /// 游戏开始时间
        /// </summary>
        public DateTime StartTime { get; set; } = DateTime.Now;

        /// <summary>
        /// 游戏结束时间
        /// </summary>
        public DateTime? EndTime { get; set; }

        /// <summary>
        /// AI是否启用
        /// </summary>
        public bool AIEnabled { get; set; } = true;

        /// <summary>
        /// 会话ID（用于标识唯一游戏）
        /// </summary>
        public string SessionId { get; set; } = Guid.NewGuid().ToString();

        /// <summary>
        /// 获取当前行棋方名称
        /// </summary>
        public string CurrentPlayerName => GetSideName(CurrentPlayer);

        /// <summary>
        /// 获取玩家控制的方名称
        /// </summary>
        public string HumanSideName => GetSideName(HumanSide);

        /// <summary>
        /// 是否是玩家回合
        /// </summary>
        public bool IsPlayerTurn => CurrentPlayer == HumanSide;

        /// <summary>
        /// 是否是AI回合
        /// </summary>
        public bool IsAITurn => AIEnabled && CurrentPlayer != HumanSide;

        /// <summary>
        /// 游戏是否结束
        /// </summary>
        public bool IsGameOver =>
            string.Equals(GameStatus, "结束", StringComparison.Ordinal) ||
            string.Equals(GameStatus, "Finished", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(GameStatus, "Game over", StringComparison.OrdinalIgnoreCase);

        /// <summary>
        /// 获取游戏时长
        /// </summary>
        public TimeSpan GetGameDuration()
        {
            var endTime = EndTime ?? DateTime.Now;
            return endTime - StartTime;
        }

        /// <summary>
        /// 获取走法数量
        /// </summary>
        public int GetMoveCount() => MoveHistory.Count;

        /// <summary>
        /// 获取红方走法数量
        /// </summary>
        public int GetRedMoveCount()
        {
            int count = 0;
            foreach (var move in MoveHistory)
            {
                if (move.Side == 0) count++;
            }
            return count;
        }

        /// <summary>
        /// 获取黑方走法数量
        /// </summary>
        public int GetBlackMoveCount()
        {
            int count = 0;
            foreach (var move in MoveHistory)
            {
                if (move.Side == 1) count++;
            }
            return count;
        }

        /// <summary>
        /// 获取指定方走法数量
        /// </summary>
        public int GetSideMoveCount(int side)
        {
            int count = 0;
            foreach (var move in MoveHistory)
            {
                if (move.Side == side) count++;
            }
            return count;
        }

        /// <summary>
        /// 获取当前棋种下的阵营名称
        /// </summary>
        public string GetSideName(int side)
        {
            var normalizedVariant = (GameVariant ?? "").Trim();
            if (normalizedVariant.Contains("\u56fd\u9645\u8c61\u68cb") || normalizedVariant.Contains("Chess"))
            {
                return side == 0 ? "\u767d\u65b9" : "\u9ed1\u65b9";
            }
            if (normalizedVariant.Contains("国际象棋") || normalizedVariant.Contains("Chess"))
            {
                return side == 0 ? "白方" : "黑方";
            }

            return side == 0 ? "红方" : "黑方";
        }

        /// <summary>
        /// 添加走法记录
        /// </summary>
        public void AddMove(MoveRecord move)
        {
            move.MoveNumber = (MoveHistory.Count + 2) / 2;
            MoveHistory.Add(move);
        }

        /// <summary>
        /// 获取格式化的走法历史（用于显示）
        /// </summary>
        public string GetFormattedMoveHistory()
        {
            if (MoveHistory.Count == 0)
            {
                return "(暂无落子记录)";
            }

            var result = new System.Text.StringBuilder();
            foreach (var move in MoveHistory)
            {
                result.AppendLine($"  第{move.MoveNumber}回合 {GetSideName(move.Side)}: {move.ChineseNotation}");
            }
            return result.ToString();
        }

        /// <summary>
        /// 转换为字典（用于JSON序列化）
        /// </summary>
        public object ToDictionary()
        {
            return new
            {
                session_id = SessionId,
                game_variant = GameVariant,
                current_fen = CurrentFEN,
                initial_fen = InitialFEN,
                current_player = CurrentPlayer,
                human_side = HumanSide,
                halfmove_clock = HalfmoveClock,
                fullmove_number = FullmoveNumber,
                game_status = GameStatus,
                game_result = GameResult,
                game_end_type = GameEndType,
                time_control = TimeControl,
                time_control_description = TimeControlDescription,
                clock_initial_seconds = ClockInitialSeconds,
                clock_increment_seconds = ClockIncrementSeconds,
                white_clock_remaining_seconds = WhiteClockRemainingSeconds,
                black_clock_remaining_seconds = BlackClockRemainingSeconds,
                white_clock_remaining = WhiteClockRemaining,
                black_clock_remaining = BlackClockRemaining,
                clock_active_side = ClockActiveSide,
                clock_running = ClockRunning,
                ai_enabled = AIEnabled,
                start_time = StartTime.ToString("yyyy-MM-dd HH:mm:ss"),
                end_time = EndTime?.ToString("yyyy-MM-dd HH:mm:ss"),
                move_count = MoveHistory.Count,
                moves = new List<object>(MoveHistory.ConvertAll(m => m.ToDictionary()))
            };
        }
    }
}
