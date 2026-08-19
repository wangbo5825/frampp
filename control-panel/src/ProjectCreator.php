<?php

declare(strict_types=1);

namespace Frampp\ControlPanel;

/**
 * 一键创建项目：minimal（离线模板）/ symfony / api-platform（composer create-project）。
 */
final class ProjectCreator
{
    public function __construct(private readonly Config $config)
    {
    }

    public function create(string $name, string $type = 'minimal'): array
    {
        $name = trim($name);
        if (!preg_match('/^[a-z0-9][a-z0-9_-]*$/i', $name)) {
            throw new \InvalidArgumentException('项目名仅允许字母、数字、下划线、连字符（且不能以数字符号开头）');
        }
        if (!in_array($type, ['minimal', 'symfony', 'api-platform'], true)) {
            throw new \InvalidArgumentException("未知项目类型: $type（可选 minimal|symfony|api-platform）");
        }

        $target = $this->config->root . DIRECTORY_SEPARATOR . 'htdocs' . DIRECTORY_SEPARATOR . $name;
        if (is_dir($target) || is_file($target)) {
            throw new \RuntimeException("目标已存在: $target");
        }

        return match ($type) {
            'minimal'     => $this->createMinimal($name, $target),
            'symfony'     => $this->createFromComposer($name, $target, ['symfony/skeleton']),
            'api-platform' => $this->createFromComposer($name, $target, ['symfony/skeleton', 'api-platform/core']),
        };
    }

    private function createMinimal(string $name, string $target): array
    {
        $template = $this->config->root . DIRECTORY_SEPARATOR . 'templates' . DIRECTORY_SEPARATOR . 'project-minimal';
        if (!is_dir($template)) {
            // 开发布局回退：<repo>/installer/templates/project-minimal
            $repo = dirname(__DIR__, 2);
            $template = $repo . DIRECTORY_SEPARATOR . 'installer' . DIRECTORY_SEPARATOR . 'templates' . DIRECTORY_SEPARATOR . 'project-minimal';
        }
        if (!is_dir($template)) {
            throw new \RuntimeException('缺少 minimal 项目模板（templates/project-minimal）');
        }

        $this->copyTree($template, $target);
        $composerFile = $target . DIRECTORY_SEPARATOR . 'composer.json';
        if (is_file($composerFile)) {
            $content = (string) file_get_contents($composerFile);
            $content = str_replace('frampp/hello', 'frampp/' . strtolower($name), $content);
            file_put_contents($composerFile, $content);
        }
        return ['name' => $name, 'type' => 'minimal', 'path' => $target];
    }

    /**
     * 第一步 create-project 创建骨架，后续包在项目内 composer require（如 api-platform/core）。
     *
     * @param list<string> $steps
     */
    private function createFromComposer(string $name, string $target, array $steps): array
    {
        $php = $this->config->bin('frankenphp') . DIRECTORY_SEPARATOR . 'php.exe';
        $composer = $this->config->bin('bin') . DIRECTORY_SEPARATOR . 'composer.phar';
        foreach ([$php, $composer] as $file) {
            if (!is_file($file)) {
                throw new \RuntimeException("缺少依赖文件: $file");
            }
        }
        $first = array_shift($steps);
        $cmd = sprintf(
            '%s -d memory_limit=1G %s create-project %s %s --no-interaction --no-ansi --no-progress --prefer-dist 2>&1',
            escapeshellarg($php),
            escapeshellarg($composer),
            escapeshellarg((string) $first),
            escapeshellarg($target)
        );
        $run = $this->runComposer($cmd);
        $output = $run['output'];
        $code = $run['code'];
        if ($code !== 0 || !is_dir($target)) {
            throw new \RuntimeException("composer create-project {$first} 失败（exit={$code}）：" . implode("\n", array_slice($output, -20)));
        }

        $requires = [];
        foreach ($steps as $package) {
            $cmd = sprintf(
                '%s -d memory_limit=1G %s require %s --no-interaction --no-ansi --no-progress --prefer-dist 2>&1',
                escapeshellarg($php),
                escapeshellarg($composer),
                escapeshellarg($package)
            );
            $run = $this->runComposerIn($cmd, $target);
            $output = $run['output'];
            $code = $run['code'];
            if ($code !== 0) {
                throw new \RuntimeException("composer require {$package} 失败（exit={$code}）：" . implode("\n", array_slice($output, -20)));
            }
            $requires[] = $package;
        }

        return ['name' => $name, 'path' => $target, 'composer_steps' => array_merge([$first], $requires)];
    }

    /**
     * 网络抖动时重试 composer 命令（最多 3 次，间隔 10s）。
     *
     * @return array{output:list<string>,code:int}
     */
    private function runComposer(string $cmd): array
    {
        $lastOutput = [];
        $lastCode = 1;
        for ($attempt = 1; $attempt <= 3; $attempt++) {
            $output = [];
            $code = 0;
            exec($cmd, $output, $code);
            if ($code === 0) {
                return ['output' => $output, 'code' => 0];
            }
            $lastOutput = $output;
            $lastCode = $code;
            if ($attempt < 3) {
                sleep(10);
            }
        }
        return ['output' => $lastOutput, 'code' => $lastCode];
    }

    /**
     * 在指定目录内执行 composer（require 必须在项目目录中运行）。
     *
     * @return array{output:list<string>,code:int}
     */
    private function runComposerIn(string $cmd, string $cwd): array
    {
        $prev = getcwd();
        chdir($cwd);
        try {
            return $this->runComposer($cmd);
        } finally {
            if ($prev !== false) {
                chdir($prev);
            }
        }
    }

    private function copyTree(string $src, string $dst): void
    {
        mkdir($dst, 0777, true);
        $iterator = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($src, \FilesystemIterator::SKIP_DOTS),
            \RecursiveIteratorIterator::SELF_FIRST
        );
        foreach ($iterator as $item) {
            $relative = substr($item->getPathname(), strlen($src));
            $dest = $dst . DIRECTORY_SEPARATOR . ltrim($relative, DIRECTORY_SEPARATOR);
            if ($item->isDir()) {
                mkdir($dest, 0777, true);
            } else {
                copy($item->getPathname(), $dest);
            }
        }
    }
}
