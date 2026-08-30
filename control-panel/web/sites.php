<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/Config.php';
require_once __DIR__ . '/../src/SiteManager.php';
require_once __DIR__ . '/../src/AccessManager.php';

use Frampp\ControlPanel\Config;
use Frampp\ControlPanel\SiteManager;
use Frampp\ControlPanel\AccessManager;

$config = Config::discover();
$sites = new SiteManager($config);
$access = new AccessManager($config);
$token = (string) $config->secret('panel_token');
$siteList = $sites->sites();
$types = $sites->types();

$editName = (string) ($_GET['edit'] ?? '');
$editSite = null;
foreach ($siteList as $site) {
    if ($site['name'] === $editName) {
        $editSite = $site;
        break;
    }
}

$notice = '';
if (isset($_GET['error'])) {
    $notice = '<p style="color:#a40e26;font-weight:600">' . htmlspecialchars((string) $_GET['error']) . '</p>';
} elseif (isset($_GET['msg'])) {
    $ok = ($_GET['ok'] ?? '0') === '1';
    $notice = '<p style="color:' . ($ok ? '#1a7f37' : '#a40e26') . ';font-weight:600">' . htmlspecialchars((string) $_GET['msg']) . '</p>';
}
?>
<!doctype html>
<html lang="zh-CN">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>FRAMPP 站点管理</title>
    <style>
        body { font-family: "Segoe UI", "Microsoft YaHei", sans-serif; background: #f5f6f8; margin: 0; padding: 32px; }
        main { max-width: 900px; margin: 0 auto; }
        h1 { font-size: 22px; }
        .card { background: #fff; border: 1px solid #e2e4e8; border-radius: 8px; padding: 20px; margin-bottom: 20px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #eef0f3; font-size: 14px; }
        input, select { padding: 5px 8px; border: 1px solid #d0d3d9; border-radius: 6px; font-size: 13px; margin-right: 8px; }
        button { cursor: pointer; border: 1px solid #d0d3d9; background: #fafbfc; border-radius: 6px; padding: 6px 14px; font-size: 13px; }
        button:hover { background: #f0f2f5; }
        .meta { color: #57606a; font-size: 13px; }
        .row { margin-bottom: 10px; }
        a.nav { color: #0969da; text-decoration: none; font-size: 13px; margin-right: 12px; }
    </style>
</head>
<body>
<main>
    <p><a class="nav" href="index.php">&larr; 返回控制面板 / Back to panel</a></p>
    <h1>FRAMPP 站点管理 / Site Manager</h1>
    <p class="meta">站点片段保存到 <code>etc/caddy.d/&lt;name&gt;.caddy</code>，保存后通过 Caddy admin API 热重载。
        Site snippets are saved to <code>etc/caddy.d/&lt;name&gt;.caddy</code> and hot-reloaded via the Caddy admin API.</p>

    <?= $notice ?>

    <div class="card">
        <h2 style="font-size:16px">站点列表 / Sites</h2>
        <table>
            <thead><tr><th>名称</th><th>地址 / Address</th><th>类型 / Type</th><th>Root / Target</th><th>操作</th></tr></thead>
            <tbody>
            <?php if (!$siteList): ?>
                <tr><td colspan="5" class="meta">暂无站点 / no sites（默认站点在 Caddyfile 中定义）</td></tr>
            <?php endif; ?>
            <?php foreach ($siteList as $site): ?>
                <tr>
                    <td><?= htmlspecialchars($site['name']) ?></td>
                    <td><code><?= htmlspecialchars($site['address']) ?></code></td>
                    <td><?= htmlspecialchars($types[$site['type']] ?? $site['type']) ?></td>
                    <td><code><?= htmlspecialchars($site['type'] === 'proxy' ? $site['target'] : $site['root']) ?></code></td>
                    <td>
                        <a class="nav" href="sites.php?edit=<?= rawurlencode($site['name']) ?>">编辑 / Edit</a>
                        <form method="post" action="action.php" style="display:inline">
                            <input type="hidden" name="token" value="<?= htmlspecialchars($token) ?>">
                            <input type="hidden" name="action" value="site-delete">
                            <input type="hidden" name="name" value="<?= htmlspecialchars($site['name']) ?>">
                            <button type="submit" onclick="return confirm('删除站点 <?= htmlspecialchars($site['name']) ?>？/ Delete site?')">删除 / Delete</button>
                        </form>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>

        <form method="post" action="action.php" style="margin-top:12px">
            <input type="hidden" name="token" value="<?= htmlspecialchars($token) ?>">
            <input type="hidden" name="action" value="site-reload">
            <button type="submit">热重载全部配置 / Reload all</button>
        </form>
    </div>

    <div class="card">
        <h2 style="font-size:16px"><?= $editSite ? '编辑站点 / Edit Site：' . htmlspecialchars($editSite['name']) : '新建站点 / New Site' ?></h2>
        <form method="post" action="action.php">
            <input type="hidden" name="token" value="<?= htmlspecialchars($token) ?>">
            <input type="hidden" name="action" value="site-save">
            <div class="row">
                <label>名称 / Name
                    <input type="text" name="name" value="<?= htmlspecialchars($editSite['name'] ?? '') ?>" required
                           pattern="[A-Za-z0-9._-]{1,64}" <?= $editSite ? 'readonly' : '' ?> placeholder="my-app">
                </label>
                <label>监听地址 / Address
                    <input type="text" name="address" value="<?= htmlspecialchars($editSite['address'] ?? '') ?>" required
                           placeholder="http://127.0.0.1:8082 或 example.com" size="30">
                </label>
            </div>
            <div class="row">
                <label>类型 / Type
                    <select name="type" id="site-type">
                        <?php foreach ($types as $key => $label): ?>
                            <option value="<?= $key ?>" <?= ($editSite['type'] ?? 'php') === $key ? 'selected' : '' ?>><?= htmlspecialchars($label) ?></option>
                        <?php endforeach; ?>
                    </select>
                </label>
                <label id="root-field">文档根目录 / Root
                    <input type="text" name="root" id="root-input" value="<?= htmlspecialchars($editSite['root'] ?? '') ?>"
                           placeholder="C:/work/www/my-app 或 /srv/www" size="34">
                </label>
                <label id="target-field" style="display:none">目标地址 / Target
                    <input type="text" name="target" id="target-input" value="<?= htmlspecialchars($editSite['target'] ?? '') ?>"
                           placeholder="127.0.0.1:9000 或 http://localhost:3000" size="30">
                </label>
            </div>
            <button type="submit">保存并重载 / Save &amp; Reload</button>
            <?php if ($editSite): ?>
                <a class="nav" href="sites.php">取消 / Cancel</a>
            <?php endif; ?>
        </form>
        <p class="meta">提示：多个站点按文件名顺序加载，可用数字前缀控制顺序（如 <code>10-api.caddy</code>）。修改站点后 Caddy 会自动应用新配置。</p>
    </div>
</main>
<script>
    const typeSelect = document.getElementById('site-type');
    const rootField = document.getElementById('root-field');
    const rootInput = document.getElementById('root-input');
    const targetField = document.getElementById('target-field');
    const targetInput = document.getElementById('target-input');
    function toggleFields() {
        const isProxy = typeSelect.value === 'proxy';
        rootField.style.display = isProxy ? 'none' : '';
        targetField.style.display = isProxy ? '' : 'none';
        rootInput.disabled = isProxy;
        targetInput.disabled = !isProxy;
    }
    typeSelect.addEventListener('change', toggleFields);
    toggleFields();
</script>
</body>
</html>
