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

    private const WINDOWS = PHP_OS_FAMILY === 'Windows';

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
            throw new \InvalidArgumentException("未知服务: {$name}（可选：" . implode('|', self::services()) . '）');
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
        if (self::WINDOWS) {
            exec('taskkill /PID ' . (int) $pid . ' /T 2>NUL');
        } else {
            exec('kill ' . (int) $pid . ' 2>/dev/null');
        }
        for ($i = 0; $i < 20; $i++) {
            if (!$this->isProcessAlive($pid)) {
                break;
            }
            usleep(250_000);
        }
        if ($this->isProcessAlive($pid)) {
            if (self::WINDOWS) {
                exec('taskkill /PID ' . (int) $pid . ' /T /F 2>NUL');
            } else {
                exec('kill -9 ' . (int) $pid . ' 2>/dev/null');
            }
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
        $exe = $this->config->bin('frankenphp') . DIRECTORY_SEPARATOR . $this->exeName('frankenphp');
        if (!is_file($exe)) {
            throw new \RuntimeException("缺少 FrankenPHP 可执行文件: $exe");
        }
        $args = ['run', '--config', $this->config->root . DIRECTORY_SEPARATOR . 'Caddyfile'];
        return $this->startDetached($exe, $args, $this->config->root, 'frankenphp');
    }

    private function startMariadb(): ?int
    {
        $exe = $this->config->bin('mariadb') . DIRECTORY_SEPARATOR . 'bin' . DIRECTORY_SEPARATOR . $this->exeName('mariadbd');
        if (!is_file($exe)) {
            throw new \RuntimeException("缺少 MariaDB 可执行文件: $exe");
        }
        $datadir = $this->config->dataDir('mariadb');
        $log = $this->config->logsDir() . DIRECTORY_SEPARATOR . 'mariadb.log';
        $args = [
            '--no-defaults',
            '--datadir=' . $datadir,
            '--port=' . $this->config->port('mysql'),
            '--bind-address=127.0.0.1',
        ];
        if (self::WINDOWS) {
            $args[] = '--console';
        } else {
            $args[] = '--log-error=' . $this->config->logsDir() . DIRECTORY_SEPARATOR . 'mariadb.err.log';
            // 以 root 运行时 mariadbd 拒绝启动，需显式 --user
            $user = trim((string) shell_exec('id -un 2>/dev/null'));
            if ($user !== '') {
                $args[] = '--user=' . $user;
            }
        }
        return $this->startDetached($exe, $args, $this->config->root, 'mariadb');
    }

    private function startRedis(): ?int
    {
        $exe = $this->config->bin('redis') . DIRECTORY_SEPARATOR . $this->exeName('redis-server');
        if (!is_file($exe)) {
            throw new \RuntimeException("缺少 Redis 可执行文件: $exe");
        }
        // msys2 构建会按 POSIX 路径解析绝对路径参数；必须在其目录内用相对路径启动
        // Linux 静态构建行为一致：相对路径启动 redis.conf 最稳妥
        $redisDir = $this->config->bin('redis');
        if (!is_dir($this->config->dataDir('redis'))) {
            mkdir($this->config->dataDir('redis'), 0777, true);
        }
        return $this->startDetached($exe, ['redis.conf'], $redisDir, 'redis');
    }

    /**
     * 通过 proc_open 直接拉起进程（Windows 下 bypass_shell 绕开 cmd.exe），
     * 输出重定向到日志文件，进程脱离父进程独立运行；PID 交由调用方落盘。
     */
    private function startDetached(string $exe, array $args, string $cwd, string $name, ?string $stderrLog = null): ?int
    {
        $stdout = $this->config->logsDir() . DIRECTORY_SEPARATOR . self::SERVICES[$name]['log'];
        $stderr = $stderrLog ?? $this->config->logsDir() . DIRECTORY_SEPARATOR . $name . '.err.log';

        $descriptors = [
            0 => ['file', self::WINDOWS ? 'NUL' : '/dev/null', 'r'],
            1 => ['file', $stdout, 'a'],
            2 => ['file', $stderr, 'a'],
        ];
        $options = [];
        if (self::WINDOWS) {
            $options['bypass_shell'] = true;
        }

        $proc = proc_open(array_merge([$exe], $args), $descriptors, $pipes, $cwd, null, $options);
        if (!is_resource($proc)) {
            throw new \RuntimeException("启动 {$name} 失败：无法创建进程（{$exe}）");
        }
        $status = proc_get_status($proc);
        $pid = $status['pid'] ?? null;
        // 注意：不调用 proc_close()，否则会等待子进程退出
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
        if (self::WINDOWS) {
            exec('tasklist /FI "PID eq ' . $pid . '" /NH 2>NUL', $out, $exit);
            foreach ($out as $line) {
                if (str_contains($line, (string) $pid)) {
                    return true;
                }
            }
            return false;
        }
        // POSIX：kill -0 不发送信号，仅探测进程是否存在
        exec('kill -0 ' . $pid . ' 2>/dev/null', $out, $exit);
        return $exit === 0;
    }

    private function exeName(string $base): string
    {
        return self::WINDOWS ? $base . '.exe' : $base;
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
