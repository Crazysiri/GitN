# Requirements Document

## Introduction

本功能为 GitN 引入「Git 操作历史日志」（Operation History Logs）。GitN 目前通过 `GitService → GitCLI.execute` 执行 git 命令，`execute` 会在 `waitUntilExit()` 之后一次性返回完整的 stdout/stderr，且执行结果仅通过 toast 短暂提示，操作过程与输出不会被保留。这对审计、排查失败原因（尤其涉及 git hook 输出，如 `git-lfs pre-push`）非常不利。

本功能要求：为每个仓库（对应每个标签页）记录所有会修改仓库状态的 git 操作（远程/网络类与本地变更类），持久化到磁盘并在应用重启后恢复；对 push/pull/fetch 类操作实时流式展示进程与 hook 输出，其余变更类操作在完成时记录捕获到的输出；并通过工具栏附近的模态/浮层界面展示可展开查看日志的历史列表。

按照仓库 AGENTS.md 约束，新增逻辑应放入聚焦、可单元测试的服务/辅助层（参考 `RepoReflogLoader` 服务 + `RepoReflogState` 模型的既有模式），避免让 `RepoViewModel` 与 `GitService` 膨胀；新增非 UI 逻辑需随附测试。

## Glossary

- **Operation_History_Service**: 负责记录、持久化、加载与查询单个仓库操作历史的聚焦服务层组件（非 UI），与 `RepoReflogLoader` 类似的定位。
- **Operation_Log_Entry**: 一条操作历史记录，至少包含操作类型、执行的 git 命令与参数、开始时间戳、完成时间戳、退出状态码、成功/失败结果、以及捕获或流式收集到的输出内容（stdout/stderr/hook 输出）。
- **Streaming_Executor**: `GitCLI` 中新增的流式执行路径，可在进程运行期间按增量向调用方回传 stdout/stderr（含 git hook 输出），用于 push/pull/fetch。
- **Mutating_Operation**: 会改变仓库状态的 git 操作，包括远程/网络类（fetch、fetchWithPrune、pull/pullFF/pullRebase/pullForce、push/pushForce/pushTag）与本地变更类（commit、merge、rebase、checkout、reset、stash）。
- **Read_Only_Operation**: 只读查询类 git 操作（如 log、status、diff），不在本功能记录范围内。
- **Streaming_Operation**: push、pull、fetch（含其 force/prune/tag 等变体）这类需要实时流式输出的操作。
- **History_Store**: 每个仓库对应的、持久化到磁盘的操作历史存储位置。
- **History_View**: 从工具栏（push/pull/fetch 控件附近）打开的模态/浮层界面，展示当前仓库的操作历史列表，支持逐条展开查看日志输出。
- **Repo_Context**: 单个仓库/标签页的上下文，每个 Repo_Context 拥有独立的操作历史。

## Requirements

### Requirement 1: 记录变更类操作

**User Story:** 作为使用 GitN 的开发者，我希望每次执行会修改仓库的 git 操作都被记录下来，以便日后审计和排查问题。

#### Acceptance Criteria

1. WHEN 一个 Mutating_Operation 开始执行, THE Operation_History_Service SHALL 创建一条 Operation_Log_Entry 并记录操作类型、完整的 git 命令与参数、以及开始时间戳。
2. WHEN 一个 Mutating_Operation 执行完成, THE Operation_History_Service SHALL 在对应的 Operation_Log_Entry 中记录完成时间戳、进程退出状态码以及成功或失败结果。
3. WHEN 一个 Read_Only_Operation 执行, THE Operation_History_Service SHALL 不为该操作创建 Operation_Log_Entry。
4. THE Operation_History_Service SHALL 将每条 Operation_Log_Entry 归属到发起该操作的 Repo_Context。
5. WHERE 一个 Mutating_Operation 属于本地变更类（commit、merge、rebase、checkout、reset、stash）, THE Operation_History_Service SHALL 在操作完成时记录该操作捕获到的完整 stdout 与 stderr 输出。

### Requirement 2: 每仓库持久化与恢复

**User Story:** 作为使用 GitN 的开发者，我希望每个仓库的操作历史被保存到磁盘并在重启应用后仍可查看，以便长期审计。

#### Acceptance Criteria

