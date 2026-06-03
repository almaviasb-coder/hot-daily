param(
    [int]$Limit = 10,
    [string]$OutDir = (Join-Path $PSScriptRoot "dist"),
    [string]$DataDir = (Join-Path $PSScriptRoot "data")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$sources = @("36氪", "百度", "抖音", "今日头条", "微博")
$capturedAt = Get-Date
$reportDate = $capturedAt.ToString("yyyy-MM-dd")
$windowStart = $capturedAt.AddDays(-1).ToString("yyyy-MM-dd HH:mm")
$windowEnd = $capturedAt.ToString("yyyy-MM-dd HH:mm")

function New-HotItem {
    param(
        [string]$Source,
        [string]$Title,
        [string]$Url,
        [int]$Rank,
        [string]$Heat,
        [string]$ImageUrl = "",
        [string]$Content = ""
    )

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return $null
    }

    [pscustomobject]@{
        source = $Source
        title = ($Title -replace "\s+", " ").Trim()
        url = $Url
        rank = $Rank
        heat = $Heat
        image_url = $ImageUrl
        content = ($Content -replace "\s+", " ").Trim()
        captured_at = $capturedAt.ToString("yyyy-MM-dd HH:mm:ss")
    }
}

function Invoke-HotRequest {
    param(
        [string]$Uri,
        [hashtable]$Headers = @{},
        [int]$TimeoutSec = 20
    )

    $defaultHeaders = @{
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"
        "Accept" = "text/html,application/json,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        "Accept-Language" = "zh-CN,zh;q=0.9,en;q=0.6"
    }
    foreach ($key in $Headers.Keys) {
        $defaultHeaders[$key] = $Headers[$key]
    }

    try {
        return (Invoke-WebRequest -Uri $Uri -UseBasicParsing -Headers $defaultHeaders -TimeoutSec $TimeoutSec).Content
    } catch {
        Write-Warning "抓取失败：$Uri -> $($_.Exception.Message)"
        return $null
    }
}

