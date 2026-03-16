# GitN 功能介绍与使用文档

## 概览

GitN 是一个 macOS 原生 Git 图形客户端，基于 SwiftUI 构建。界面分为三栏：左侧 **Sidebar**（分支/远程/标签等），中间 **Graph**（提交历史图），右侧 **Detail**（文件 diff 与提交操作）。

---

## 主要功能列表

| 功能 | 说明 |
|------|------|
| 多 Tab 管理 | 同时打开多个仓库 |
| 提交图 | 可视化分支拓扑，分页加载 |
| Pull / Push / Fetch | 支持普通模式、多种 Pull 策略、Force Pull/Push |
| 分支管理 | 创建、切换、重命名、删除、设置 Upstream |
| Merge / Rebase | 本地分支间合并与变基 |
| Stash | 暂存/恢复/删除工作区变更 |
| Tag | 创建、查看标签 |
| Remote | 添加、编辑、删除远程仓库 |
| Staging | 文件级暂存/反暂存，拖拽操作 |
| 提交 | 创建提交、编辑提交信息 |
| Conflict 解决 | 三面板可视化冲突解决 |
| Squash Commits | 多选 commit 合并压缩 |
| AI 提交信息 | 调用 cursor-agent 自动生成 |
| 文件历史 | 单文件提交历史与 diff |
| Compare 模式 | 提交快照与工作目录对比 |
| 内嵌终端 | 仓库目录下的 shell 终端 |
| GitLab MR | 查看、过滤、Rebase & Merge MR |
| 语法高亮 | Diff 视图支持 20+ 语言语法高亮 |

---

## 复杂功能详细说明

### 1. 多 Tab 管理

**打开新仓库：**

- 启动后进入 **New Tab 页**，点击 **Open** 按钮选择本地 Git 仓库目录
- 支持从 **Recent**（最近 15 条）直接点击重新打开
- 点击 Tab 栏右上角 **+** 按钮打开新标签页

**Tab 切换行为：**

- 每个 Tab 独立持有一个 `RepoViewModel`，互不干扰
- 采用**懒加载 + 缓存**策略：Tab 首次点击时才加载数据，之后切换不销毁（通过 `opacity` 隐藏），避免重复加载
- 切换到已加载的 Tab 时，会触发一次**后台 Fetch** 更新远程状态
- 关闭 Tab 后如无其他 Tab，自动回到 New Tab 页
- 所有已打开的仓库在 App 重启后**自动恢复**

---

### 2. Pull 模式 & Force Pull

**普通 Pull：** 点击工具栏 **Pull** 按钮执行，使用当前设置的默认模式。

**切换 Pull 模式：** 点击 Pull 按钮旁的 **▾ 小三角**，从下拉菜单选择：

| 模式 | 等效命令 | 说明 |
|------|----------|------|
| Merge（默认） | `git pull` | 产生合并提交 |
| Rebase | `git pull --rebase` | 保持线性历史 |
| Fast-forward only | `git pull --ff-only` | 仅允许快进，否则报错 |

选择即保存为新的默认模式（下次点击 Pull 直接使用）。

**Force Pull（危险操作）：**

1. 点击 **▾** → 选择 **Force Pull (reset to remote)**
2. 弹出确认框，说明该操作将执行 `git fetch + git reset --hard @{u}`，**丢弃本地所有未推送提交**
3. 确认后执行，本地分支完全重置为远程状态

> 适用场景：本地历史已乱、想完全与远程同步时使用。操作不可逆。

---

### 3. Force Push

**普通 Push：** 点击工具栏 **Push** 按钮，如当前分支无 upstream 则自动弹出 upstream 设置面板。

**Force Push：**

1. 点击 Push 旁的 **▾** → 选择 **Force Push (--force-with-lease)**
2. 确认弹框后执行

使用 `--force-with-lease` 安全模式：若远程已被他人推送则会拒绝，比 `--force` 更安全。

> 适用场景：本地 rebase/amend 之后需要覆盖远程历史。

---

### 4. Squash Commits（合并多个提交）

1. 在提交图（Graph）中，按住 **⌘ 或 Shift** 多选若干连续提交
2. 右键弹出上下文菜单，选择 **Squash X commits**
3. 系统执行 interactive rebase 将所选提交压缩为一个

> 注意：只能 squash 当前分支上可编辑的提交（即 HEAD 可达的提交）。

---

### 5. Conflict 冲突解决

当 Merge、Rebase 或 Stash Apply 产生冲突时：

- 工具栏出现黄色警告角标，显示 `MERGE` / `REBASE` / `STASH` 状态
- Detail 面板切换为冲突操作面板，列出所有冲突文件

**打开可视化解决界面：**

点击冲突文件进入 **三面板冲突编辑器**（ConflictMergeView）：

```
┌─────────────┬─────────────┐
│   A (Ours)  │  B (Theirs) │
├─────────────┴─────────────┤
│         Output            │
└───────────────────────────┘
```

- **A 面板（蓝色）**：当前分支（Ours）的内容
- **B 面板（橙色）**：合入分支（Theirs）的内容
- **Output 面板**：实时预览最终结果

**操作方式：**

