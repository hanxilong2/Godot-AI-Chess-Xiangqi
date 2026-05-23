using Godot;
using System;
using System.IO;
using System.Text;

namespace ChessAI.Module
{
    /// <summary>
    /// AI模块配置
    /// 包含API密钥、URL、Prompt路径等配置信息
    /// </summary>
    public static class AI_Module_Config
    {
        /// <summary>
        /// API密钥环境变量名。
        /// </summary>
        public const string API_KEY_ENV_VAR = "CHESS_AI_API_KEY";

        /// <summary>
        /// 阿里云百炼 / DashScope 官方环境变量名。
        /// </summary>
        public const string DASHSCOPE_API_KEY_ENV_VAR = "DASHSCOPE_API_KEY";

        private static string _runtimeApiKey = "";
        private static bool _persistentApiKeyLoaded = false;
        private static string _persistentApiKey = "";
        private static int _banterPlayerSide = 0;
        private static int _chatPlayerSide = 0;
        private static int _reviewPlayerSide = 0;

        /// <summary>
        /// API基础URL（阿里云百炼 / DashScope OpenAI兼容接口，北京地域）
        /// </summary>
        public const string API_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions";

        /// <summary>
        /// 聊天模型名称（Qwen3.5-Flash）
        /// </summary>
        public const string CHAT_MODEL = "qwen3.5-flash";

        /// <summary>
        /// 主动搭话模型名称（Qwen3.5-Plus）
        /// </summary>
        public const string BANTER_MODEL = "qwen3.5-plus";

        /// <summary>
        /// Proactive banter trigger chance. 0.5 means move/undo events speak about half the time.
        /// </summary>
        public const double BANTER_TRIGGER_PROBABILITY = 0.5;

        /// <summary>
        /// 复盘模型名称（Qwen3.5-Plus）
        /// </summary>
        public const string REVIEW_MODEL = "qwen3.5-plus";

        /// <summary>
        /// Agent工具选择模型名称。
        /// </summary>
        public const string AGENT_MODEL = "qwen3.5-flash";

        /// <summary>
        /// 模型名称（默认使用聊天模型）
        /// </summary>
        public const string MODEL_NAME = CHAT_MODEL;

        /// <summary>
        /// Prompt文件夹路径
        /// </summary>
        public const string PROMPT_FOLDER_PATH = "res://chess_ai_module/resources/prompts/";

        /// <summary>
        /// 数据存储文件夹路径
        /// </summary>
        public const string STORAGE_FOLDER_PATH = "user://chess_ai_data/";

        public const string CURRENT_MEMORY_FILE_PATH = STORAGE_FOLDER_PATH + "current_game_memory.md";

        public const string GLOBAL_MEMORY_FILE_PATH = STORAGE_FOLDER_PATH + "global_game_memory.md";

        public const string GLOBAL_CHESS_MEMORY_FILE_PATH = STORAGE_FOLDER_PATH + "global_chess_game_memory.md";

        public const string GLOBAL_XIANGQI_MEMORY_FILE_PATH = STORAGE_FOLDER_PATH + "global_xiangqi_game_memory.md";

        public const string MEMORY_FILE_PATH = CURRENT_MEMORY_FILE_PATH;

        public const int GLOBAL_MEMORY_ENTRY_LIMIT = 50;

        public const int CURRENT_MEMORY_INTERACTION_LIMIT = 30;

        public const int MEMORY_SUMMARY_MAX_TOKENS = 520;

        /// <summary>
        /// 本地AI设置文件路径。位于Godot user:// 下，不会写入项目源码。
        /// </summary>
        public const string API_SETTINGS_FILE_PATH = STORAGE_FOLDER_PATH + "ai_settings.cfg";

        private const string API_SETTINGS_SECTION = "api";
        private const string API_KEY_SETTING = "key";

        /// <summary>
        /// API请求超时时间（毫秒）
        /// </summary>
        public const int API_TIMEOUT_MS = 30000;

        /// <summary>
        /// API重试次数
        /// </summary>
        public const int API_RETRY_COUNT = 3;

        /// <summary>
        /// API重试间隔（毫秒）
        /// </summary>
        public const int API_RETRY_DELAY_MS = 1000;

        /// <summary>
        /// 最大上下文token数
        /// </summary>
        public const int MAX_CONTEXT_TOKENS = 4096;

