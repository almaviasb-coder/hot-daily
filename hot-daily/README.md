# 热榜日报生成器

每天生成一份可本地双击打开的静态 HTML 热榜日报。

## 当前规格

- 来源：36 氪、百度、抖音、今日头条、微博
- 数量：全网总榜 10 条
- 过滤：按规则过滤娱乐八卦内容
- 合并：按标题相似度合并跨平台热点
- 输出：纯静态 HTML，不依赖后端、CDN 或外部脚本
- 默认统计窗口：生成时刻往前 24 小时

## 使用

在 PowerShell 中运行：

```powershell
cd D:\CODEX软件\hot-daily
.\generate-report.ps1
```

生成文件：

```text
dist\index.html
dist\YYYY-MM-DD日报.html
data\YYYY-MM-DD.raw.json
data\YYYY-MM-DD.merged.json
```

双击 `dist\index.html` 或当天日期日报 HTML 即可查看。

## 自定义条数

```powershell
.\generate-report.ps1 -Limit 10
```

## 定时生成

可以用 Windows 任务计划程序每天 08:00 执行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File "D:\CODEX软件\hot-daily\generate-report.ps1"
```

## 说明

采集器使用公开页面或公开 JSON 入口。平台页面结构可能变化，所以脚本按来源独立处理；某个来源失败时，仍会生成当天日报，并在页面中提示失败来源。

娱乐八卦过滤和跨平台合并都基于标题规则，不使用 AI 摘要，因此可能存在误判。后续可以通过调整 `Test-Entertainment` 的关键词和 `Merge-HotItems` 的相似度阈值继续优化。
