<?php

declare(strict_types=1);

require __DIR__ . '/../src/Config.php';
require __DIR__ . '/../src/ServiceManager.php';
require __DIR__ . '/../src/AccessManager.php';
require __DIR__ . '/../src/SiteManager.php';

use Frampp\ControlPanel\Config;
use Frampp\ControlPanel\ServiceManager;
use Frampp\ControlPanel\AccessManager;
use Frampp\ControlPanel\SiteManager;

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    http_response_code(405);
    exit('Method Not Allowed');
}

try {
    $config = Config::discover();
    $expected = (string) $config->secret('panel_token');
    $given = (string) ($_POST['token'] ?? '');
    if ($expected === '' || !hash_equals($expected, $given)) {
        http_response_code(403);
        exit('Forbidden');
    }

    $action = $_POST['action'] ?? '';
    $service = $_POST['service'] ?? 'all';
    $mgr = new ServiceManager($config);
    $access = new AccessManager($config);
    $sites = new SiteManager($config);
    $message = 'ok';

    $result = match ($action) {
        'start' => $mgr->start($service),
        'stop'  => $mgr->stop($service),
        'cleanup' => $mgr->cleanupOrphans(),
        'site-save' => $sites->saveSite((string) ($_POST['name'] ?? ''), [
            'address' => (string) ($_POST['address'] ?? ''),
            'type'    => (string) ($_POST['type'] ?? 'php'),
            'root'    => (string) ($_POST['root'] ?? ''),
            'target'  => (string) ($_POST['target'] ?? ''),
        ]),
        'site-delete' => $sites->deleteSite((string) ($_POST['name'] ?? '')),
        'site-reload' => null,
        'ip-access-add' => $access->addRule((string) ($_POST['value'] ?? ''), (string) ($_POST['action'] ?? 'block')),
        'ip-access-remove' => $access->removeRule((string) ($_POST['value'] ?? '')),
        'ip-access-save' => $access->saveConfig([
            'enabled'        => ($_POST['enabled'] ?? '') === '1',
            'default_action' => (string) ($_POST['default_action'] ?? 'allow'),
            'geoip_db'       => trim((string) ($_POST['geoip_db'] ?? '')),
            'geoip_format'   => trim((string) ($_POST['geoip_format'] ?? 'mmdb')),
        ]),
        'ip-access-reload' => null,
        default => throw new \InvalidArgumentException("未知操作: $action"),
    };

    if (str_starts_with($action, 'site-')) {
        $reload = $sites->reload();
        $message = $reload['message'];
        header('Location: sites.php?ok=' . ($reload['ok'] ? '1' : '0') . '&msg=' . rawurlencode($message));
    }

    if (str_starts_with($action, 'ip-access-')) {
        $access->renderCaddyfile();
        header('Location: index.php?ok=' . ($access->reload() ? 1 : 0));
    }

    if (!str_starts_with($action, 'site-') && !str_starts_with($action, 'ip-access-')) {
        header('Location: index.php?ok=1');
    }
} catch (\Throwable $e) {
    http_response_code(500);
    header('Location: index.php?error=' . rawurlencode($e->getMessage()));
}
