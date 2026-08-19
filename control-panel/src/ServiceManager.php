<?php

declare(strict_types=1);

namespace Frampp\ControlPanel;

/**
 * 服务管理：FrankenPHP / MariaDB / Redis 的启停、状态、端口与日志。
 *
 * 安全基线：
 *   - 所有服务仅绑定 127.0.0.1；
 *   - Web 端变更操作必须携带 data/secrets.json 中的 panel_token；
 *   - 进程 PID 写入 data/*.pid，由控制面板统一管理。
 */
final class ServiceManager
{
    private const SERVICES = [
        'frankenphp' => ['port' => 'http',   'log' => 'frankenphp.log'],
        'mariadb'    => ['port' => 'mysql',  'log' => 'mariadb.log'],
        'redis'      => ['port' => 'redis',  'log' => 'redis.log'],
    ];

    public function __construct(private readonly Config $config)
    {
    }

    public static function services(): array
    {
        return array_keys(self::SERVICES);
    }

    /**
     * @return array<string,array{name:string,running:bool,pid:?int,port:?int,port_open:bool,error:?string}>
     */
    public function status(?string $only = null): array
    {
        $result = [];
        foreach (self::SERVICES as $name => $meta) {
            if ($only !== null && $only !== $name) {
                continue;
            }
            $pid = $this->readPid($name);
            $port = $this->config->port($meta['port']);
            $alive = $pid !== null && $this->isProcessAlive($pid);
            $result[$name] = [
                'name'      => $name,
                'running'   => $alive,
                'pid'       => $pid,
                'port'      => $port,
                'port_open' => $this->isPortOpen('127.0.0.1', $port),
                'error'     => null,
            ];
        }
        return $result;
    }

    public function start(string $name): array
    {
        if (!isset(self::SERVICES[$name])) {
            throw new \InvalidArgumentException("未知服务: $name（可选：" . implode('|', self::services()) . '）');
        }
        $status = $this->status($name)[$name];
        if ($status['running']) {
            return ['name' => $name, 'started' => false, 'message' => "已在运行 (PID {$status['pid']})"];
        }

        switch ($name) {
            case 'frankenphp':
                $pid = $this->startFrankenphp();
                break;
            case 'mariadb':
                $pid = $this->startMariadb();
                break;
            case 'redis':
                $pid = $this->startRedis();
                break;
            default:
                throw new \LogicException("未实现: $name");
        }

        if ($pid !== null) {
            $this->writePid($name, $pid);
        }
        return ['name' => $name, 'started' => true, 'pid' => $pid];
    }

    public function stop(string $name): array
    {
        if (!isset(self::SERVICES[$name])) {
            throw new \InvalidArgumentException("未知服务: $name");
        }
        $pid = $this->readPid($name);
        if ($pid === null || !$this->isProcessAlive($pid)) {
            $this->removePid($name);
            return ['name' => $name, 'stopped' => false, 'message' => '未在运行'];
        }

        // 先优雅终止，超时再强杀
        exec('taskkill /PID ' . (int) $pid . ' /T 2>NUL');
        for ($i = 0; $i < 20; $i++) {
            if (!$this->isProcessAlive($pid)) {
                break;
            }
            usleep(250_000);
        }
        if ($this->isProcessAlive($pid)) {
            exec('taskkill /PID ' . (int) $pid . ' /T /F 2>NUL');
        }
        $this->removePid($name);
        return ['name' => $name, 'stopped' => true];
    }

    public function tailLog(string $name, int $lines = 50): array
    {
        if (!isset(self::SERVICES[$name])) {
            throw new \InvalidArgumentException("未知服务: $name");
        }
        $logFile = $this->config->logsDir() . DIRECTORY_SEPARATOR . self::SERVICES[$name]['log'];
        if (!is_file($logFile)) {
            return ['name' => $name, 'file' => $logFile, 'lines' => []];
        }
        $content = (string) file_get_contents($logFile);
        $all = $content === '' ? [] : explode("\n", rtrim($content, "\r\n"));
        return ['name' => $name, 'file' => $logFile, 'lines' => array_slice($all, -$lines)];
    }

    public function ports(): array
    {
        $ports = [];
        foreach ($this->config->runtime['ports'] ?? [] as $name => $port) {
            $ports[$name] = ['port' => (int) $port, 'open' => $this->isPortOpen('127.0.0.1', (int) $port)];
        }
        return $ports;
    }

