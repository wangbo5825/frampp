<?php

declare(strict_types=1);

require __DIR__ . '/../src/Config.php';
require __DIR__ . '/../src/ServiceManager.php';

use Frampp\ControlPanel\Config;
use Frampp\ControlPanel\ServiceManager;

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

    $result = match ($action) {
        'start' => $mgr->start($service),
        'stop'  => $mgr->stop($service),
        default => throw new \InvalidArgumentException("未知操作: $action"),
    };

    header('Location: index.php?ok=1');
} catch (\Throwable $e) {
    http_response_code(500);
    header('Location: index.php?error=' . rawurlencode($e->getMessage()));
}
