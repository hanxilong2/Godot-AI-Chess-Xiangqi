# Godot AI Chess Xiangqi

这是一个面向毕业设计的 Godot 棋类游戏项目。项目以 3D 咖啡馆场景为主要游玩空间，将国际象棋、中国象棋、棋局记录、AI 对话与复盘等内容组织到同一个 Godot 工程中，目标是形成一个可演示、可扩展的棋类互动游戏原型。

本项目基于开源项目 [GodotHub/siamese_chess](https://github.com/GodotHub/siamese_chess) 继续开发，并在原有 Godot + C++ GDExtension 棋类工程基础上加入中国象棋规则、人机对局、AI 交互模块和项目结构重组。

## 项目定位

- 毕设方向：Godot 游戏开发与棋类 AI 交互
- 游戏形态：3D 场景探索 + 棋盘对局 + AI 对话/复盘
- 技术栈：Godot 4.5、GDScript、C#、C++ GDExtension
- 主要内容：中国象棋对局、国际象棋场景保留、Pikafish 引擎适配、AI 角色交互、UI 与资源整合

## 主要功能

- 中国象棋棋盘、棋子、坐标、走法记录与局面状态管理
- 基于 Pikafish 的中国象棋人机对弈流程
- C++ GDExtension 中国象棋规则接口与 Godot/C# 调用封装
- AI 对话、棋局吐槽、复盘文本生成等 C# 模块
- 咖啡馆主题 3D 场景、开始菜单、设置、对话框、相机视图等游戏界面
- 国际象棋相关场景与脚本按模块整理保留

## 在 Godot 中运行

### 1. 准备运行环境

请优先使用以下环境打开项目：

- Godot 4.5 .NET 版本
- .NET 8 SDK
- Windows 64 位系统

项目使用了 GDScript、C# 和 C++ GDExtension。普通版 Godot 无法编译和加载 C# 脚本，因此需要下载带 `.NET` 标识的 Godot 编辑器版本。

### 2. 获取项目

从 GitHub 克隆或下载项目后，确认根目录中包含以下关键文件：

- `project.godot`
- `ChessCafe.csproj`
- `siamese.gdextension`
- `bin/libsiamese.windows.template_debug.x86_64.dll`
- `bin/libsiamese.windows.template_release.x86_64.dll`
- `resource/xiangqi/bin/pikafish/pikafish.exe`
- `resource/xiangqi/bin/pikafish/pikafish.nnue`

如果使用 Git 克隆，并且后续需要重新编译 C++ 扩展，可以同步子模块：

```powershell
git submodule update --init --recursive
```

仅在 Windows 上直接运行游戏时，通常不需要重新编译 C++ 扩展，因为仓库中已经包含当前使用的 Windows 动态库。

### 3. 用 Godot 打开工程

1. 启动 Godot 4.5 .NET 编辑器。
2. 在项目管理器中点击 `Import`。
3. 选择本仓库根目录下的 `project.godot`。
4. 导入后打开项目，等待 Godot 完成资源扫描和 `.import` 文件生成。
5. 如果编辑器提示构建 C# 项目，选择构建；也可以在编辑器右上角点击 `Build` 手动构建。

首次打开时，模型、贴图、音频和 C# 脚本导入会花一些时间。导入期间不要急着运行场景，等编辑器底部不再显示导入任务后再启动。

### 4. 启动游戏

项目默认主场景已经配置为：

- `scene/ui/start_menu.tscn`

在 Godot 编辑器中点击右上角运行按钮，或按 `F5`，即可从主菜单启动。

也可以直接运行指定场景：

- 中国象棋主场景：`resource/xiangqi/scene/game/xiangqi_cafe_game.tscn`
- 国际象棋主场景：`resource/chess/scene/game/chess_cafe.tscn`

打开对应场景后，点击“运行当前场景”，或按 `F6`，即可跳过主菜单直接进入该玩法场景。

### 5. 配置 AI 对话功能

棋局 AI 对话和复盘功能使用阿里云百炼 / DashScope 的 OpenAI 兼容接口。没有 API Key 时，棋局本身仍可运行，但 AI 对话、吐槽和复盘功能不会正常返回内容。

可以使用以下任一方式配置 API Key：

- 在游戏内点击对局界面的 `API Key` 按钮，输入并保存 Key。
- 在系统环境变量中设置 `CHESS_AI_API_KEY`。
- 在系统环境变量中设置 `DASHSCOPE_API_KEY`。

如果通过环境变量配置，请设置完成后重新启动 Godot 编辑器，让运行进程读取新的环境变量。

### 6. 常见问题

- 如果 C# 脚本无法加载，确认使用的是 Godot 4.5 .NET 版本，并且本机已安装 .NET 8 SDK。
- 如果提示找不到 GDExtension 动态库，确认 `bin/` 目录下存在 Windows 版 `libsiamese` 动态库。
- 如果中国象棋 AI 不走棋，确认 `resource/xiangqi/bin/pikafish/` 下同时存在 `pikafish.exe` 和 `pikafish.nnue`。
- 如果 AI 对话没有回复，确认已经配置有效的 DashScope API Key，并检查网络是否能访问 `dashscope.aliyuncs.com`。
- 如果 Godot 首次打开后画面或资源异常，可以关闭项目后重新打开，让资源重新导入一次。

## 场景速查

工程中的主要可运行场景如下：

- 主菜单：`scene/ui/start_menu.tscn`
- 中国象棋主场景：`resource/xiangqi/scene/game/xiangqi_cafe_game.tscn`
- 国际象棋主场景：`resource/chess/scene/game/chess_cafe.tscn`

## 目录说明

- `resource/xiangqi/`：中国象棋场景、规则脚本、Pikafish 适配与棋局表现
- `resource/chess/`：国际象棋场景、棋盘与相关脚本
- `chess_ai_module/`：C# AI 对话、复盘、记忆和提示词模块
- `common/`：C# 公共数据模型
- `scene/ui/`：菜单、设置、对话、加载、文档浏览等界面场景
- `scene/common/`：通用玩家和环境场景
- `src/common/`：关卡、玩家、状态机、进度等通用 GDScript
- `src/core/`：C++ GDExtension 核心逻辑
- `src/ui/`：界面控制脚本
- `assets/`：模型、贴图、音频、字体与翻译资源

## 开源基础

本项目不是从零开始的独立工程，而是在 `GodotHub/siamese_chess` 的开源代码基础上进行二次开发。原项目提供了 Godot 棋类游戏框架、国际象棋相关实现和部分资源组织方式；本项目围绕毕业设计需求继续扩展中国象棋、AI 交互和 3D 游戏流程。

## 许可证

项目沿用并保留上游项目的 MulanPSL-2.0 许可证。完整许可证文本见 [LICENSE](LICENSE)，二次开发说明见 [LICENSE-NOTICE.md](LICENSE-NOTICE.md)。
