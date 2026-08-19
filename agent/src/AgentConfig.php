<?php

declare(strict_types=1);

namespace Frampp\Agent;

/**
 * Agent 配置：自动发现 FRAMPP 运行时，加载密钥与工具开关。
 */
final class AgentConfig
{
    /** @var array<string,mixed> */
    public readonly array $raw;

    /** @var array<string,mixed> */
    public readonly array $secrets;

    /** @var array<string,mixed>|null */
    public readonly ?array $runtime;

    private function __construct(
        public readonly ?string $runtimeRoot,
        public readonly ?string $projectDir,
        array $raw,
        array $secrets,
        ?array $runtime,
    ) {
        $this->raw = $raw;
        $this->secrets = $secrets;
        $this->runtime = $runtime;
    }

    public static function load(?string $configFile = null, ?string $home = null): self
    {
        $configFile ??= dirname(__DIR__) . DIRECTORY_SEPARATOR . 'config' . DIRECTORY_SEPARATOR . 'frampp-mcp.json';
        $raw = [];
        if (is_file($configFile)) {
            $raw = json_decode((string) file_get_contents($configFile), true, 512, JSON_THROW_ON_ERROR);
        }

        $runtimeRoot = $home ?? getenv('FRAMPP_HOME') ?: null;
        $secrets = [];
        $runtime = null;
        if ($runtimeRoot !== null || is_dir($runtimeRoot ?? '')) {
            // 显式指定时使用
        } else {
            // 自动发现：安装布局 <root>/data/runtime.json；开发布局 <repo>/dist/runtime
            $base = dirname(__DIR__, 2);
            foreach ([$base, $base . DIRECTORY_SEPARATOR . 'dist' . DIRECTORY_SEPARATOR . 'runtime'] as $candidate) {
                if (is_file($candidate . DIRECTORY_SEPARATOR . 'data' . DIRECTORY_SEPARATOR . 'runtime.json')) {
                    $runtimeRoot = $candidate;
                    break;
                }
            }
        }

        if ($runtimeRoot !== null && is_dir($runtimeRoot)) {
            $runtimeFile = $runtimeRoot . DIRECTORY_SEPARATOR . 'data' . DIRECTORY_SEPARATOR . 'runtime.json';
            if (is_file($runtimeFile)) {
                $runtime = json_decode((string) file_get_contents($runtimeFile), true, 512, JSON_THROW_ON_ERROR);
            }
            $secretsFile = $runtimeRoot . DIRECTORY_SEPARATOR . 'data' . DIRECTORY_SEPARATOR . 'secrets.json';
            if (is_file($secretsFile)) {
                $secrets = json_decode((string) file_get_contents($secretsFile), true, 512, JSON_THROW_ON_ERROR);
            }
        }

        $projectDir = $raw['project'] ?? null;
        if ($projectDir !== null && !is_dir($projectDir)) {
            $projectDir = null;
        }

        return new self($runtimeRoot, $projectDir, $raw, $secrets, $runtime);
    }

    public function enabled(string $group): bool
    {
        return (bool) ($this->raw['enabled'][$group] ?? true);
    }

    public function runtimeReady(): bool
    {
        return $this->runtimeRoot !== null && $this->runtime !== null;
    }

    public function secret(string $name): ?string
    {
        return $this->secrets[$name] ?? null;
    }

    public function runtimeDir(): string
    {
        return (string) $this->runtimeRoot;
    }

    public function int(string $key, int $default): int
    {
        return (int) ($this->raw[$key] ?? $default);
    }
}
