<?php

declare(strict_types=1);

namespace Frampp\ControlPanel;

/**
 * 站点管理：维护 etc/caddy.d/*.caddy 站点片段，
 * 重建 Caddyfile 并通过 Caddy admin API（/load, text/caddyfile）热重载。
 *
 * 站点片段格式（Caddyfile 站点块）：
 *   <address> {
 *       root * <document root>
 *       [php]
 *       encode zstd gzip
 *       [reverse_proxy <target>]
 *       [file_server]
 *       log { output file <logfile> }
 *   }
 */
final class SiteManager
{
    public function __construct(private readonly Config $config)
    {
    }

    /**
     * 可管理的站点类型。
     *
     * @return array<string,string> type => 中文说明
     */
    public function types(): array
    {
        return [
            'php'    => 'PHP 站点（root + PHP + file_server）',
            'static' => '静态站点（root + file_server）',
            'proxy'  => '反向代理（reverse_proxy）',
        ];
    }

    /**
     * 列出 etc/caddy.d/ 下所有站点片段。
     *
     * @return list<array{name:string,file:string,address:string,type:string,root:string,target:string}>
     */
    public function sites(): array
    {
        $dir = $this->config->etcDir('caddy.d');
        $result = [];
        if (!is_dir($dir)) {
            return $result;
        }
        foreach (glob($dir . DIRECTORY_SEPARATOR . '*.caddy') ?: [] as $file) {
            $name = basename($file, '.caddy');
            if ($name === '00-default') {
                continue;
            }
            $content = (string) file_get_contents($file);
            $result[] = [
                'name'    => $name,
                'file'    => $file,
                'address' => $this->extractAddress($content),
                'type'    => $this->detectType($content),
                'root'    => $this->extractRoot($content),
                'target'  => $this->extractTarget($content),
            ];
        }
        return $result;
    }

    /**
     * 新建或更新站点片段。
     *
     * @param array{address:string,type:string,root:string,target:string} $values
     */
    public function saveSite(string $name, array $values): void
    {
        $name = trim($name);
        if (!preg_match('/^[A-Za-z0-9._-]{1,64}$/', $name)) {
            throw new \InvalidArgumentException('站点名称仅支持字母、数字、点、下划线与短横线（最长 64 字符）');
        }
        if ($name === '00-default') {
            throw new \InvalidArgumentException('站点名称 00-default 为保留示例文件');
        }

        $address = trim((string) ($values['address'] ?? ''));
        $type = (string) ($values['type'] ?? 'php');
        if (!isset($this->types()[$type])) {
            throw new \InvalidArgumentException('未知站点类型');
        }
        if ($address === '') {
            throw new \InvalidArgumentException('监听地址不能为空，例如 http://127.0.0.1:8082 或 example.com');
        }

        $root = rtrim(str_replace('\\', '/', trim((string) ($values['root'] ?? ''))), '/');
        $target = trim((string) ($values['target'] ?? ''));

        if (($type === 'php' || $type === 'static') && $root === '') {
            throw new \InvalidArgumentException('PHP / 静态站点需要填写文档根目录 root');
        }
        if ($type === 'proxy' && $target === '') {
            throw new \InvalidArgumentException('反向代理站点需要填写目标地址 target');
        }

        $lines = [];
        $lines[] = '# FRAMPP site: ' . $name . ' (managed by control panel)';
        $lines[] = $address . ' {';
        if ($type === 'php' || $type === 'static') {
            $lines[] = '    root * ' . $root;
        }
        if ($type === 'php') {
            $lines[] = '    php';
        }
        $lines[] = '    encode zstd gzip';
        if ($type === 'proxy') {
            $lines[] = '    reverse_proxy ' . $target;
        } else {
            $lines[] = '    file_server';
        }
        $lines[] = '    log {';
        $lines[] = '        output file ' . str_replace('\\', '/', $this->config->logsDir()) . '/' . $name . '-access.log';
        $lines[] = '    }';
        $lines[] = '}';

        $file = $this->config->etcDir('caddy.d') . DIRECTORY_SEPARATOR . $name . '.caddy';
        file_put_contents($file, implode("\n", $lines) . "\n");
    }

    public function deleteSite(string $name): void
    {
        $name = trim($name);
        if (!preg_match('/^[A-Za-z0-9._-]{1,64}$/', $name) || $name === '00-default') {
            throw new \InvalidArgumentException('站点名称无效或为保留文件');
        }
        $file = $this->config->etcDir('caddy.d') . DIRECTORY_SEPARATOR . $name . '.caddy';
        if (is_file($file) && !unlink($file)) {
            throw new \RuntimeException("无法删除站点文件: {$file}");
        }
    }

    /**
     * 重建 Caddyfile（复用 AccessManager 的模板渲染）并通过 admin API 热重载。
     *
     * @return array{ok:bool,message:string}
     */
    public function reload(): array
    {
        $access = new AccessManager($this->config);
        $access->renderCaddyfile();
        $caddyfile = $this->config->etcDir('Caddyfile');
        if (!is_file($caddyfile)) {
            return ['ok' => false, 'message' => "缺少 Caddyfile: {$caddyfile}"];
        }
        $body = (string) file_get_contents($caddyfile);

        $ctx = stream_context_create([
            'http' => [
                'method'        => 'POST',
                'header'        => "Content-Type: text/caddyfile\r\n",
                'content'       => $body,
                'ignore_errors' => true,
                'timeout'       => 5,
            ],
        ]);
        $response = @file_get_contents('http://127.0.0.1:2019/load', false, $ctx);
        $code = 0;
        foreach ($http_response_header ?? [] as $header) {
            if (preg_match('#^HTTP/\S+\s+(\d+)#', $header, $m)) {
                $code = (int) $m[1];
            }
        }
        if ($response !== false && $code >= 200 && $code < 300) {
            return ['ok' => true, 'message' => '配置已热重载'];
        }
        $message = '配置重载失败（HTTP ' . ($code ?: '?') . '）：' . trim((string) $response);
        return ['ok' => false, 'message' => $message !== '' ? $message : '无法连接 Caddy admin API（127.0.0.1:2019）'];
    }

    /** 从站点片段中提取监听地址（第一个非注释行） */
    private function extractAddress(string $content): string
    {
        foreach (explode("\n", $content) as $line) {
            $line = trim($line);
            if ($line !== '' && !str_starts_with($line, '#')) {
                return rtrim($line, ' {');
            }
        }
        return '';
    }

    private function detectType(string $content): string
    {
        if (str_contains($content, 'reverse_proxy')) {
            return 'proxy';
        }
        if (str_contains($content, 'php')) {
            return 'php';
        }
        return 'static';
    }

    private function extractRoot(string $content): string
    {
        return preg_match('/root \*\s+(\S+)/', $content, $m) ? $m[1] : '';
    }

    private function extractTarget(string $content): string
    {
        return preg_match('/reverse_proxy\s+(\S+)/', $content, $m) ? $m[1] : '';
    }
}
