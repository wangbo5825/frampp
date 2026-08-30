<?php

declare(strict_types=1);

namespace Frampp\ControlPanel;

require_once __DIR__ . '/AccessManager.php';

/**
 * 服务管理：FrankenPHP / MariaDB / Redis 的启停、状态、端口与日志。
 *
 * 安全基线：
 *   - 所有服务仅绑定 127.0.0.1；
 *   - Web 端变更操作必须携带 var/secrets.json 中的 panel_token；
 *   - 进程 PID 写入 var/*.pid，由控制面板统一管理。
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
     * @return array<string,array{name:string,running:bool,pid:?int,port:?int,port_open:bool,orphan:bool,error:?string}>
     */
    public function status(?string $only = null): array
    {
        $result = [];
        foreach (self::SERVICES as $name => $meta) {
            if ($only !== null && $only !== $name) {
                continue;
            }
            $metaInfo = $this->pidMeta($name);
            $pid = $metaInfo['pid'] ?? null;
            $port = $this->config->port($meta['port']);
            $alive = $pid !== null && $this->isProcessAlive($pid);
            $result[$name] = [
                'name'      => $name,
                'running'   => $alive,
                'pid'       => $pid,
                'port'      => $port,
                'port_open' => $this->isPortOpen('127.0.0.1', $port),
                'orphan'    => $alive && $this->isOrphan($metaInfo),
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
            $launcherType = getenv('FRAMPP_DAEMON') === '1' ? 'daemon' : 'cli';
            $this->writePidMeta($name, $pid, $launcherType);
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

        // 先优雅终止进程树，超时再强杀
        $this->killProcessTree($pid, false);
        for ($i = 0; $i < 20; $i++) {
            if (!$this->isProcessAlive($pid)) {
                break;
            }
            usleep(250_000);
        }
        if ($this->isProcessAlive($pid)) {
            $this->killProcessTree($pid, true);
        }
        $this->removePid($name);
        return ['name' => $name, 'stopped' => true];
    }

    /**
     * 清理孤儿服务：daemon（framppd）启动且启动者已退出的残留进程，
     * 按进程树终止并删除 PID 文件。
     *
     * @return array{cleaned:list<string>,skipped:list<string>}
     */
    public function cleanupOrphans(): array
    {
        $cleaned = [];
        $skipped = [];
        foreach (self::SERVICES as $name => $meta) {
            $info = $this->pidMeta($name);
            $pid = $info['pid'] ?? null;
            if ($pid === null) {
                continue;
            }
            if (!$this->isProcessAlive($pid)) {
                // 进程已不存在，仅清理过期 PID 文件
                $this->removePid($name);
                $skipped[] = $name;
                continue;
            }
            if ($this->isOrphan($info)) {
                $this->killProcessTree($pid, true);
                $this->removePid($name);
                $cleaned[] = $name;
            }
        }
        return ['cleaned' => $cleaned, 'skipped' => $skipped];
    }

    /**
     * 切换内部传输模式：'tcp'（默认，127.0.0.1 端口）<-> 'sock'（unix socket，仅 Linux）。
     *
     * sock 模式下 Caddy admin / MariaDB / Redis 均使用 var/run/*.sock，
     * 对外站点端口（8080/8081）不受影响，仍在 Caddyfile 中配置。
     *
     * @return array{mode:string,changed:bool,message:string,restart:array<string,bool>}
     */
    public function switchMode(string $target): array
    {
        $target = $target === 'sock' ? 'sock' : 'tcp';
        if ($target === 'sock' && self::WINDOWS) {
            throw new \InvalidArgumentException('unix socket 模式仅 Linux 支持（Windows 请保持 TCP）');
        }
        $current = $this->config->mode();
        if ($current === $target) {
            return ['mode' => $target, 'changed' => false, 'message' => "已处于 {$target} 模式"];
        }

        // 1. 停止服务（先数据服务再 Web 服务器）
        foreach (['mariadb', 'redis', 'frankenphp'] as $svc) {
            try {
                $this->stop($svc);
            } catch (\Throwable) {
                // 未运行或停止失败不阻塞切换
            }
        }

        // 2. 更新 runtime.json（mode + sockets）
        $runtimeFile = $this->config->varDir('runtime.json');
        $runtime = is_file($runtimeFile)
            ? json_decode((string) file_get_contents($runtimeFile), true)
            : $this->config->runtime;
        if (!is_array($runtime)) {
            $runtime = $this->config->runtime;
        }
        if ($target === 'sock') {
            $runDir = $this->config->varDir('run');
            if (!is_dir($runDir)) {
                mkdir($runDir, 0777, true);
            }
            $runtime['mode'] = 'sock';
            $runtime['sockets'] = [
                'admin' => $runDir . DIRECTORY_SEPARATOR . 'admin.sock',
                'mysql' => $runDir . DIRECTORY_SEPARATOR . 'mysql.sock',
                'redis' => $runDir . DIRECTORY_SEPARATOR . 'redis.sock',
            ];
        } else {
            $runtime['mode'] = 'tcp';
            unset($runtime['sockets']);
        }
        file_put_contents(
            $runtimeFile,
            json_encode($runtime, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL
        );

        // 3. 重新加载配置并重生成 Caddyfile / redis.conf / php.ini
        $config = Config::discover($this->config->root);
        $access = new AccessManager($config);
        $access->renderCaddyfile();
        $this->renderRedisConf($config);
        $this->renderPhpIni($config);

        // 4. 启动服务
        $restart = [];
        $errors = [];
        $mgr = new self($config);
        foreach (['mariadb', 'redis', 'frankenphp'] as $svc) {
            try {
                $result = $mgr->start($svc);
                $restart[$svc] = (bool) ($result['started'] ?? false);
            } catch (\Throwable $e) {
                $restart[$svc] = false;
                $errors[] = "{$svc}: " . $e->getMessage();
            }
        }

        $message = "已切换到 {$target} 模式";
        if (!empty($errors)) {
            $message .= '；部分服务启动失败：' . implode('; ', $errors);
        }
        return [
            'mode'    => $target,
            'changed' => true,
            'message' => $message,
            'restart' => $restart,
        ];
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
        $exe = $this->config->module('frankenphp') . DIRECTORY_SEPARATOR . $this->exeName('frankenphp');
        if (!is_file($exe)) {
            throw new \RuntimeException("缺少 FrankenPHP 可执行文件: $exe");
        }
        $args = ['run', '--config', $this->config->etcDir('Caddyfile')];
        return $this->startDetached($exe, $args, $this->config->root, 'frankenphp');
    }

    private function startMariadb(): ?int
    {
        $exe = $this->config->module('mariadb') . DIRECTORY_SEPARATOR . 'bin' . DIRECTORY_SEPARATOR . $this->exeName('mariadbd');
        if (!is_file($exe)) {
            throw new \RuntimeException("缺少 MariaDB 可执行文件: $exe");
        }
        $datadir = $this->config->varDir('mariadb');
        $log = $this->config->logsDir() . DIRECTORY_SEPARATOR . 'mariadb.log';
        $args = [
            '--no-defaults',
            '--datadir=' . $datadir,
            '--port=' . $this->config->port('mysql'),
            '--bind-address=127.0.0.1',
        ];
        $mysqlSock = $this->config->socket('mysql');
        if ($mysqlSock !== null) {
            // unix socket 模式：禁用 TCP 监听，仅本机 socket（避免端口冲突）
            $args[] = '--skip-networking';
            $args[] = '--socket=' . $mysqlSock;
        }
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
        $exe = $this->config->module('redis') . DIRECTORY_SEPARATOR . $this->exeName('redis-server');
        if (!is_file($exe)) {
            throw new \RuntimeException("缺少 Redis 可执行文件: $exe");
        }
        // 配置统一在 etc/ 下，直接以该目录为工作目录加载 redis.conf
        $redisCwd = $this->config->etcDir();
        if (!is_dir($this->config->varDir('redis'))) {
            mkdir($this->config->varDir('redis'), 0777, true);
        }
        return $this->startDetached($exe, ['redis.conf'], $redisCwd, 'redis');
    }

    /** 按当前模式重生成 redis.conf（unix socket 模式含 unixsocket 指令） */
    private function renderRedisConf(Config $config): void
    {
        $template = $config->root . DIRECTORY_SEPARATOR . 'installer' . DIRECTORY_SEPARATOR . 'templates'
            . DIRECTORY_SEPARATOR . 'redis.conf.template';
        if (!is_file($template)) {
            throw new \RuntimeException("缺少 redis.conf 模板: {$template}");
        }
        $content = (string) file_get_contents($template);
        $mysqlSock = $config->socket('mysql');
        $redisSock = $config->socket('redis');
        $unixSocketConf = $redisSock !== null
            ? "unixsocket $redisSock\nunixsocketperm 700"
            : '# unix socket disabled (tcp mode)';
        $replace = [
            '{{REDIS_PASSWORD}}' => (string) ($config->secret('redis_password') ?? ''),
            '{{DATA_DIR}}'       => str_replace('\\', '/', $config->varDir('redis')),
            '{{LOG_FILE}}'       => str_replace('\\', '/', $config->logsDir() . DIRECTORY_SEPARATOR . 'redis.log'),
            '{{UNIX_SOCKET_CONF}}' => $unixSocketConf,
        ];
        file_put_contents($config->etcDir('redis.conf'), str_replace(array_keys($replace), array_values($replace), $content));
    }

    /** 按当前模式重生成 php.ini（unix socket 模式下 mysqli/pdo_mysql 默认走 socket） */
    private function renderPhpIni(Config $config): void
    {
        $template = $config->root . DIRECTORY_SEPARATOR . 'installer' . DIRECTORY_SEPARATOR . 'templates'
            . DIRECTORY_SEPARATOR . 'php.ini.linux.template';
        if (!is_file($template)) {
            return; // Windows 无 linux 模板，保持原样
        }
        $content = (string) file_get_contents($template);
        $content = str_replace('{{MYSQL_SOCKET}}', (string) ($config->socket('mysql') ?? ''), $content);
        file_put_contents($config->etcDir('php.ini'), $content);
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
        return $this->pidMeta($name)['pid'] ?? null;
    }

    /**
     * 读取 PID 元数据。兼容旧格式（纯整数 PID）。
     *
     * @return array{pid:?int,launcher_pid:?int,launcher_type:string,started_at:?string}
     */
    private function pidMeta(string $name): array
    {
        $file = $this->config->varDir($name . '.pid');
        if (!is_file($file)) {
            return ['pid' => null, 'launcher_pid' => null, 'launcher_type' => 'cli', 'started_at' => null];
        }
        $raw = trim((string) file_get_contents($file));
        $data = json_decode($raw, true);
        if (is_array($data) && isset($data['pid'])) {
            return [
                'pid'           => (int) $data['pid'],
                'launcher_pid'  => isset($data['launcher_pid']) ? (int) $data['launcher_pid'] : null,
                'launcher_type' => (string) ($data['launcher_type'] ?? 'cli'),
                'started_at'    => isset($data['started_at']) ? (string) $data['started_at'] : null,
            ];
        }
        // 旧格式：纯整数 PID
        $pid = (int) $raw;
        return [
            'pid'           => $pid > 0 ? $pid : null,
            'launcher_pid'  => null,
            'launcher_type' => 'cli',
            'started_at'    => null,
        ];
    }

    /**
     * @param array{pid:?int,launcher_pid:?int,launcher_type:string,started_at:?string} $meta
     */
    private function isOrphan(array $meta): bool
    {
        if (($meta['launcher_type'] ?? 'cli') !== 'daemon') {
            return false;
        }
        $launcher = $meta['launcher_pid'] ?? null;
        if ($launcher === null || $launcher <= 0) {
            return false;
        }
        // 启动者（framppd）已退出，而服务进程仍然存活 => 残留孤儿
        return !$this->isProcessAlive($launcher);
    }

    private function writePidMeta(string $name, int $pid, string $launcherType): void
    {
        $meta = [
            'pid'           => $pid,
            'launcher_pid'  => $launcherType === 'daemon' ? $this->parentPid() : null,
            'launcher_type' => $launcherType,
            'started_at'    => date(DATE_ATOM),
        ];
        file_put_contents(
            $this->config->varDir($name . '.pid'),
            json_encode($meta, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL
        );
    }

    private function removePid(string $name): void
    {
        $file = $this->config->varDir($name . '.pid');
        if (is_file($file)) {
            @unlink($file);
        }
    }

    private function isProcessAlive(int $pid): bool
    {
        if ($pid <= 0) {
            return false;
        }
        if (self::WINDOWS) {
            // tasklist /FI 在某些权限环境（如受限沙盒）会被拒绝，改用 Get-Process
            exec(
                'powershell -NoProfile -Command "if (Get-Process -Id ' . $pid . ' -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" 2>NUL',
                $out,
                $exit
            );
            return $exit === 0;
        }
        // POSIX：kill -0 不发送信号，仅探测进程是否存在
        exec('kill -0 ' . $pid . ' 2>/dev/null', $out, $exit);
        return $exit === 0;
    }

    /** 当前进程（PHP CLI）的父进程 PID，用于 daemon 启动归因 */
    private function parentPid(): ?int
    {
        if (self::WINDOWS) {
            return null;
        }
        exec('ps -o ppid= -p ' . getmypid() . ' 2>/dev/null', $out, $exit);
        $ppid = (int) trim(implode('', $out));
        return $ppid > 0 ? $ppid : null;
    }

    /**
     * 终止进程树：先后代后根，Windows 用 taskkill /T，Linux 递归收集后代。
     */
    private function killProcessTree(int $pid, bool $force): void
    {
        if (self::WINDOWS) {
            exec('taskkill /PID ' . (int) $pid . ($force ? ' /T /F' : ' /T') . ' 2>NUL');
            return;
        }
        $tree = [$pid];
        $this->collectDescendants($pid, $tree);
        // 从最深的后代开始终止，最后终止根进程
        foreach (array_reverse($tree) as $p) {
            exec('kill ' . ($force ? '-9 ' : '') . (int) $p . ' 2>/dev/null');
        }
    }

    /**
     * 递归收集子进程 PID（Linux：ps --ppid）。
     *
     * @param list<int> $result
     */
    private function collectDescendants(int $pid, array &$result): void
    {
        exec('ps -o pid= --ppid ' . (int) $pid . ' 2>/dev/null', $out);
        foreach ($out as $line) {
            $child = (int) trim($line);
            if ($child > 0 && !in_array($child, $result, true)) {
                $result[] = $child;
                $this->collectDescendants($child, $result);
            }
        }
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
