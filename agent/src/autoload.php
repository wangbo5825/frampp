<?php

declare(strict_types=1);

/**
 * FRAMPP Agent 轻量 PSR-4 自动加载（零依赖，避免引入 Composer 供应链）。
 */
spl_autoload_register(static function (string $class): void {
    $prefix = 'Frampp\\Agent\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }
    $relative = substr($class, strlen($prefix));
    $file = __DIR__ . DIRECTORY_SEPARATOR . str_replace('\\', DIRECTORY_SEPARATOR, $relative) . '.php';
    if (is_file($file)) {
        require $file;
    }
});
