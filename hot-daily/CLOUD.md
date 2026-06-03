# 放到云端运行

推荐使用 GitHub Actions。它可以在你的电脑不开机时，每天自动运行脚本并生成日报。

## 1. 上传到 GitHub

新建一个 GitHub 仓库，把 `D:\CODEX软件` 里的内容上传进去。

需要包含这些文件：

```text
.github/workflows/hot-daily.yml
hot-daily/generate-report.ps1
hot-daily/README.md
```

## 2. 自动生成时间

工作流文件已经设置为每天北京时间 08:00 运行：

```text
0 0 * * *
```

GitHub Actions 使用 UTC 时间，所以 UTC 00:00 对应北京时间 08:00。

你也可以在 GitHub 页面手动运行：

```text
Actions -> Hot Daily Report -> Run workflow
```

## 3. 查看生成文件

每次运行后会把结果提交回仓库：

```text
hot-daily/dist/index.html
hot-daily/dist/YYYY-MM-DD日报.html
hot-daily/data/YYYY-MM-DD.raw.json
hot-daily/data/YYYY-MM-DD.merged.json
```

## 4. 发布成网页

如果想直接用网址访问：

1. 打开仓库 Settings
2. 进入 Pages
3. Source 选择 Deploy from a branch
4. Branch 选择 main
5. Folder 选择 `/hot-daily/dist`

如果 GitHub Pages 页面不允许直接选择这个目录，可以改成把日报输出到 `docs` 目录，或新增一个专门发布 Pages 的工作流。

## 注意

GitHub Actions 的定时任务可能有几分钟延迟，不保证精确到 08:00:00，但通常足够做日报。
