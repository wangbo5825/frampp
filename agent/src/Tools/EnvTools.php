<?php

declare(strict_types=1);

namespace Frampp\Agent\Tools;

use Frampp\Agent\AgentConfig;
use Frampp\Agent\AsTool;

/**
 * 环境工具：命令一律由固定模板 + escapeshellarg 构造（强白名单），不接受任意命令。
 */
final class EnvTools
{
    public function __construct(private readonly AgentConfig $config)
    {
    }

    private function phpBin(): string
    {
        if (!$this->config->runtimeReady()) {
            throw new \RuntimeException('FRAMPP 运行时不可用');
        }
        $bin = $this->config->runtimeDir() . DIRECTORY_SEPARATOR . 'modules' . DIRECTORY_SEPARATOR . 'frankenphp'
            . DIRECTORY_SEPARATOR . (PHP_OS_FAMILY === 'Windows' ? 'frankenphp.exe' : 'frankenphp');
        return is_file($bin) ? $bin : 'php';
    }

    /**
     * @param array<string,string> $values
     */
    private function execTemplate(string $template, array $values, ?string $cwd = null): string
    {
        $replace = [];
        foreach ($values as $k => $v) {
            $replace['{' . $k . '}'] = escapeshellarg($v);
        }
        $cmd = strtr($template, $replace);
        $output = [];
        $code = 0;
        $prev = getcwd();
        if ($cwd !== null) {
            chdir($cwd);
        }
        try {
            exec($cmd . ' 2>&1', $output, $code);
        } finally {
            if ($prev !== false) {
                chdir($prev);
            }
        }
        return implode("\n", array_slice($output, 0, 500));
    }

    #[AsTool('env.php_version', '查看 PHP 版本与环境信息（只读）')]
    public function phpVersion(array $args = []): array
    {
        $text = $this->execTemplate('{php} php-cli -v', ['php' => $this->phpBin()]);
        return ['text' => $text];
    }

    #[AsTool('env.composer_show', '列出项目已安装的 Composer 包（只读）', [
        'type' => 'object',
        'properties' => ['direct_only' => ['type' => 'boolean']],
    ])]
    public function composerShow(array $args = []): array
    {
        if ($this->config->projectDir === null) {
            return ['text' => '未配置 project 目录（agent/config/frampp-mcp.json）'];
        }
        $composer = $this->config->runtimeDir() . DIRECTORY_SEPARATOR . 'modules' . DIRECTORY_SEPARATOR . 'composer'
            . DIRECTORY_SEPARATOR . 'composer.phar';
        if (!is_file($composer)) {
            return ['isError' => true, 'text' => '缺少 composer.phar'];
        }
        $flag = !empty($args['direct_only']) ? ' --direct' : '';
        $text = $this->execTemplate(
            '{php} php-cli {composer} show --no-ansi --no-interaction' . $flag,
            ['php' => $this->phpBin(), 'composer' => $composer],
            $this->config->projectDir
        );
        return ['text' => $text];
    }

    #[AsTool('env.services_status', '查看 FRAMPP 三件套服务状态（只读）')]
    public function servicesStatus(array $args = []): array
    {
        $cli = $this->config->runtimeDir() . DIRECTORY_SEPARATOR . 'modules' . DIRECTORY_SEPARATOR . 'control-panel'
            . DIRECTORY_SEPARATOR . 'bin' . DIRECTORY_SEPARATOR . 'frampp';
        if (!is_file($cli)) {
            $cli = dirname(__DIR__, 3) . DIRECTORY_SEPARATOR . 'control-panel' . DIRECTORY_SEPARATOR . 'bin' . DIRECTORY_SEPARATOR . 'frampp';
        }
        if (!is_file($cli)) {
            return ['isError' => true, 'text' => '未找到控制面板 CLI'];
        }
        $text = $this->execTemplate(
            '{php} php-cli {cli} status --json --home {home}',
            ['php' => $this->phpBin(), 'cli' => $cli, 'home' => $this->config->runtimeDir()]
        );
        return ['text' => $text];
    }

    #[AsTool('env.project_info', '查看项目结构与 composer.json（只读）')]
    public function projectInfo(array $args = []): array
    {
        if ($this->config->projectDir === null) {
            return ['text' => '未配置 project 目录'];
        }
        $dir = $this->config->projectDir;
        $info = ['root' => $dir];
        $composerFile = $dir . DIRECTORY_SEPARATOR . 'composer.json';
        if (is_file($composerFile)) {
            $info['composer'] = json_decode((string) file_get_contents($composerFile), true, 512, JSON_THROW_ON_ERROR);
        }
        $entries = scandir($dir) ?: [];
        $info['entries'] = array_values(array_filter(
            $entries,
            static fn (string $e): bool => $e !== '.' && $e !== '..' && !str_starts_with($e, '.')
        ));
        return ['text' => json_encode($info, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)];
    }
}
