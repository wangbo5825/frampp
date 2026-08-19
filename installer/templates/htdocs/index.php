<?php

declare(strict_types=1);

$version = PHP_VERSION;
?>
<!doctype html>
<html lang="zh-CN">
<head>
    <meta charset="utf-8">
    <title>FRAMPP</title>
    <style>
        body { font-family: "Segoe UI", "Microsoft YaHei", sans-serif; background: #f5f6f8; margin: 0; padding: 80px 24px; }
        main { max-width: 560px; margin: 0 auto; background: #fff; border: 1px solid #e2e4e8; border-radius: 10px; padding: 32px; }
        h1 { margin-top: 0; }
        code { background: #f0f2f5; padding: 2px 6px; border-radius: 4px; }
    </style>
</head>
<body>
<main>
    <h1>FRAMPP 已就绪 🎉</h1>
    <p>FrankenPHP / MariaDB / Redis 运行正常，PHP <?= htmlspecialchars($version) ?>。</p>
    <p>把项目代码放到 <code>htdocs/</code>，或访问 <code><a href="http://127.0.0.1:8081/">控制面板</a></code>。</p>
</main>
</body>
</html>
