using Godot;
using System;

namespace ChessAI.Module.Services
{
    /// <summary>
    /// Prompt加载器
    /// 从resources/prompts/目录读取Prompt模板
    /// </summary>
    public class PromptLoader
    {
        /// <summary>
        /// 加载系统Prompt
        /// </summary>
        public string LoadSystemPrompt(string promptFileName)
        {
            var filePath = AI_Module_Config.PROMPT_FOLDER_PATH + promptFileName;
            var fallbackFileName = promptFileName.Replace("_en.txt", ".txt");
            var fallbackPath = AI_Module_Config.PROMPT_FOLDER_PATH + fallbackFileName;

            if (AI_Module_Config.DEBUG_MODE)
            {
                GD.Print($"[PromptLoader] 加载Prompt文件: {filePath}");
            }

            try
            {
                var file = FileAccess.Open(filePath, FileAccess.ModeFlags.Read);
                if (file == null)
                {
                    if (fallbackFileName != promptFileName)
                    {
                        GD.PrintErr($"[PromptLoader] 无法打开文件: {filePath}; fallback={fallbackPath}");
                        file = FileAccess.Open(fallbackPath, FileAccess.ModeFlags.Read);
                    }
                    if (file == null)
                    {
                        GD.PrintErr($"[PromptLoader] 无法打开文件: {filePath}");
                        return "";
                    }
                }

                var content = file.GetAsText();
                file.Close();

                if (AI_Module_Config.DEBUG_MODE)
                {
                    GD.Print($"[PromptLoader] 成功加载Prompt，长度: {content.Length}");
                }

                return content;
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[PromptLoader] 加载Prompt失败: {ex.Message}");
                return "";
            }
        }

        /// <summary>
        /// 加载聊天系统Prompt
        /// </summary>
        public string LoadChatPrompt()
        {
            return LoadSystemPrompt(AI_Module_Config.GetChatPromptFileName());
        }

        /// <summary>
        /// 加载主动搭话系统Prompt
        /// </summary>
        public string LoadBanterPrompt()
        {
            return LoadSystemPrompt(AI_Module_Config.GetBanterPromptFileName());
        }

        /// <summary>
        /// 加载复盘系统Prompt
        /// </summary>
        public string LoadReviewPrompt()
        {
            return LoadSystemPrompt(AI_Module_Config.GetReviewPromptFileName());
        }
    }
}
