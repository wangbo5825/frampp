<?php

declare(strict_types=1);

namespace Frampp\ControlPanel;

require_once __DIR__ . '/CaddyAdminClient.php';

/**
 * IP 访问控制：管理 etc/access.json 与 etc/access-filter.rules，
 * 生成 etc/access-filter.caddy，并通过 Caddy admin API 热重载。
 *
 * 规则格式（caddy-access-filter v1.2.1）：
 *   <IP|CIDR|code:XX> <allow|block>
 */
final class AccessManager
{
    public function __construct(private readonly Config $config)
    {
    }

    public function supported(): bool
    {
        // Windows 官方预编译 FrankenPHP 暂未内置 caddy-access-filter
        return PHP_OS_FAMILY !== 'Windows';
    }

    /**
     * @return array{enabled:bool,supported:bool,default_action:string,geoip_db:string,geoip_format:string}
     */
    public function config(): array
    {
        $default = [
            'enabled'        => $this->supported(),
            'supported'      => $this->supported(),
            'default_action' => 'allow',
            'geoip_db'       => '',
            'geoip_format'   => '',
        ];
        $file = $this->config->etcDir('access.json');
        if (!is_file($file)) {
            return $default;
        }
        $raw = json_decode((string) file_get_contents($file), true, 512, JSON_THROW_ON_ERROR);
        return array_merge($default, is_array($raw) ? $raw : []);
    }

    public function saveConfig(array $values): void
    {
        $cfg = $this->config();
        foreach (['enabled', 'supported', 'default_action', 'geoip_db', 'geoip_format'] as $key) {
            if (array_key_exists($key, $values)) {
                $cfg[$key] = $values[$key];
            }
        }
        $cfg['supported'] = $this->supported();
        $cfg['enabled'] = (bool) $cfg['enabled'] && $this->supported();
        $cfg['default_action'] = in_array($cfg['default_action'], ['allow', 'block'], true) ? $cfg['default_action'] : 'allow';
        $file = $this->config->etcDir('access.json');
        file_put_contents(
            $file,
            json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL
        );
    }

    /**
     * @return list<array{value:string,action:string}>
     */
    public function rules(): array
    {
        $file = $this->config->etcDir('access-filter.rules');
        if (!is_file($file)) {
            return [];
        }
        $result = [];
        foreach (explode("\n", (string) file_get_contents($file)) as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#')) {
                continue;
            }
            $parts = preg_split('/\s+/', $line);
            if (count($parts) < 2) {
                continue;
            }
            $result[] = ['value' => $parts[0], 'action' => $parts[1]];
        }
        return $result;
    }

    public function addRule(string $value, string $action): void
    {
        $value = trim($value);
        $action = strtolower(trim($action));
        if (!preg_match('/^(?:[0-9a-fA-F:.]+(?:\/\d{1,3})?|code:[A-Za-z]{2})$/u', $value)) {
            throw new \InvalidArgumentException('规则格式无效：需要 IP、CIDR 或 code:XX（如 203.0.113.10 / 198.51.100.0/24 / code:CN）');
        }
        if (!in_array($action, ['allow', 'block'], true)) {
            throw new \InvalidArgumentException('操作仅支持 allow / block');
        }
        $rules = $this->rules();
        foreach ($rules as &$rule) {
            if ($rule['value'] === $value) {
                $rule['action'] = $action;
                $this->writeRules($rules);
                return;
            }
        }
        unset($rule);
        $rules[] = ['value' => $value, 'action' => $action];
        $this->writeRules($rules);
    }

    public function removeRule(string $value): void
    {
        $value = trim($value);
        $rules = array_values(array_filter(
            $this->rules(),
            static fn (array $rule): bool => $rule['value'] !== $value
        ));
        $this->writeRules($rules);
    }

    public function renderCaddyfile(): void
    {
        // v0.7.0 起安装包内模板位于 share/templates/；旧安装/开发布局回退 installer/templates/
        $template = '';
        foreach ([
            'share' . DIRECTORY_SEPARATOR . 'templates',
            'installer' . DIRECTORY_SEPARATOR . 'templates',
        ] as $rel) {
            $candidate = $this->config->root . DIRECTORY_SEPARATOR . $rel . DIRECTORY_SEPARATOR . 'Caddyfile.template';
            if (is_file($candidate)) {
                $template = $candidate;
                break;
            }
        }
        if (!is_file($template)) {
            throw new \RuntimeException("缺少 Caddyfile 模板: {$template}");
        }
        $content = (string) file_get_contents($template);

        $cfg = $this->config();
        $accessCaddy = $this->config->etcDir('access-filter.caddy');
        if ($cfg['enabled'] && $this->supported()) {
            $lines = [
                'access {',
                '    name frampp_access',
                '    rules file ' . $this->config->etcDir('access-filter.rules'),
                '    default_action ' . $cfg['default_action'],
            ];
            if ($cfg['geoip_db'] !== '') {
                $lines[] = '    geoip {';
                $lines[] = '        database ' . $cfg['geoip_db'];
                $lines[] = '        format ' . ($cfg['geoip_format'] !== '' ? $cfg['geoip_format'] : 'mmdb');
                $lines[] = '    }';
            }
            $lines[] = '}';
            file_put_contents($accessCaddy, implode("\n", $lines) . "\n");
            $import = 'import ' . $accessCaddy;
        } else {
            file_put_contents($accessCaddy, "# access-filter disabled\n");
            $import = '# access-filter disabled';
        }

        $replace = [
            '{{HTDOCS}}'        => str_replace('\\', '/', $this->config->root . DIRECTORY_SEPARATOR . 'htdocs'),
            '{{PANEL_ROOT}}'    => str_replace('\\', '/', $this->config->module('control-panel') . DIRECTORY_SEPARATOR . 'web'),
            '{{LOGS_DIR}}'      => str_replace('\\', '/', $this->config->logsDir()),
            '{{ACCESS_IMPORT}}' => $import,
            '{{CADDY_D}}'       => str_replace('\\', '/', $this->config->etcDir('caddy.d')),
            '{{ADMIN_ADDR}}'    => $this->caddyAdminAddr(),
        ];
        $content = str_replace(array_keys($replace), array_values($replace), $content);
        file_put_contents($this->config->etcDir('Caddyfile'), $content);
    }

    public function reload(): bool
    {
        if (!$this->supported()) {
            return false;
        }
        $result = (new CaddyAdminClient($this->config))
            ->post('/access-filter/reload?scope=all&name=frampp_access', '');
        return $result['status'] >= 200 && $result['status'] < 300;
    }

    /** Caddyfile admin 指令语法：TCP 填 127.0.0.1:2019，unix socket 填 unix//path */
    private function caddyAdminAddr(): string
    {
        $address = $this->config->adminAddress();
        if (str_starts_with($address, 'unix://')) {
            return 'unix//' . substr($address, 7);
        }
        return preg_replace('#^https?://#', '', $address);
    }

    /**
     * @param list<array{value:string,action:string}> $rules
     */
    private function writeRules(array $rules): void
    {
        $lines = ['# FRAMPP IP 访问规则 / IP access rules', '# 格式 / format: <IP|CIDR|code:XX> <allow|block>'];
        foreach ($rules as $rule) {
            $lines[] = $rule['value'] . ' ' . $rule['action'];
        }
        file_put_contents($this->config->etcDir('access-filter.rules'), implode("\n", $lines) . "\n");
    }
}
