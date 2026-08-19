<?php

declare(strict_types=1);

namespace Frampp\Agent;

/**
 * 审计日志：所有工具调用写入 <runtime>/logs/agent-audit.log（JSON Lines）。
 */
final class AuditLogger
{
    private ?string $file = null;

    public function __construct(private readonly ?AgentConfig $config)
    {
        if ($config !== null && $config->runtimeReady()) {
            $dir = $config->runtimeDir() . DIRECTORY_SEPARATOR . 'logs';
            if (!is_dir($dir)) {
                @mkdir($dir, 0777, true);
            }
            $this->file = $dir . DIRECTORY_SEPARATOR . 'agent-audit.log';
        }
    }

    public function record(string $tool, array $arguments, array $result): void
    {
        if ($this->file === null) {
            return;
        }
        $entry = json_encode([
            'time'      => gmdate('c'),
            'tool'      => $tool,
            'arguments' => $arguments,
            'result'    => [
                'isError' => (bool) ($result['isError'] ?? false),
                'size'    => strlen((string) ($result['text'] ?? '')),
            ],
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        @file_put_contents($this->file, $entry . PHP_EOL, FILE_APPEND | LOCK_EX);
    }
}