        /// <summary>
        /// 温度参数（控制输出随机性）
        /// </summary>
        public const double TEMPERATURE = 0.7;

        /// <summary>
        /// 最大生成token数
        /// </summary>
        public const int MAX_TOKENS = 1024;

        /// <summary>
        /// 主动搭话回复最大生成token数。搭话提示需要保持在50到100个汉字。
        /// </summary>
        public const int BANTER_MAX_TOKENS = 180;

        /// <summary>
        /// Agent工具选择最大生成token数。
        /// </summary>
        public const int AGENT_MAX_TOKENS = 256;

        /// <summary>
        /// Agent工具选择温度。工具选择应比具体回复更稳定。
        /// </summary>
        public const double AGENT_TEMPERATURE = 0.2;

        /// <summary>
        /// 红方阵营编号。
        /// </summary>
        public const int SIDE_RED = 0;

        /// <summary>
        /// 黑方阵营编号。
        /// </summary>
        public const int SIDE_BLACK = 1;

        /// <summary>
        /// 是否启用调试模式
        /// </summary>
        public static readonly bool DEBUG_MODE = false;

        /// <summary>
        /// 是否打印Prompt、玩家输入和AI回复正文。发布版本默认关闭，避免日志中留下敏感内容。
        /// </summary>
        public static readonly bool VERBOSE_CONTENT_LOGGING = false;

        /// <summary>
        /// 获取实际使用的API密钥。优先使用游戏内运行时设置，其次读取环境变量，最后读取本地设置文件。
        /// </summary>
        public static string GetApiKey()
        {
            if (!string.IsNullOrWhiteSpace(_runtimeApiKey))
            {
                return NormalizeApiKey(_runtimeApiKey);
            }

            var envKey = System.Environment.GetEnvironmentVariable(API_KEY_ENV_VAR);
            if (!string.IsNullOrWhiteSpace(envKey))
            {
                return NormalizeApiKey(envKey);
            }

            var dashScopeEnvKey = System.Environment.GetEnvironmentVariable(DASHSCOPE_API_KEY_ENV_VAR);
            if (!string.IsNullOrWhiteSpace(dashScopeEnvKey))
            {
                return NormalizeApiKey(dashScopeEnvKey);
            }

            return GetPersistentApiKey();
        }

        /// <summary>
        /// 规范化玩家粘贴的API Key。允许误粘Bearer前缀、引号和空白字符。
        /// </summary>
        public static string NormalizeApiKey(string apiKey)
        {
            if (string.IsNullOrWhiteSpace(apiKey))
            {
                return "";
            }

            var normalized = apiKey.Trim().Trim('"', '\'');
            if (normalized.StartsWith("Bearer", StringComparison.OrdinalIgnoreCase) && normalized.Length > "Bearer".Length && char.IsWhiteSpace(normalized["Bearer".Length]))
            {
                normalized = normalized.Substring("Bearer".Length).Trim();
            }

            var builder = new StringBuilder();
            foreach (var character in normalized)
            {
                if (!char.IsWhiteSpace(character) && character != '\uFEFF' && character != '\u200B' && character != '\u200C' && character != '\u200D')
                {
                    builder.Append(character);
                }
            }

            return builder.ToString().Trim().Trim('"', '\'');
        }

        /// <summary>
        /// 返回API Key的可读校验错误。空字符串表示通过。
        /// </summary>
        public static string GetApiKeyValidationError(string apiKey)
        {
            var useEnglish = UseEnglishPrompts();
            if (string.IsNullOrWhiteSpace(apiKey))
            {
                if (useEnglish)
                {
                    return $"API key is empty. Configure {API_KEY_ENV_VAR} or {DASHSCOPE_API_KEY_ENV_VAR}, or set an API key in game.";
                }
                return $"API密钥为空，请配置环境变量 {API_KEY_ENV_VAR} 或 {DASHSCOPE_API_KEY_ENV_VAR}，或在游戏内设置API Key";
            }

            for (var index = 0; index < apiKey.Length; index++)
            {
                var character = apiKey[index];
                if (character > 0x7F)
                {
                    if (useEnglish)
                    {
                        return $"API key contains non-ASCII character U+{(int)character:X4}. Paste only the key value copied from the Bailian console, without notes, full-width spaces, web labels, or a Bearer prefix.";
                    }
                    return $"API密钥包含非ASCII字符 U+{(int)character:X4}。请只粘贴百炼控制台复制的Key本体，不要包含中文说明、全角空格、网页标签或Bearer前缀。";
                }

                if (char.IsControl(character))
                {
                    if (useEnglish)
                    {
                        return "API key contains control characters. Copy the Bailian API key value again without line breaks.";
                    }
                    return "API密钥包含控制字符。请重新复制百炼API Key本体，不要带换行。";
                }
            }

            return "";
        }

