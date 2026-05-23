using System;

namespace ChessAI.DataModels
{
    /// <summary>
    /// 中国象棋AI接口契约
    /// 游戏框架通过此接口与AI模块通信
    /// </summary>
    public interface IChessAI
    {
        /// <summary>
        /// 玩家发送消息时的回调
        /// </summary>
        /// <param name="message">玩家消息</param>
        /// <param name="session">当前游戏会话</param>
        void OnPlayerMessage(string message, GameSession session);

        /// <summary>
        /// 玩家走棋时的回调
        /// </summary>
        /// <param name="moveRecord">走棋记录</param>
        /// <param name="session">当前游戏会话</param>
        void OnMovePlayed(MoveRecord moveRecord, GameSession session);

        /// <summary>
        /// 游戏结束时的回调
        /// </summary>
        /// <param name="session">游戏会话</param>
        /// <param name="result">游戏结果（红胜/黑胜/和棋）</param>
        void OnGameEnded(GameSession session, string result);

        /// <summary>
        /// AI响应事件
        /// </summary>
        event EventHandler<AIResponseEventArgs> OnAIResponse;

        /// <summary>
        /// 复盘生成完成事件
        /// </summary>
        event EventHandler<ReviewGeneratedEventArgs> OnReviewGenerated;
    }

    /// <summary>
    /// AI响应事件参数
    /// </summary>
    public class AIResponseEventArgs : EventArgs
    {
        /// <summary>
        /// 响应类型（聊天/教学/其他）
        /// </summary>
        public string ResponseType { get; set; }

        /// <summary>
        /// 响应内容
        /// </summary>
        public string Content { get; set; }

        /// <summary>
        /// 是否需要显示在UI上
        /// </summary>
        public bool ShowInUI { get; set; } = true;
    }

    /// <summary>
    /// 复盘生成完成事件参数
    /// </summary>
    public class ReviewGeneratedEventArgs : EventArgs
    {
        /// <summary>
        /// 复盘报告内容
        /// </summary>
        public string ReviewContent { get; set; }

        /// <summary>
        /// 复盘数据（JSON格式）
        /// </summary>
        public string ReviewData { get; set; }

        /// <summary>
        /// 关键失误列表
        /// </summary>
        public string[] CriticalMistakes { get; set; } = Array.Empty<string>();
    }
}