function ConvertFrom-JsonSafe {
    param([string]$Json)
    try {
        return $Json | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-BaiduHot {
    $items = @()
    $content = Invoke-HotRequest "https://top.baidu.com/board?tab=realtime" @{ "Referer" = "https://top.baidu.com/" }
    if (-not $content) { return $items }

    $match = [regex]::Match($content, "<!--s-data:(.*?)-->", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { return $items }

    $json = ConvertFrom-JsonSafe $match.Groups[1].Value
    $hotList = $json.data.cards | Where-Object { $_.component -eq "hotList" } | Select-Object -First 1
    $rank = 1
    foreach ($row in $hotList.content) {
        $items += New-HotItem "百度" $row.word $row.url $rank ([string]$row.hotScore) ([string]$row.img) ([string]$row.desc)
        $rank++
    }
    return $items
}

function Get-WeiboHot {
    $items = @()
    $content = Invoke-HotRequest "https://weibo.com/ajax/side/hotSearch" @{
        "Referer" = "https://weibo.com/"
        "Accept" = "application/json,text/plain,*/*"
    }
    if (-not $content) { return $items }

    $json = ConvertFrom-JsonSafe $content
    $rank = 1
    foreach ($row in $json.data.realtime) {
        if ($row.is_ad -or $row.category -eq "ad") { continue }
        $title = if ($row.word) { $row.word } else { $row.note }
        $url = "https://s.weibo.com/weibo?q=$([uri]::EscapeDataString($title))"
        $items += New-HotItem "微博" $title $url $rank ([string]$row.num)
        $rank++
    }
    return $items
}

function Get-DouyinHot {
    $items = @()
    $content = Invoke-HotRequest "https://www.iesdouyin.com/web/api/v2/hotsearch/billboard/word/" @{
        "Referer" = "https://www.douyin.com/"
        "Accept" = "application/json,text/plain,*/*"
    }
    if (-not $content) { return $items }

    $json = ConvertFrom-JsonSafe $content
    $rank = 1
    foreach ($row in $json.word_list) {
        $title = $row.word
        $url = "https://www.douyin.com/search/$([uri]::EscapeDataString($title))"
        $items += New-HotItem "抖音" $title $url $rank ([string]$row.hot_value)
        $rank++
    }
    return $items
}

function Get-ToutiaoHot {
    $items = @()
    $content = Invoke-HotRequest "https://www.toutiao.com/hot-event/hot-board/?origin=toutiao_pc" @{
        "Referer" = "https://www.toutiao.com/"
        "Accept" = "application/json,text/plain,*/*"
    }
    if (-not $content) { return $items }

    $json = ConvertFrom-JsonSafe $content
    $rank = 1
    foreach ($row in $json.data) {
        $imageUrl = if ($row.Image -and $row.Image.url) { [string]$row.Image.url } else { "" }
        $body = if ($row.Abstract) { [string]$row.Abstract } elseif ($row.LabelDesc) { [string]$row.LabelDesc } else { "" }
        $items += New-HotItem "今日头条" $row.Title $row.Url $rank ([string]$row.HotValue) $imageUrl $body
        $rank++
    }
    return $items
}

function Get-Kr36Hot {
    $items = @()
    $content = Invoke-HotRequest "https://www.36kr.com/newsflashes" @{ "Referer" = "https://www.36kr.com/" }
    if (-not $content) { return $items }

    $stateMatch = [regex]::Match($content, "window\.initialState=(.*?)</script>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $stateMatch.Success) { return $items }

    $matches = [regex]::Matches(
        $stateMatch.Groups[1].Value,
        '\{"itemId":(?<id>\d+).*?"widgetTitle":"(?<title>(?:\\.|[^"\\])*)","widgetContent":"(?<content>(?:\\.|[^"\\])*)"',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $rank = 1
    foreach ($match in $matches) {
        $id = $match.Groups["id"].Value
        $titleJson = '{"value":"' + $match.Groups["title"].Value + '"}'
        $contentJson = '{"value":"' + $match.Groups["content"].Value + '"}'
        $titleObject = ConvertFrom-JsonSafe $titleJson
        $contentObject = ConvertFrom-JsonSafe $contentJson
        if (-not $titleObject) { continue }

        $title = $titleObject.value
        $content = if ($contentObject) { $contentObject.value } else { "" }
        $url = "https://www.36kr.com/newsflashes/$id"
        $items += New-HotItem "36氪" $title $url $rank "" "" $content
        $rank++
    }
    return $items
}

function Test-Entertainment {
    param([string]$Title)
    $keywords = @(
        "明星", "艺人", "演员", "歌手", "偶像", "爱豆", "粉丝", "饭圈", "塌房",
        "绯闻", "恋情", "分手", "离婚", "复合", "前任", "红毯", "综艺", "剧透",
        "演唱会", "新歌", "新剧", "热播剧", "男团", "女团", "CP", "磕糖",
        "素人嘉宾", "狗仔", "站姐", "路透", "代拍"
    )

    foreach ($keyword in $keywords) {
        if ($Title -like "*$keyword*") {
            return $true
        }
    }
    return $false
}

function Normalize-Title {
    param([string]$Title)
    $text = $Title.ToLowerInvariant()
    $text = $text -replace "#", ""
    $text = $text -replace "[\s\p{P}\p{S}]", ""
    $stopWords = @("回应", "发文", "官方", "最新", "曝", "称", "宣布", "冲上热搜", "登上热搜")
    foreach ($word in $stopWords) {
        $text = $text.Replace($word, "")
    }
    return $text
}

function Get-Similarity {
    param([string]$A, [string]$B)
    if ($A -eq $B) { return 1.0 }
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return 0.0 }

    $setA = New-Object System.Collections.Generic.HashSet[string]
    $setB = New-Object System.Collections.Generic.HashSet[string]
    foreach ($ch in $A.ToCharArray()) { [void]$setA.Add([string]$ch) }
    foreach ($ch in $B.ToCharArray()) { [void]$setB.Add([string]$ch) }
    $intersection = 0
    foreach ($ch in $setA) {
        if ($setB.Contains($ch)) { $intersection++ }
    }
    $union = $setA.Count + $setB.Count - $intersection
    if ($union -eq 0) { return 0.0 }
    return $intersection / $union
}

function Merge-HotItems {
    param([array]$Items)
    $groups = @()

    foreach ($item in $Items) {
        if ($null -eq $item) { continue }
        if (Test-Entertainment $item.title) { continue }

        $normalized = Normalize-Title $item.title
        if ($normalized.Length -lt 3) { continue }

        $target = $null
        $bestScore = 0.0
        foreach ($group in $groups) {
            $score = Get-Similarity $normalized $group.normalized
            if ($score -gt $bestScore) {
                $bestScore = $score
                $target = $group
            }
        }

        if ($target -and $bestScore -ge 0.72) {
            $target.items += $item
            if ($item.title.Length -gt $target.title.Length) {
                $target.title = $item.title
                $target.normalized = $normalized
            }
        } else {
            $groups += [pscustomobject]@{
                title = $item.title
                normalized = $normalized
                items = @($item)
            }
        }
    }

    foreach ($group in $groups) {
        $uniqueSources = @($group.items | Select-Object -ExpandProperty source -Unique)
        $bestRank = ($group.items | Measure-Object -Property rank -Minimum).Minimum
        $score = ($uniqueSources.Count * 1000) + ((60 - [int]$bestRank) * 12)
        $sourceWeight = 0
        foreach ($source in $uniqueSources) {
            switch ($source) {
                "36氪" { $sourceWeight += 80 }
                "百度" { $sourceWeight += 70 }
                "今日头条" { $sourceWeight += 65 }
                "微博" { $sourceWeight += 50 }
                "抖音" { $sourceWeight += 45 }
            }
        }

        [pscustomobject]@{
            title = $group.title
            sources = $uniqueSources
            best_rank = [int]$bestRank
            score = $score + $sourceWeight
            items = @($group.items | Sort-Object rank)
        }
    }
}

function HtmlEncode {
    param([object]$Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Convert-ImageToDataUri {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return "" }
    $fullPath = Join-Path $OutDir $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) { return "" }

    $ext = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    $mime = switch ($ext) {
        ".png" { "image/png" }
        ".webp" { "image/webp" }
        default { "image/jpeg" }
    }
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    return "data:$mime;base64,$([Convert]::ToBase64String($bytes))"
}

function Save-ImageAsset {
    param(
        [string]$ImageUrl,
        [int]$Rank
    )

    if ([string]::IsNullOrWhiteSpace($ImageUrl)) { return "" }
    if ($ImageUrl.StartsWith("//")) {
        $ImageUrl = "https:$ImageUrl"
    }
    if (-not ($ImageUrl.StartsWith("http://") -or $ImageUrl.StartsWith("https://"))) {
        return ""
    }

    $assetDir = Join-Path $OutDir (Join-Path "assets" $reportDate)
    New-Item -ItemType Directory -Force -Path $assetDir | Out-Null

    try {
        $uri = [uri]$ImageUrl
        $ext = [System.IO.Path]::GetExtension($uri.AbsolutePath)
        if ([string]::IsNullOrWhiteSpace($ext) -or $ext.Length -gt 6) {
            $ext = ".jpg"
        }
        $fileName = "hot-$("{0:D2}" -f $Rank)$ext"
        $filePath = Join-Path $assetDir $fileName
        Invoke-WebRequest -Uri $ImageUrl -UseBasicParsing -TimeoutSec 20 -OutFile $filePath -Headers @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"
            "Referer" = "https://www.baidu.com/"
        }
        if ((Get-Item -LiteralPath $filePath).Length -lt 4096) {
            Remove-Item -LiteralPath $filePath -Force
            return ""
        }
        return "assets/$reportDate/$fileName"
    } catch {
        Write-Warning "图片下载失败：$ImageUrl -> $($_.Exception.Message)"
        return ""
    }
}

function Save-ArticlePage {
    param(
        [int]$Rank,
        [object]$Group,
        [string]$ImagePath
    )

    $articleDir = Join-Path $OutDir "articles"
    New-Item -ItemType Directory -Force -Path $articleDir | Out-Null

    $fileName = "hot-$("{0:D2}" -f $Rank).html"
    $filePath = Join-Path $articleDir $fileName
    $sourceLinks = ($Group.items | ForEach-Object {
        "<a href='$(HtmlEncode $_.url)' target='_blank' rel='noopener'>来源：$(HtmlEncode $_.source)</a>"
    }) -join ""
    $paragraphs = @($Group.items |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.content) } |
        Select-Object -ExpandProperty content -Unique)
    if ($paragraphs.Count -eq 0) {
        $paragraphs = @(
            "该热点来源未在公开热榜接口中提供完整正文。当前静态页按统一格式展示标题、配图和来源，完整报道请点击下方来源链接查看。",
            "为了避免复制平台全文或抓取受限内容，本页只保存公开可获取的热榜信息。"
        )
    }
    $bodyHtml = ($paragraphs | ForEach-Object {
        "<p>$(HtmlEncode $_)</p>"
    }) -join "`n"
    $imageHtml = if ($ImagePath) {
        $articleImageSrc = Convert-ImageToDataUri $ImagePath
        "<img class='hero-img' src='$(HtmlEncode $articleImageSrc)' alt=''>"
    } else {
        "<div class='hero-fallback'>热点</div>"
    }

    $html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$(HtmlEncode $Group.title)</title>
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; background: #f6f7f9; color: #20242a; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", Arial, sans-serif; line-height: 1.7; }
    main { max-width: 820px; margin: 0 auto; padding: 28px 18px 40px; }
    article { background: #fff; border: 1px solid #e5e7eb; border-radius: 8px; overflow: hidden; }
    .content { padding: 24px; }
    .date { color: #2563eb; font-size: 14px; font-weight: 700; }
    h1 { margin: 8px 0 14px; font-size: 28px; line-height: 1.35; letter-spacing: 0; }
    .hero-img, .hero-fallback { width: 100%; aspect-ratio: 16 / 9; object-fit: cover; display: block; background: #eef2f7; }
    .hero-fallback { display: flex; align-items: center; justify-content: center; color: #475569; font-weight: 700; }
    .sources { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 18px; }
    .sources a { color: #2563eb; text-decoration: none; font-size: 14px; }
    .sources a:hover { text-decoration: underline; }
    .body { margin-top: 20px; font-size: 16px; }
    .body p { margin: 0 0 14px; }
    .meta { margin-top: 14px; color: #667085; font-size: 13px; }
    .back { display: inline-block; margin-bottom: 14px; color: #2563eb; text-decoration: none; font-size: 14px; }
    @media (max-width: 560px) { h1 { font-size: 22px; } .content { padding: 18px; } main { padding: 16px 12px 28px; } }
  </style>
</head>
<body>
  <main>
    <a class="back" href="../index.html">返回日报</a>
    <article>
      $imageHtml
      <div class="content">
        <div class="date">$($capturedAt.ToString("yyyy 年 MM 月 dd 日"))</div>
        <h1>$(HtmlEncode $Group.title)</h1>
        <div class="body">
          $bodyHtml
        </div>
        <div class="sources">$sourceLinks</div>
        <div class="meta">统一静态正文页。原始完整内容以来源链接为准。</div>
      </div>
    </article>
  </main>
</body>
</html>
"@
    $html | Set-Content -LiteralPath $filePath -Encoding UTF8
    return "articles/$fileName"
}

function Get-ImageQueries {
    param([string]$Title)

    if ($Title -match "金饰|金价|黄金") {
        return @("gold jewelry necklace", "gold jewelry")
    }
    if ($Title -match "adi|das|Adidas|阿迪") {
        return @("Adidas store", "Adidas")
    }
    if ($Title -match "问界|M9|AITO") {
        return @("AITO M9", "Aito car")
    }

    $compactTitle = $Title -replace "回应|事故|浙江|台州|新闻|图片", ""
    return @(
        "$Title 新闻 图片",
        "$Title 图片",
        "$compactTitle 图片"
    )
}

function Find-WebImageUrls {
    param([string]$Title)

    $results = New-Object System.Collections.Generic.List[string]
    $blockList = @(
        "boardmix.cn", "iconfont", "logo", "favicon", "sprite", ".svg", ".gif",
        "data:image", "blank", "placeholder", "meitudata.com", "duitang.com"
    )

    $patterns = @(
        'murl&quot;:&quot;(https?://.*?)(?:&quot;|\\u0026)',
        '"murl":"(https?://.*?)(?:"|\\u0026)'
    )

    $queries = Get-ImageQueries $Title

    foreach ($queryText in $queries) {
        $commonsQuery = [uri]::EscapeDataString($queryText)
        $commonsUrl = "https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=$commonsQuery&gsrnamespace=6&gsrlimit=5&prop=imageinfo&iiprop=url&iiurlwidth=960&format=json&origin=*"
        $commonsContent = Invoke-HotRequest $commonsUrl @{
            "Referer" = "https://commons.wikimedia.org/"
            "Accept" = "application/json,text/plain,*/*"
        } 20
        if ($commonsContent) {
            $commonsJson = ConvertFrom-JsonSafe $commonsContent
            if ($commonsJson -and $commonsJson.query -and $commonsJson.query.pages) {
                foreach ($page in $commonsJson.query.pages.PSObject.Properties.Value) {
                    if ($page.imageinfo -and $page.imageinfo[0].thumburl) {
                        $candidate = [string]$page.imageinfo[0].thumburl
                        if (-not $results.Contains($candidate)) {
                            $results.Add($candidate)
                        }
                    }
                }
            }
        }

        $query = [uri]::EscapeDataString($queryText)
        $content = Invoke-HotRequest "https://cn.bing.com/images/search?q=$query" @{
            "Referer" = "https://cn.bing.com/"
        } 20
        if (-not $content) { continue }

        foreach ($pattern in $patterns) {
            $matches = [regex]::Matches($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $matches) {
                $candidate = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
                $candidate = $candidate -replace "\\/", "/"
                $lower = $candidate.ToLowerInvariant()
                $blocked = $false
                foreach ($word in $blockList) {
                    if ($lower.Contains($word)) {
                        $blocked = $true
                        break
                    }
                }
                if (-not $blocked -and -not $results.Contains($candidate)) {
                    $results.Add($candidate)
                }
                if ($results.Count -ge 10) {
                    return $results.ToArray()
                }
            }
        }
    }

    return $results.ToArray()
}

function Render-Report {
    param(
        [array]$TopGroups,
        [array]$RawItems,
        [array]$FailedSources
    )

    $sourceBadges = ($sources | ForEach-Object { "<span class='source-badge'>$(HtmlEncode $_)</span>" }) -join ""
    $rows = New-Object System.Text.StringBuilder
    $rank = 1

    foreach ($group in $TopGroups) {
        $primaryUrl = $group.items[0].url
        $imageSource = ($group.items | Where-Object { -not [string]::IsNullOrWhiteSpace($_.image_url) } | Select-Object -First 1)
        $localImage = if ($imageSource) { Save-ImageAsset $imageSource.image_url $rank } else { "" }
        if (-not $localImage) {
            $webImages = Find-WebImageUrls $group.title
            foreach ($webImage in $webImages) {
                $localImage = Save-ImageAsset $webImage $rank
                if ($localImage) { break }
            }
        }
        $articleUrl = Save-ArticlePage $rank $group $localImage
        $thumbSrc = if ($localImage) { Convert-ImageToDataUri $localImage } else { "" }
        $thumbHtml = if ($localImage) {
            "<a class='thumb' href='$(HtmlEncode $articleUrl)'><img src='$(HtmlEncode $thumbSrc)' alt=''></a>"
        } else {
            "<a class='thumb thumb-fallback' href='$(HtmlEncode $articleUrl)'><span>热点</span></a>"
        }
        $sourceLine = ($group.items | ForEach-Object {
            "<a href='$(HtmlEncode $_.url)' target='_blank' rel='noopener'>来源：$(HtmlEncode $_.source)</a>"
        }) -join ""

        $chips = ($group.sources | ForEach-Object { "<span class='chip'>$(HtmlEncode $_)</span>" }) -join ""
        [void]$rows.AppendLine(@"
<article class="hot-item">
  <div class="rank">$("{0:D2}" -f $rank)</div>
  $thumbHtml
  <div class="hot-body">
    <h2><a class="title-link" href="$(HtmlEncode $articleUrl)">$(HtmlEncode $group.title)</a></h2>
    <div class="chips">$chips</div>
    <div class="meta">最高排名 #$($group.best_rank) · 覆盖 $($group.sources.Count) 个平台 · 采集 $($capturedAt.ToString("HH:mm"))</div>
    <div class="links">$sourceLine</div>
  </div>
</article>
"@)
        $rank++
    }

    if ($TopGroups.Count -eq 0) {
        [void]$rows.AppendLine("<div class='empty'>今天没有生成入选条目。可能是全部来源抓取失败，或过滤规则过严。</div>")
    }

    $failedText = if ($FailedSources.Count -gt 0) {
        "部分来源抓取失败：" + (($FailedSources | ForEach-Object { HtmlEncode $_ }) -join "、")
    } else {
        "全部来源抓取完成"
    }

    $html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>每日热榜日报 - $reportDate</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f6f7f9;
      --paper: #ffffff;
      --text: #20242a;
      --muted: #667085;
      --line: #e5e7eb;
      --accent: #2563eb;
      --accent-soft: #eff6ff;
      --rank: #111827;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", Arial, sans-serif;
      line-height: 1.65;
    }
    .page {
      max-width: 920px;
      margin: 0 auto;
      padding: 32px 20px 42px;
    }
    header {
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 28px;
    }
    .date {
      color: var(--accent);
      font-weight: 700;
      font-size: 14px;
      margin-bottom: 6px;
    }
    h1 {
      margin: 0;
      font-size: 32px;
      line-height: 1.2;
      letter-spacing: 0;
    }
    .sub {
      margin-top: 12px;
      color: var(--muted);
      font-size: 14px;
    }
    .sources {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 18px;
    }
    .source-badge, .chip {
      display: inline-flex;
      align-items: center;
      min-height: 24px;
      padding: 2px 9px;
      border-radius: 999px;
      background: var(--accent-soft);
      color: #1d4ed8;
      font-size: 12px;
      font-weight: 650;
      white-space: nowrap;
    }
    .summary {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
      margin: 16px 0;
    }
    .summary div {
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 14px 16px;
    }
    .summary b {
      display: block;
      font-size: 22px;
      line-height: 1.2;
    }
    .summary span {
      display: block;
      margin-top: 4px;
      color: var(--muted);
      font-size: 12px;
    }
    .notice {
      margin: 0 0 16px;
      color: var(--muted);
      font-size: 13px;
    }
    .list {
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
    }
    .hot-item {
      display: grid;
      grid-template-columns: 58px 132px minmax(0, 1fr);
      gap: 12px;
      padding: 20px 22px;
      border-top: 1px solid var(--line);
    }
    .hot-item:first-child { border-top: 0; }
    .rank {
      color: var(--rank);
      font-size: 24px;
      font-weight: 800;
      line-height: 1.25;
      font-variant-numeric: tabular-nums;
    }
    .thumb {
      display: block;
      width: 132px;
      aspect-ratio: 16 / 10;
      border-radius: 8px;
      overflow: hidden;
      background: #eef2f7;
      border: 1px solid var(--line);
    }
    .thumb img {
      display: block;
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
    .thumb-fallback {
      display: flex;
      align-items: center;
      justify-content: center;
      color: #475569;
      font-size: 13px;
      font-weight: 700;
      text-decoration: none;
    }
    h2 {
      margin: 0;
      font-size: 19px;
      line-height: 1.45;
      letter-spacing: 0;
      overflow-wrap: anywhere;
    }
    .chips {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      margin-top: 8px;
    }
    .meta {
      margin-top: 8px;
      color: var(--muted);
      font-size: 13px;
    }
    .links {
      display: flex;
      flex-wrap: wrap;
      gap: 8px 14px;
      margin-top: 8px;
      font-size: 13px;
    }
    a {
      color: var(--accent);
      text-decoration: none;
    }
    a:hover { text-decoration: underline; }
    .title-link {
      color: var(--text);
      text-decoration: none;
    }
    .title-link:hover {
      color: var(--accent);
      text-decoration: underline;
    }
    .empty {
      padding: 28px;
      color: var(--muted);
      text-align: center;
    }
    footer {
      margin-top: 18px;
      color: var(--muted);
      font-size: 12px;
    }
    @media (max-width: 680px) {
      .page { padding: 18px 12px 28px; }
      header { padding: 22px 18px; }
      h1 { font-size: 26px; }
      .summary { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .hot-item {
        grid-template-columns: 42px 96px minmax(0, 1fr);
        padding: 18px 16px;
      }
      .thumb { width: 96px; }
      .rank { font-size: 20px; }
      h2 { font-size: 17px; }
    }
    @media (max-width: 440px) {
      .hot-item {
        grid-template-columns: 38px minmax(0, 1fr);
      }
      .thumb {
        grid-column: 2;
        width: 100%;
        max-width: 180px;
      }
      .hot-body {
        grid-column: 2;
      }
    }
  </style>
</head>
<body>
  <main class="page">
    <header>
      <div class="date">$($capturedAt.ToString("yyyy 年 MM 月 dd 日"))</div>
      <h1>每日热榜日报</h1>
      <div class="sub">统计窗口：$windowStart 至 $windowEnd。数据来自公开热榜页面，仅保留总榜前 $Limit 条，娱乐八卦内容已按规则过滤。</div>
      <div class="sources">$sourceBadges</div>
    </header>

    <section class="summary" aria-label="日报概览">
      <div><b>$($TopGroups.Count)</b><span>今日入选</span></div>
      <div><b>$($sources.Count)</b><span>目标来源</span></div>
      <div><b>$(($TopGroups | Where-Object { $_.sources.Count -gt 1 }).Count)</b><span>跨平台热点</span></div>
      <div><b>$($capturedAt.ToString("HH:mm"))</b><span>生成时间</span></div>
    </section>

    <p class="notice">$failedText。原始抓取 $($RawItems.Count) 条，合并过滤后取前 $Limit 条。</p>

    <section class="list" aria-label="总榜">
$rows
    </section>

    <footer>
      本页为纯静态 HTML 快照，可本地双击打开；链接指向各平台公开页面。过滤与合并基于标题规则，可能存在少量误判。
    </footer>
  </main>
</body>
</html>
"@

    return $html
}

function Save-Json {
    param([string]$Path, [object]$Value)
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

New-Item -ItemType Directory -Force -Path $OutDir, $DataDir | Out-Null
$todayAssetDir = Join-Path $OutDir (Join-Path "assets" $reportDate)
if (Test-Path -LiteralPath $todayAssetDir) {
    Remove-Item -LiteralPath $todayAssetDir -Recurse -Force
}
$articleDir = Join-Path $OutDir "articles"
if (Test-Path -LiteralPath $articleDir) {
    Remove-Item -LiteralPath $articleDir -Recurse -Force
}

$collectors = @(
    @{ Name = "36氪"; Script = { Get-Kr36Hot } },
    @{ Name = "百度"; Script = { Get-BaiduHot } },
    @{ Name = "抖音"; Script = { Get-DouyinHot } },
    @{ Name = "今日头条"; Script = { Get-ToutiaoHot } },
    @{ Name = "微博"; Script = { Get-WeiboHot } }
)

$rawItems = @()
$failedSources = @()
foreach ($collector in $collectors) {
    Write-Host "抓取 $($collector.Name)..."
    try {
        $items = & $collector.Script
        if ($items.Count -eq 0) {
            $failedSources += $collector.Name
        }
        $rawItems += $items
    } catch {
        Write-Warning "$($collector.Name) 处理失败：$($_.Exception.Message)"
        $failedSources += $collector.Name
    }
}

$merged = @(Merge-HotItems $rawItems | Sort-Object -Property score -Descending | Select-Object -First $Limit)

Save-Json (Join-Path $DataDir "$reportDate.raw.json") $rawItems
Save-Json (Join-Path $DataDir "$reportDate.merged.json") $merged

$html = Render-Report $merged $rawItems $failedSources
$dailyPath = Join-Path $OutDir "${reportDate}日报.html"
$indexPath = Join-Path $OutDir "index.html"
$html | Set-Content -LiteralPath $dailyPath -Encoding UTF8
$html | Set-Content -LiteralPath $indexPath -Encoding UTF8

Write-Host ""
Write-Host "生成完成：$dailyPath"
Write-Host "最新入口：$indexPath"













