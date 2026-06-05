using System;
using System.Collections.Generic;

namespace ChessAI.DataModels
{
    /// <summary>
    /// 单步走法数据记录
    /// 对应GDScript中的XiangqiMove和临时代码输出的走法信息
    /// </summary>
    public class MoveRecord
    {
        /// <summary>
        /// 起始位置索引 (0-89)
        /// </summary>
        public int FromIndex { get; set; } = -1;

        /// <summary>
        /// 目标位置索引 (0-89)
        /// </summary>
        public int ToIndex { get; set; } = -1;

        /// <summary>
        /// 移动的棋子 (如 "K", "A", "E", "H", "R", "C", "P" 为红方，小写为黑方)
        /// </summary>
        public string Piece { get; set; } = "";

        /// <summary>
        /// 被吃掉的棋子
        /// </summary>
        public string CapturedPiece { get; set; } = "";

        /// <summary>
        /// 标志位 (1=吃子, 2=将军, 4=将死, 8=特殊)
        /// </summary>
        public int Flags { get; set; } = 0;

        /// <summary>
        /// 中国象棋记谱法（如 "炮二平五"）
        /// </summary>
        public string ChineseNotation { get; set; } = "";

        /// <summary>
        /// 坐标记谱法（如 "h2e2"）
        /// </summary>
        public string CoordinateNotation { get; set; } = "";

        /// <summary>
        /// 行棋方 (0=红方, 1=黑方)
        /// </summary>
        public int Side { get; set; } = 0;

        public int PlyIndex { get; set; } = 0;

        /// <summary>
        /// 回合数
        /// </summary>
        public int MoveNumber { get; set; } = 1;

        /// <summary>
        /// 评估分数（皮卡鱼引擎返回）
        /// </summary>
        public int EvaluationScore { get; set; } = 0;

        /// <summary>
        /// Teaching trigger/reference score. When absent, the AI falls back to EvaluationScore or Pikafish analysis.
        /// </summary>
        public int TeachingScore { get; set; } = 0;

        /// <summary>
        /// 最佳走法（皮卡鱼引擎推荐）
        /// </summary>
        public string BestMove { get; set; } = "";

        /// <summary>
        /// 皮卡鱼原始分析数据（如前后局面评分、WDL、搜索深度、PV等）
        /// </summary>
        public Dictionary<string, object> PikafishAnalysis { get; set; } = new Dictionary<string, object>();

        /// <summary>
        /// 是否有效
        /// </summary>
        public bool IsValid => FromIndex >= 0 && FromIndex < 90 && ToIndex >= 0 && ToIndex < 90;

        /// <summary>
        /// 是否吃子
        /// </summary>
        public bool IsCapture => !string.IsNullOrEmpty(CapturedPiece) || (Flags & 1) != 0;

        /// <summary>
        /// 是否将军
        /// </summary>
        public bool IsCheck => (Flags & 2) != 0;

        /// <summary>
        /// 是否将死
        /// </summary>
        public bool IsCheckmate => (Flags & 4) != 0;

        /// <summary>
        /// 获取行棋方名称
        /// </summary>
        public string SideName => Side == 0 ? "红方" : "黑方";

        /// <summary>
        /// 获取棋子名称
        /// </summary>
        public string PieceName => GetPieceDisplayName(Piece);

        /// <summary>
        /// 获取被吃棋子名称
        /// </summary>
        public string CapturedPieceName => GetPieceDisplayName(CapturedPiece);

        /// <summary>
        /// 转换为字典（用于JSON序列化）
        /// </summary>
        public object ToDictionary()
        {
            return new
            {
                from_index = FromIndex,
                to_index = ToIndex,
                piece = Piece,
                captured_piece = CapturedPiece,
                flags = Flags,
                chinese_notation = ChineseNotation,
                coordinate_notation = CoordinateNotation,
                side = Side,
                ply_index = PlyIndex,
                move_number = MoveNumber,
                evaluation_score = EvaluationScore,
                teaching_score = TeachingScore,
                best_move = BestMove,
                pikafish_analysis = PikafishAnalysis
            };
        }

        /// <summary>
        /// 获取棋子显示名称
        /// </summary>
        private static string GetPieceDisplayName(string piece)
        {
            if (string.IsNullOrEmpty(piece)) return "";
            return piece switch
            {
                "K" => "帅",
                "A" => "仕",
                "E" => "相",
                "H" => "马",
                "R" => "车",
                "C" => "炮",
                "P" => "兵",
                "k" => "将",
                "a" => "士",
                "e" => "象",
                "h" => "马",
                "r" => "车",
                "c" => "炮",
                "p" => "卒",
                _ => piece
            };
        }
    }
}
