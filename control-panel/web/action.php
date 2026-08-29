<?php

declare(strict_types=1);

require __DIR__ . '/../src/Config.php';
require __DIR__ . '/../src/ServiceManager.php';
require __DIR__ . '/../src/AccessManager.php';

use Frampp\ControlPanel\Config;
use Frampp\ControlPanel\ServiceManager;
use Frampp\ControlPanel\AccessManager;

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

    $result = match ($action) {
        'start' => $mgr->start($service),
        'stop'  => $mgr->stop($service),
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

    if (str_starts_with($action, 'ip-access-')) {
        $access->renderCaddyfile();
        $result = ['reloaded' => $action === 'ip-access-reload' ? $access->reload() : $access->reload()];
    }

    header('Location: index.php?ok=' . (is_array($result) && ($result['reloaded'] ?? true) ? 1 : 0));
} catch (\Throwable $e) {
    http_response_code(500);
    header('Location: index.php?error=' . rawurlencode($e->getMessage()));
}
