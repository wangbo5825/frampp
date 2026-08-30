<?php

declare(strict_types=1);

namespace Frampp\Agent;

/**
 * 最小 RESP 客户端：仅支持只读命令白名单（GET/SCAN/TTL/INFO 等）。
 */
final class RespClient
{
    private const READ_COMMANDS = [
        'GET', 'MGET', 'SCAN', 'TTL', 'PTTL', 'INFO', 'DBSIZE', 'TYPE', 'EXISTS',
        'STRLEN', 'LLEN', 'SCARD', 'HLEN', 'ZCARD', 'HGET', 'HGETALL', 'LRANGE',
        'LINDEX', 'SMEMBERS', 'ZRANGE', 'ZSCORE', 'SRANDMEMBER', 'OBJECT',
    ];

    /** @var resource|null */
    private $stream = null;

    public function __construct(
        private readonly AgentConfig $config,
    ) {
    }

    public function command(string $name, array $args = []): mixed
    {
        $upper = strtoupper($name);
        if (!in_array($upper, self::READ_COMMANDS, true)) {
            throw new \InvalidArgumentException("Redis 命令不在只读白名单: $upper");
        }
        $this->connect();
        return $this->execute($upper, $args);
    }

    private function execute(string $upper, array $args): mixed
    {
        $payload = "*" . (count($args) + 1) . "\r\n";
        foreach (array_merge([$upper], $args) as $part) {
            $payload .= '$' . strlen((string) $part) . "\r\n" . $part . "\r\n";
        }
        fwrite($this->stream, $payload);
        return $this->readReply();
    }

    public function close(): void
    {
        if (is_resource($this->stream)) {
            fclose($this->stream);
        }
        $this->stream = null;
    }

    private function connect(): void
    {
        if (is_resource($this->stream)) {
            return;
        }
        if (!$this->config->runtimeReady()) {
            throw new \RuntimeException('FRAMPP 运行时不可用');
        }
        $pass = $this->config->secret('redis_password');
        if ($pass === null) {
            throw new \RuntimeException('缺少 Redis 密码（var/secrets.json 无 redis_password）');
        }
        $errno = 0;
        $errstr = '';
        $redisSock = $this->config->socket('redis');
        $target = $redisSock !== null
            ? 'unix://' . $redisSock
            : 'tcp://127.0.0.1:' . (int) ($this->config->runtime['ports']['redis'] ?? 6379);
        $stream = @stream_socket_client(
            $target,
            $errno,
            $errstr,
            3,
            STREAM_CLIENT_CONNECT
        );
        if ($stream === false) {
            throw new \RuntimeException("Redis 连接失败: $errstr");
        }
        $this->stream = $stream;
        $this->execute('AUTH', [$pass]);
    }

    private function readReply(): mixed
    {
        $line = fgets($this->stream);
        if ($line === false) {
            throw new \RuntimeException('Redis 连接已关闭');
        }
        $line = rtrim($line, "\r\n");
        if ($line === '') {
            return $this->readReply();
        }
        $prefix = $line[0];
        $data = substr($line, 1);
        return match ($prefix) {
            '+' => $data,
            '-' => throw new \RuntimeException("Redis 错误: $data"),
            ':' => (int) $data,
            '$' => $this->readBulk((int) $data),
            '*' => $this->readArray((int) $data),
            default => throw new \RuntimeException("未知 RESP 前缀: $prefix"),
        };
    }

    private function readBulk(int $length): ?string
    {
        if ($length === -1) {
            return null;
        }
        $data = '';
        while (strlen($data) < $length + 2) {
            $chunk = fread($this->stream, $length + 2 - strlen($data));
            if ($chunk === false || $chunk === '') {
                throw new \RuntimeException('Redis 读取中断');
            }
            $data .= $chunk;
        }
        return substr($data, 0, $length);
    }

    private function readArray(int $count): array
    {
        $out = [];
        for ($i = 0; $i < $count; $i++) {
            $out[] = $this->readReply();
        }
        return $out;
    }
}
