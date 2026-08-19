<?php

declare(strict_types=1);

require __DIR__ . '/../src/Config.php';
require __DIR__ . '/../src/ServiceManager.php';

use Frampp\ControlPanel\Config;
use Frampp\ControlPanel\ServiceManager;

$config = Config::discover();
$mgr = new ServiceManager($config);
$status = $mgr->status();
$ports = $mgr->ports();
$log = $mgr->tailLog('frankenphp', 40);
$token = (string) $config->secret('panel_token');

function badge(bool $ok): string
{
    $color = $ok ? '#1a7f37' : '#a40e26';
    $text = $ok ? '运行中' : '已停止';
    return sprintf('<span style="color:%s;font-weight:600">%s</span>', $color, $text);
}
?>
<!doctype html>
<html lang="zh-CN">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>FRAMPP 控制面板</title>
    <style>
        body { font-family: "Segoe UI", "Microsoft YaHei", sans-serif; background: #f5f6f8; margin: 0; padding: 32px; }
        main { max-width: 900px; margin: 0 auto; }
        h1 { font-size: 22px; }
        .card { background: #fff; border: 1px solid #e2e4e8; border-radius: 8px; padding: 20px; margin-bottom: 20px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #eef0f3; font-size: 14px; }
        button { cursor: pointer; border: 1px solid #d0d3d9; background: #fafbfc; border-radius: 6px; padding: 6px 14px; font-size: 13px; }
        button:hover { background: #f0f2f5; }
        pre { background: #0d1117; color: #c9d1d9; padding: 14px; border-radius: 6px; overflow: auto; font-size: 12px; max-height: 260px; }
        .meta { color: #57606a; font-size: 13px; }
    </style>
</head>
<body>
<main>
    <h1>FRAMPP 控制面板</h1>
    <p class="meta">运行时：<?= htmlspecialchars($config->root) ?></p>

    <div class="card">
        <table>
            <thead>
            <tr><th>服务</th><th>状态</th><th>PID</th><th>端口</th><th>操作</th></tr>
            </thead>
            <tbody>
            <?php foreach ($status as $name => $s): ?>
                <tr>
                    <td><?= htmlspecialchars($name) ?></td>
                    <td><?= badge($s['running']) ?></td>
                    <td><?= $s['pid'] ?? '-' ?></td>
                    <td><?= $s['port'] ? $s['port'] . '（' . ($s['port_open'] ? '开放' : '关闭') . '）' : '-' ?></td>
                    <td>
                        <?php if ($s['running']): ?>
                            <form method="post" action="action.php" style="display:inline">
                                <input type="hidden" name="token" value="<?= htmlspecialchars($token) ?>">
                                <input type="hidden" name="action" value="stop">
                                <input type="hidden" name="service" value="<?= htmlspecialchars($name) ?>">
                                <button type="submit">停止</button>
                            </form>
                        <?php else: ?>
                            <form method="post" action="action.php" style="display:inline">
                                <input type="hidden" name="token" value="<?= htmlspecialchars($token) ?>">
                                <input type="hidden" name="action" value="start">
                                <input type="hidden" name="service" value="<?= htmlspecialchars($name) ?>">
                                <button type="submit">启动</button>
                            </form>
                        <?php endif; ?>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    </div>

    <div class="card">
        <h2 style="font-size:16px">端口</h2>
        <table>
            <thead><tr><th>用途</th><th>端口</th><th>状态</th></tr></thead>
            <tbody>
            <?php foreach ($ports as $name => $p): ?>
                <tr>
                    <td><?= htmlspecialchars($name) ?></td>
                    <td><?= $p['port'] ?></td>
                    <td><?= badge($p['open']) ?></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    </div>

    <div class="card">
        <h2 style="font-size:16px">FrankenPHP 日志（最近 40 行）</h2>
        <pre><?= htmlspecialchars(implode("\n", $log['lines'])) ?></pre>
    </div>
</main>
</body>
</html>
