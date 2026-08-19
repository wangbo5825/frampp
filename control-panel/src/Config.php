<?php

declare(strict_types=1);

namespace Frampp\ControlPanel;

/**
 * 运行时配置发现：定位 FRAMPP 运行时目录并加载 runtime.json / secrets.json。
 *
 * 查找顺序：
 *   1. 环境变量 FRAMPP_HOME
 *   2. 安装布局：<runtime>/control-panel/src/../.. 下存在 data/runtime.json
 *   3. 开发布局：<repo>/dist/runtime
 */
final class Config
{
    /** @var string 运行时根目录 */
    public readonly string $root;

    /** @var array<string,mixed> runtime.json 内容 */
    public readonly array $runtime;

    /** @var array<string,string> secrets.json 内容 */
    public readonly array $secrets;

    private function __construct(string $root, array $runtime, array $secrets)
    {
        $this->root = $root;
        $this->runtime = $runtime;
        $this->secrets = $secrets;
    }

    public static function discover(?string $home = null): self
    {
        $root = $home ?? getenv('FRAMPP_HOME') ?: null;

        if ($root === null) {
            $base = dirname(__DIR__, 2);
            $candidates = [
                $base,                                  // 安装布局：<runtime>
                $base . DIRECTORY_SEPARATOR . 'dist' . DIRECTORY_SEPARATOR . 'runtime', // 开发布局
            ];
            foreach ($candidates as $candidate) {
                if (is_file($candidate . DIRECTORY_SEPARATOR . 'data' . DIRECTORY_SEPARATOR . 'runtime.json')) {
                    $root = $candidate;
                    break;
                }
            }
        }

        if ($root === null || !is_dir($root)) {
            throw new \RuntimeException(
                '无法定位 FRAMPP 运行时。请设置环境变量 FRAMPP_HOME，或先运行 installer/scripts/init.ps1。'
            );
        }

        $runtimeFile = $root . DIRECTORY_SEPARATOR . 'data' . DIRECTORY_SEPARATOR . 'runtime.json';
        $secretsFile = $root . DIRECTORY_SEPARATOR . 'data' . DIRECTORY_SEPARATOR . 'secrets.json';

        if (!is_file($runtimeFile)) {
            throw new \RuntimeException("缺少运行时清单: {$runtimeFile}（请先运行 init.ps1）");
        }
        $runtime = json_decode((string) file_get_contents($runtimeFile), true, 512, JSON_THROW_ON_ERROR);

        $secrets = [];
        if (is_file($secretsFile)) {
            $secrets = json_decode((string) file_get_contents($secretsFile), true, 512, JSON_THROW_ON_ERROR);
        }

        return new self($root, $runtime, $secrets);
    }

    public function bin(string $component): string
    {
        return $this->root . DIRECTORY_SEPARATOR . $component;
    }

    public function dataDir(string $sub = ''): string
    {
        return $this->root . DIRECTORY_SEPARATOR . 'data' . ($sub !== '' ? DIRECTORY_SEPARATOR . $sub : '');
    }

    public function logsDir(): string
    {
        return $this->root . DIRECTORY_SEPARATOR . 'logs';
    }

    public function port(string $name): int
    {
        return (int) ($this->runtime['ports'][$name] ?? 0);
    }

    public function secret(string $name): ?string
    {
        return $this->secrets[$name] ?? null;
    }
}