        /// <summary>
        /// 在游戏运行中设置API密钥，供后续玩家输入框调用。
        /// </summary>
        public static bool SetRuntimeApiKey(string apiKey, bool persist = false)
        {
            _runtimeApiKey = NormalizeApiKey(apiKey);
            if (persist)
            {
                return SavePersistentApiKey(_runtimeApiKey);
            }

            return true;
        }

        /// <summary>
        /// 清除游戏运行中设置的API密钥，之后会回退到环境变量或本地设置文件。
        /// </summary>
        public static bool ClearRuntimeApiKey(bool clearPersistent = false)
        {
            _runtimeApiKey = "";
            if (clearPersistent)
            {
                return ClearPersistentApiKey();
            }

            return true;
        }

        /// <summary>
        /// 当前是否已有可用API密钥。
        /// </summary>
        public static bool HasApiKey()
        {
            return !string.IsNullOrWhiteSpace(GetApiKey());
        }

        /// <summary>
        /// 设置本局搭话Prompt使用的玩家阵营。每次进入棋局时刷新一次。
        /// </summary>
        public static void SetBanterPlayerSide(int playerSide)
        {
            _banterPlayerSide = playerSide == SIDE_BLACK ? SIDE_BLACK : SIDE_RED;
        }

        /// <summary>
        /// 设置本局聊天Prompt使用的玩家阵营。每次进入棋局时刷新一次。
        /// </summary>
        public static void SetChatPlayerSide(int playerSide)
        {
            _chatPlayerSide = playerSide == SIDE_BLACK ? SIDE_BLACK : SIDE_RED;
        }

        /// <summary>
        /// 设置本局复盘Prompt使用的玩家阵营。每次进入棋局时刷新一次。
        /// </summary>
        public static void SetReviewPlayerSide(int playerSide)
        {
            _reviewPlayerSide = playerSide == SIDE_BLACK ? SIDE_BLACK : SIDE_RED;
        }

        /// <summary>
        /// 获取本局玩家阵营名称。
        /// </summary>
        public static string GetBanterPlayerSideName()
        {
            if (UseEnglishPrompts())
            {
                return _banterPlayerSide == SIDE_BLACK ? "Black" : "Red";
            }
            return _banterPlayerSide == SIDE_BLACK ? "黑方" : "红方";
        }

        /// <summary>
        /// 获取本局聊天Prompt的玩家阵营名称。
        /// </summary>
        public static string GetChatPlayerSideName()
        {
            if (UseEnglishPrompts())
            {
                return _chatPlayerSide == SIDE_BLACK ? "Black" : "Red";
            }
            return _chatPlayerSide == SIDE_BLACK ? "黑方" : "红方";
        }

        /// <summary>
        /// 获取本局复盘Prompt的玩家阵营名称。
        /// </summary>
        public static string GetReviewPlayerSideName()
        {
            if (UseEnglishPrompts())
            {
                return _reviewPlayerSide == SIDE_BLACK ? "Black" : "Red";
            }
            return _reviewPlayerSide == SIDE_BLACK ? "黑方" : "红方";
        }

