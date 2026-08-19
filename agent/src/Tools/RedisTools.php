<?php

declare(strict_types=1);

namespace Frampp\Agent\Tools;

use Frampp\Agent\AgentConfig;
use Frampp\Agent\AsTool;
use Frampp\Agent\RespClient;

final class RedisTools
{
    private ?RespClient $client = null;

    public function __construct(private readonly AgentConfig $config)
    {
    }

    private function redis(): RespClient
    {
        return $this->client ??= new RespClient($this->config);
    }

    #[AsTool('redis.keys', '用 SCAN 扫描 key（只读）', [
        'type' => 'object',
        'properties' => [
            'pattern' => ['type' => 'string', 'description' => '匹配模式，默认 *'],
            'limit' => ['type' => 'integer', 'description' => '最多返回条数，默认 100'],
        ],
    ])]
    public function keys(array $args): array
    {
        $pattern = (string) ($args['pattern'] ?? '*');
        $limit = max(1, min(1000, (int) ($args['limit'] ?? 100)));
        $cursor = '0';
        $keys = [];
        do {
            [$next, $batch] = $this->redis()->command('SCAN', [$cursor, 'MATCH', $pattern, 'COUNT', '200']);
            $cursor = (string) $next;
            foreach ((array) $batch as $key) {
                $keys[] = (string) $key;
                if (count($keys) >= $limit) {
                    break 2;
                }
            }
        } while ($cursor !== '0' && count($keys) < $limit);
        return ['text' => json_encode(['count' => count($keys), 'keys' => $keys], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)];
    }

    #[AsTool('redis.get', '读取字符串值（只读）', [
        'type' => 'object',
        'properties' => ['key' => ['type' => 'string']],
        'required' => ['key'],
    ])]
    public function get(array $args): array
    {
        $key = (string) ($args['key'] ?? '');
        if ($key === '') {
            return ['isError' => true, 'text' => 'key 不能为空'];
        }
        $value = $this->redis()->command('GET', [$key]);
        return ['text' => json_encode(['key' => $key, 'value' => $value], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)];
    }

    #[AsTool('redis.ttl', '查看 key 剩余过期时间（只读）', [
        'type' => 'object',
        'properties' => ['key' => ['type' => 'string']],
        'required' => ['key'],
    ])]
    public function ttl(array $args): array
    {
        $key = (string) ($args['key'] ?? '');
        if ($key === '') {
            return ['isError' => true, 'text' => 'key 不能为空'];
        }
        return ['text' => json_encode(['key' => $key, 'ttl' => $this->redis()->command('TTL', [$key])])];
    }

    #[AsTool('redis.info', 'Redis 内存 / 统计信息（只读）', [
        'type' => 'object',
        'properties' => ['section' => ['type' => 'string', 'description' => '可选：Server/Clients/Memory/Persistence/Stats/Replication/Keyspace']],
    ])]
    public function info(array $args): array
    {
        $section = (string) ($args['section'] ?? 'default');
        if (!preg_match('/^[A-Za-z]+$/', $section)) {
            return ['isError' => true, 'text' => 'section 参数非法'];
        }
        $raw = (string) $this->redis()->command('INFO', [$section]);
        return ['text' => $raw];
    }
}
