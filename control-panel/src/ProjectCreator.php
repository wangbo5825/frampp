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
            'minimal' => $this->createMinimal($name, $target),
            default   => $this->createFromComposer($name, $target, $type),
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

    private function createFromComposer(string $name, string $target, string $type): array
    {
        $php = $this->config->bin('frankenphp') . DIRECTORY_SEPARATOR . 'php.exe';
        $composer = $this->config->bin('bin') . DIRECTORY_SEPARATOR . 'composer.phar';
        foreach ([$php, $composer] as $file) {
            if (!is_file($file)) {
                throw new \RuntimeException("缺少依赖文件: $file");
            }
        }
        $package = $type === 'symfony' ? 'symfony/skeleton' : 'api-platform/api-platform';
        $cmd = sprintf(
            '%s %s create-project %s %s --no-interaction --no-ansi 2>&1',
            escapeshellarg($php),
            escapeshellarg($composer),
            escapeshellarg($package),
            escapeshellarg($target)
        );
        $output = [];
        $code = 0;
        exec($cmd, $output, $code);
        if ($code !== 0 || !is_dir($target)) {
            throw new \RuntimeException("composer create-project 失败（exit=$code）：" . implode("\n", array_slice($output, -20)));
        }
        return ['name' => $name, 'type' => $type, 'path' => $target, 'composer_exit' => $code];
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