        public static bool UseEnglishPrompts()
        {
            var locale = TranslationServer.GetLocale() ?? "";
            return locale.StartsWith("en", StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// 获取本局搭话Prompt文件名。
        /// </summary>
        public static string GetBanterPromptFileName()
        {
            var fileName = _banterPlayerSide == SIDE_BLACK
                ? "banter_black_system.txt"
                : "banter_red_system.txt";
            return LocalizePromptFileName(fileName);
        }

        /// <summary>
        /// 获取本局聊天Prompt文件名。
        /// </summary>
        public static string GetChatPromptFileName()
        {
            var fileName = _chatPlayerSide == SIDE_BLACK
                ? "chat_black_system.txt"
                : "chat_red_system.txt";
            return LocalizePromptFileName(fileName);
        }

        /// <summary>
        /// 获取本局复盘Prompt文件名。
        /// </summary>
        public static string GetReviewPromptFileName()
        {
            var fileName = _reviewPlayerSide == SIDE_BLACK
                ? "review_black_system.txt"
                : "review_red_system.txt";
            return LocalizePromptFileName(fileName);
        }

        private static string LocalizePromptFileName(string fileName)
        {
            if (!UseEnglishPrompts())
            {
                return fileName;
            }

            const string extension = ".txt";
            return fileName.EndsWith(extension, StringComparison.OrdinalIgnoreCase)
                ? fileName.Substring(0, fileName.Length - extension.Length) + "_en" + extension
                : fileName + "_en";
        }

        /// <summary>
        /// 获取本地设置文件中的API密钥。
        /// </summary>
        public static string GetPersistentApiKey()
        {
            if (_persistentApiKeyLoaded)
            {
                return _persistentApiKey;
            }

            _persistentApiKeyLoaded = true;
            _persistentApiKey = "";

            var config = new ConfigFile();
            var error = config.Load(API_SETTINGS_FILE_PATH);
            if (error != Error.Ok)
            {
                return "";
            }

            _persistentApiKey = NormalizeApiKey(config.GetValue(API_SETTINGS_SECTION, API_KEY_SETTING, "").ToString());
            return _persistentApiKey;
        }

        /// <summary>
        /// 将API密钥写入本地设置文件。
        /// </summary>
        public static bool SavePersistentApiKey(string apiKey)
        {
            var trimmedKey = NormalizeApiKey(apiKey);
            _persistentApiKeyLoaded = true;
            _persistentApiKey = trimmedKey;

            if (string.IsNullOrWhiteSpace(trimmedKey))
            {
                return ClearPersistentApiKey();
            }

            if (!EnsureStorageDirectory())
            {
                _persistentApiKey = "";
                return false;
            }

            var config = new ConfigFile();
            config.SetValue(API_SETTINGS_SECTION, API_KEY_SETTING, trimmedKey);
            var error = config.Save(API_SETTINGS_FILE_PATH);
            if (error != Error.Ok)
            {
                GD.PrintErr($"[AI_Module_Config] API Key保存失败: {error}; path={GetGlobalApiSettingsFilePath()}");
                _persistentApiKey = "";
                return false;
            }

            if (DEBUG_MODE)
            {
                GD.Print($"[AI_Module_Config] API Key已保存到: {GetGlobalApiSettingsFilePath()}");
            }

            return true;
        }

        /// <summary>
        /// 清除本地设置文件中的API密钥。
        /// </summary>
        public static bool ClearPersistentApiKey()
        {
            _persistentApiKeyLoaded = true;
            _persistentApiKey = "";

            if (!Godot.FileAccess.FileExists(API_SETTINGS_FILE_PATH))
            {
                return true;
            }

            var error = DirAccess.RemoveAbsolute(GetGlobalApiSettingsFilePath());
            if (error != Error.Ok)
            {
                GD.PrintErr($"[AI_Module_Config] API Key文件删除失败: {error}; path={GetGlobalApiSettingsFilePath()}");
                return false;
            }

            return true;
        }

        public static string GetGlobalApiSettingsFilePath()
        {
            return ProjectSettings.GlobalizePath(API_SETTINGS_FILE_PATH);
        }

        private static string GetGlobalStorageFolderPath()
        {
            return ProjectSettings.GlobalizePath(STORAGE_FOLDER_PATH);
        }

        private static bool EnsureStorageDirectory()
        {
            try
            {
                Directory.CreateDirectory(GetGlobalStorageFolderPath());
                return Directory.Exists(GetGlobalStorageFolderPath());
            }
            catch (Exception ex)
            {
                GD.PrintErr($"[AI_Module_Config] API Key目录创建失败: {ex.Message}; path={GetGlobalStorageFolderPath()}");
                return false;
            }
        }

        /// <summary>
        /// 获取聊天系统Prompt文件路径
        /// </summary>
        public static string GetChatPromptPath() => PROMPT_FOLDER_PATH + GetChatPromptFileName();

        /// <summary>
        /// 获取搭话系统Prompt文件路径
        /// </summary>
        public static string GetBanterPromptPath() => PROMPT_FOLDER_PATH + GetBanterPromptFileName();


        /// <summary>
        /// 获取复盘系统Prompt文件路径
        /// </summary>
        public static string GetReviewPromptPath() => PROMPT_FOLDER_PATH + GetReviewPromptFileName();
    }
}
