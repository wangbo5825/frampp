<?php

declare(strict_types=1);

namespace Frampp\Agent\Tools;

use Frampp\Agent\AgentConfig;
use Frampp\Agent\AsTool;

final class LogTools
{
    private const FILES = [
        'frankenphp' => 'frankenphp.log',
        'mariadb'    => 'mariadb.log',
        'redis'      => 'redis.log',
        'panel'      => 'panel-access.log',
    ];

    public function __construct(private readonly AgentConfig $config)
    {
    }

    private function resolve(string $service): string
    {
        if (!$this->config->runtimeReady()) {
            throw new \RuntimeException('FRAMPP 运行时不可用');
        }
        $logsDir = realpath($this->config->runtimeDir() . DIRECTORY_SEPARATOR . 'logs');
        if ($logsDir === false) {
            throw new \RuntimeException('日志目录不存在');
        }
        $file = realpath($logsDir . DIRECTORY_SEPARATOR . (self::FILES[$service] ?? ''));
        if ($file === false || !str_starts_with($file, $logsDir . DIRECTORY_SEPARATOR)) {
            throw new \RuntimeException("日志文件不在白名单内: $service");
        }
        return $file;
    }

    #[AsTool('logs.tail', '实时查看应用日志尾部（路径白名单）', [
        'type' => 'object',
        'properties' => [
            'service' => ['type' => 'string', 'enum' => ['frankenphp', 'mariadb', 'redis', 'panel']],
            'lines' => ['type' => 'integer', 'description' => '行数，默认 50'],
        ],
        'required' => ['service'],
    ])]
    public function tail(array $args): array
    {
        $service = (string) ($args['service'] ?? '');
        if (!isset(self::FILES[$service])) {
            return ['isError' => true, 'text' => '未知服务，可选：' . implode('|', array_keys(self::FILES))];
        }
        $lines = max(1, min(500, (int) ($args['lines'] ?? 50)));
        $file = $this->resolve($service);
        if (!is_file($file)) {
            return ['text' => "（日志文件尚不存在: $file）"];
        }
        $content = (string) file_get_contents($file);
        $all = $content === '' ? [] : explode("\n", rtrim($content, "\r\n"));
        $tail = array_slice($all, -$lines);
        return ['text' => json_encode(['service' => $service, 'lines' => $tail], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)];
    }

    #[AsTool('logs.search', '按关键字搜索日志（路径白名单）', [
        'type' => 'object',
        'properties' => [
            'service' => ['type' => 'string', 'enum' => ['frankenphp', 'mariadb', 'redis', 'panel']],
            'keyword' => ['type' => 'string'],
            'limit' => ['type' => 'integer', 'description' => '最多返回行数，默认 50'],
        ],
        'required' => ['service', 'keyword'],
    ])]
    public function search(array $args): array
    {
        $service = (string) ($args['service'] ?? '');
        $keyword = (string) ($args['keyword'] ?? '');
        if (!isset(self::FILES[$service]) || $keyword === '') {
            return ['isError' => true, 'text' => '参数错误：service 或 keyword 无效'];
        }
        $limit = max(1, min(500, (int) ($args['limit'] ?? 50)));
        $file = $this->resolve($service);
        if (!is_file($file)) {
            return ['text' => "（日志文件尚不存在: $file）"];
        }
        $matches = [];
        $handle = fopen($file, 'rb');
        if ($handle !== false) {
            while (($line = fgets($handle)) !== false && count($matches) < $limit) {
                if (stripos($line, $keyword) !== false) {
                    $matches[] = rtrim($line, "\r\n");
                }
            }
            fclose($handle);
        }
        return ['text' => json_encode(['service' => $service, 'keyword' => $keyword, 'matches' => $matches], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)];
    }
}