    private function startFrankenphp(): ?int
    {
        $exe = $this->config->bin('frankenphp') . DIRECTORY_SEPARATOR . 'frankenphp.exe';
        if (!is_file($exe)) {
            throw new \RuntimeException("缺少 FrankenPHP 可执行文件: $exe");
        }
        $args = ['run', '--config', $this->config->root . DIRECTORY_SEPARATOR . 'Caddyfile'];
        return $this->startDetached($exe, $args, $this->config->root, 'frankenphp');
    }

    private function startMariadb(): ?int
    {
        $exe = $this->config->bin('mariadb') . DIRECTORY_SEPARATOR . 'bin' . DIRECTORY_SEPARATOR . 'mariadbd.exe';
        if (!is_file($exe)) {
            throw new \RuntimeException("缺少 MariaDB 可执行文件: $exe");
        }
        $datadir = $this->config->dataDir('mariadb');
        $log = $this->config->logsDir() . DIRECTORY_SEPARATOR . 'mariadb.log';
        $args = [
            '--datadir=' . $datadir,
            '--port=' . $this->config->port('mysql'),
            '--bind-address=127.0.0.1',
            '--console',
        ];
        return $this->startDetached($exe, $args, $this->config->root, 'mariadb', $log);
    }

    private function startRedis(): ?int
    {
        $exe = $this->config->bin('redis') . DIRECTORY_SEPARATOR . 'redis-server.exe';
        if (!is_file($exe)) {
            throw new \RuntimeException("缺少 Redis 可执行文件: $exe");
        }
        $conf = $this->config->bin('redis') . DIRECTORY_SEPARATOR . 'redis.conf';
        return $this->startDetached($exe, [$conf], $this->config->root, 'redis');
    }

    /**
     * 通过 PowerShell Start-Process 以隐藏窗口方式拉起进程并记录 PID。
     */
    private function startDetached(string $exe, array $args, string $cwd, string $name, ?string $stderrLog = null): ?int
    {
        $stdout = $this->config->logsDir() . DIRECTORY_SEPARATOR . self::SERVICES[$name]['log'];
        $stderr = $stderrLog ?? $this->config->logsDir() . DIRECTORY_SEPARATOR . $name . '.err.log';
        $pidFile = $this->config->dataDir($name . '.pid');

        $payload = [
            'file'   => $exe,
            'args'   => $args,
            'cwd'    => $cwd,
            'stdout' => $stdout,
            'stderr' => $stderr,
            'pidFile'=> $pidFile,
        ];
        $tmp = tempnam(sys_get_temp_dir(), 'frampp-') . '.json';
        file_put_contents($tmp, json_encode($payload, JSON_UNESCAPED_SLASHES));

        $helper = dirname(__DIR__) . DIRECTORY_SEPARATOR . 'bin' . DIRECTORY_SEPARATOR . 'start-service.ps1';
        $cmd = sprintf(
            'powershell -NoProfile -ExecutionPolicy Bypass -File "%s" -JsonArgs "%s"',
            $helper,
            $tmp
        );
        $output = [];
        $exit = 0;
        exec($cmd . ' 2>NUL', $output, $exit);
        @unlink($tmp);

        $pid = $this->readPid($name);
        if ($pid === null) {
            throw new \RuntimeException("启动 $name 失败（未取得 PID），日志见 " . $stdout);
        }
        return $pid;
    }

    private function readPid(string $name): ?int
    {
        $file = $this->config->dataDir($name . '.pid');
        if (!is_file($file)) {
            return null;
        }
        $pid = (int) trim((string) file_get_contents($file));
        return $pid > 0 ? $pid : null;
    }

    private function writePid(string $name, int $pid): void
    {
        file_put_contents($this->config->dataDir($name . '.pid'), (string) $pid);
    }

    private function removePid(string $name): void
    {
        $file = $this->config->dataDir($name . '.pid');
        if (is_file($file)) {
            @unlink($file);
        }
    }

    private function isProcessAlive(int $pid): bool
    {
        exec('tasklist /FI "PID eq ' . $pid . '" /NH 2>NUL', $out, $exit);
        foreach ($out as $line) {
            if (str_contains($line, (string) $pid)) {
                return true;
            }
        }
        return false;
    }

    private function isPortOpen(string $host, int $port): bool
    {
        if ($port <= 0) {
            return false;
        }
        $fp = @fsockopen($host, $port, $errno, $errstr, 0.5);
        if ($fp !== false) {
            fclose($fp);
            return true;
        }
        return false;
    }
}