- 每个冲突区域在 A/B 面板的**首行左侧有复选框**，点击勾选即代表选用该侧内容
- 可同时勾选 A 和 B（两者都保留），也可都不选（跳过该冲突块）
- Output 面板中选中的行显示 `A ✓` 或 `B ✓` 标记
- 顶部导航按钮 **↑ / ↓** 在多个冲突区之间跳转
- 三面板**同步滚动**，始终对齐
- 支持**语法高亮**（根据文件扩展名自动识别语言）
- 点击 **Save** 保存解决结果并 stage 该文件
- 点击 **Reset** 清空所有选择，重新来过
- 解决所有文件后，在 Detail 面板点击 **Continue** 完成 merge/rebase

---

### 6. Rebase & Merge MR（GitLab）

**前提：** 在 Settings 中配置 GitLab URL 和 Personal Access Token。

**查看 MR：**

1. 展开 Sidebar → **MERGE REQUESTS** 区域（首次展开时自动加载）
2. 顶部过滤栏可切换：`Opened` / `Merged` / `Closed`
3. 每条 MR 显示：状态图标、编号、标题、作者、源分支 → 目标分支、是否有冲突

**Rebase & Merge 操作：**

1. 右键某条 `Opened` 状态的 MR → **Rebase & Merge**
2. 弹出确认框，说明完整流程：
   - 当前工作区变更会被**自动 stash**
   - Checkout 源分支
   - Rebase 到目标分支
   - 调用 GitLab API 执行 Merge
   - 恢复 stash
3. 操作期间显示全屏遮罩和进度文字，防止误操作
4. 完成后 toast 通知结果

**其他操作（右键菜单）：**

- **Open in Browser**：在浏览器打开 MR 页面
- **Copy MR Title / Source Branch / MR URL**

---

### 7. 提交信息编辑

**方式一：** 在 Detail 面板，选中历史提交后，直接**点击提交信息文字区域**（鼠标悬停时显示蓝色边框），进入编辑模式。

**方式二：** 在提交图右键 → **Edit Message**，弹出独立编辑框。

编辑模式下：
- 标题和描述分离，标题有**72 字符剩余计数**
- 支持一键调用 **AI** 生成新的提交信息（见下节）
- 点击 **Update Message** 保存（执行 `git commit --amend`）

> 只有**当前分支上可达**的提交才能编辑（不能编辑其他分支的提交）。

---

### 8. AI 自动生成提交信息

**前提：** 已安装 `cursor-agent` CLI，并在 **Settings → AI Commit** 中配置 API Key（或设置环境变量 `CURSOR_API_KEY`）。

**新提交时使用：**

1. 确保有已暂存文件（staged files）
2. 在 Detail 面板底部提交区域，点击 **✦ AI** 按钮
3. 等待生成后，标题和描述自动填入

**编辑已有提交时使用：**

1. 点击提交信息区进入编辑模式
2. 点击右上角紫色 **✦ AI** 按钮，基于该提交的 diff 重新生成

AI 使用 Conventional Commits 格式（`type(scope): description`），支持自定义 Prompt（在 Settings 中修改）。

---

### 9. 文件历史（File History）

在 Detail 面板，右键任意文件 → **File History**，弹出独立窗口，显示：

- 该文件的所有历史提交列表（hash、日期、作者、消息）
- 点击某条提交，下方展示该提交对该文件的完整 diff

---

### 10. Compare 模式（与工作目录对比）

在提交图右键任意历史提交 → **Compare with Working Directory**：

- Detail 面板切换为 Compare 模式，显示该提交快照与当前工作目录的差异
- 适合查看"自从某个提交之后，文件改了什么"
- 点击 **Done** 退出 Compare 模式

---

### 11. 内嵌终端

- 点击工具栏 **Terminal** 图标（或再次点击收起）
- 终端自动 `cd` 到当前仓库目录，使用用户默认 Shell（`$SHELL`）
- 支持 xterm-256color，Option 键作为 Meta 键
- 支持 Dark/Light 主题切换

---

### 12. 分支右键操作速查

在 Sidebar 中，**本地分支**右键菜单包含以下操作：

| 操作 | 说明 |
|------|------|
| Pull \<branch\> | 拉取该分支的远程更新 |
| Merge \<branch\> into \<current\> | 合并到当前分支 |
| Rebase \<current\> onto \<branch\> | 变基到该分支 |
| Checkout | 切换到该分支（双击也可切换） |
| Set Upstream | 设置跟踪的远程分支 |
| Create branch here | 在该分支 HEAD 新建分支 |
| Cherry pick commit | Cherry pick 该分支顶部提交 |
| Reset \<current\> to this commit | Soft / Mixed / Hard 三种模式 |
| Revert commit | 创建一个反转提交 |
| Rename | 重命名分支 |
| Delete | 删除（未合并时提示 Force Delete） |
| Copy branch name / SHA | 复制到剪贴板 |
| Create tag here | 在该提交打标签 |

**单击分支**：Graph 滚动定位到该分支的 HEAD 提交。
**双击分支**：切换到该分支。

---

### 13. 提交图右键操作速查

在 Graph 视图，**右键某条提交**可执行：

- Merge / Rebase（针对 ref 节点）
- Checkout（branch 或 detached HEAD）
- Create Branch at this commit
- Cherry Pick
- Reset (Soft / Mixed / Hard)
- Revert
- Edit Message
- Create Tag
- Delete Branch / Delete Remote Branch
- Compare with Working Directory
- Copy SHA
- **Squash X commits**（多选后出现）