1. WHEN 一条 Operation_Log_Entry 被创建或更新, THE Operation_History_Service SHALL 将该 Repo_Context 的操作历史持久化到对应的 History_Store。
2. WHEN 一个仓库在应用中被打开, THE Operation_History_Service SHALL 从该仓库对应的 History_Store 加载已持久化的操作历史并使其可供查询。
3. THE Operation_History_Service SHALL 为每个 Repo_Context 维护相互独立的 History_Store，使不同仓库/标签页的操作历史互不混合。
4. IF 某个 Repo_Context 尚不存在已持久化的操作历史, THEN THE Operation_History_Service SHALL 以空历史初始化该 Repo_Context 且不产生错误。
5. IF 读取 History_Store 时数据损坏或无法解析, THEN THE Operation_History_Service SHALL 以空历史继续运行并记录一条可诊断的错误信息。

### Requirement 3: push/pull/fetch 的实时流式输出

**User Story:** 作为使用 GitN 的开发者，我希望在执行 push/pull/fetch 时能实时看到进程与 git hook 的输出，以便及时了解进度和排查失败。

#### Acceptance Criteria

1. WHILE 一个 Streaming_Operation 正在执行, THE Streaming_Executor SHALL 在进程运行期间以增量方式向对应的 Operation_Log_Entry 追加 stdout 与 stderr 输出。
2. WHILE 一个 Streaming_Operation 正在执行, THE Streaming_Executor SHALL 捕获并追加 git hook 产生的输出。
3. WHEN 用户在 History_View 中展开一个正在执行的 Streaming_Operation 的 Operation_Log_Entry, THE History_View SHALL 随新输出到达而实时更新所显示的日志内容。
4. WHEN 一个 Streaming_Operation 执行完成, THE Streaming_Executor SHALL 记录进程退出状态码并将该 Operation_Log_Entry 标记为已完成。
5. THE Streaming_Executor SHALL 在执行 Streaming_Operation 时使用扩展后的 PATH 环境（`GitCLI.enrichedEnvironment`），使 git hook 可解析所需工具。
6. IF 一个 Streaming_Operation 在流式执行过程中失败, THEN THE Streaming_Executor SHALL 在对应的 Operation_Log_Entry 中保留已收集到的全部输出并记录失败结果。

### Requirement 4: 工具栏触发的历史界面

**User Story:** 作为使用 GitN 的开发者，我希望从工具栏打开一个操作历史界面并逐条查看每次操作的日志，以便审阅执行细节。

#### Acceptance Criteria

1. THE History_View SHALL 可从工具栏中 push/pull/fetch 控件附近的入口以模态或浮层方式打开。
2. WHEN 用户打开 History_View, THE History_View SHALL 展示当前 Repo_Context 的操作历史列表，且每条列表项显示操作类型、开始时间戳与成功或失败结果。
3. THE History_View SHALL 按时间顺序展示 Operation_Log_Entry，使最近的操作可被用户识别。
4. WHEN 用户展开一条 Operation_Log_Entry, THE History_View SHALL 显示该操作对应的 git 命令、退出状态码以及捕获或流式收集到的完整日志输出。
5. WHEN 用户在不同标签页之间切换后打开 History_View, THE History_View SHALL 仅展示当前 Repo_Context 的操作历史。
6. IF 当前 Repo_Context 的操作历史为空, THEN THE History_View SHALL 显示一条表明尚无历史记录的空状态提示。

### Requirement 5: 错误与边界处理

**User Story:** 作为使用 GitN 的开发者，我希望历史记录在异常情况下仍然可靠，不影响正常的 git 操作，以便持续信任该功能。

#### Acceptance Criteria

1. IF 持久化 Operation_Log_Entry 到 History_Store 失败, THEN THE Operation_History_Service SHALL 保留内存中的操作历史并记录一条可诊断的错误信息。
2. IF 一个 Mutating_Operation 在完成前进程被终止或中断, THEN THE Operation_History_Service SHALL 将对应的 Operation_Log_Entry 标记为中断状态并保留已收集到的输出。
3. WHEN 一个操作的输出包含无法以 UTF-8 解码的字节, THE Operation_History_Service SHALL 保留可解码部分并以不丢失记录的方式完成该 Operation_Log_Entry。
4. IF 记录或持久化操作历史发生失败, THEN THE Operation_History_Service SHALL 不阻断或改变底层 git 操作本身的执行结果。
