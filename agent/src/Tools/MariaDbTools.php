<?php

declare(strict_types=1);

namespace Frampp\Agent\Tools;

use Frampp\Agent\AgentConfig;
use Frampp\Agent\AsTool;
use Frampp\Agent\QueryGuard;
use PDO;

final class MariaDbTools
{
    private ?PDO $pdo = null;

    public function __construct(private readonly AgentConfig $config)
    {
    }

    private function pdo(): PDO
    {
        if ($this->pdo === null) {
            if (!$this->config->runtimeReady()) {
                throw new \RuntimeException('FRAMPP 运行时不可用（未找到 runtime.json）');
            }
            $port = (int) ($this->config->runtime['ports']['mysql'] ?? 3306);
            $user = 'frampp_ro';
            $pass = $this->config->secret('mariadb_readonly_password');
            if ($pass === null) {
                throw new \RuntimeException('缺少只读账号密码（var/secrets.json 无 mariadb_readonly_password）');
            }
            $this->pdo = new PDO(
                "mysql:host=127.0.0.1;port=$port;charset=utf8mb4",
                $user,
                $pass,
                [PDO::ATTR_TIMEOUT => 3, PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
            );
        }
        return $this->pdo;
    }

    #[AsTool('mysql.list_tables', '列出数据库中所有用户表', [
        'type' => 'object',
        'properties' => ['schema' => ['type' => 'string', 'description' => '可选：限定数据库名']],
    ])]
    public function listTables(array $args): array
    {
        $schema = trim((string) ($args['schema'] ?? ''));
        $sql = "SELECT table_schema AS schema_name, table_name, table_rows
                FROM information_schema.tables
                WHERE table_type = 'BASE TABLE' AND table_schema NOT IN
                    ('mysql', 'information_schema', 'performance_schema', 'sys')
                ORDER BY table_schema, table_name";
        $stmt = $this->pdo()->query($sql);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        if ($schema !== '') {
            $rows = array_values(array_filter($rows, static fn (array $r): bool => $r['schema_name'] === $schema));
        }
        return ['text' => json_encode($rows, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)];
    }

    #[AsTool('mysql.describe', '查看表结构（SHOW COLUMNS）', [
        'type' => 'object',
        'properties' => [
            'table' => ['type' => 'string'],
            'schema' => ['type' => 'string', 'description' => '可选：数据库名'],
        ],
        'required' => ['table'],
    ])]
    public function describe(array $args): array
    {
        $table = trim((string) ($args['table'] ?? ''));
        if ($table === '' || !preg_match('/^[A-Za-z0-9_$-]+$/', $table)) {
            return ['isError' => true, 'text' => '表名非法'];
        }
        $schema = trim((string) ($args['schema'] ?? ''));
        $quoted = "`" . str_replace('`', '``', $table) . "`";
        $sql = $schema !== ''
            ? "SHOW COLUMNS FROM `" . str_replace('`', '``', $schema) . "`.$quoted"
            : "SHOW COLUMNS FROM $quoted";
        $rows = $this->pdo()->query(QueryGuard::guard($sql, 1000))->fetchAll(PDO::FETCH_ASSOC);
        return ['text' => json_encode($rows, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)];
    }

    #[AsTool('mysql.query', '执行只读查询（自动加 LIMIT）', [
        'type' => 'object',
        'properties' => [
            'sql' => ['type' => 'string'],
            'max_rows' => ['type' => 'integer', 'description' => '可选：覆盖默认行数上限'],
        ],
        'required' => ['sql'],
    ])]
    public function query(array $args): array
    {
        $sql = QueryGuard::guard(
            (string) ($args['sql'] ?? ''),
            max(1, min(1000, (int) ($args['max_rows'] ?? $this->config->int('query_max_rows', 200))))
        );
        $stmt = $this->pdo()->query($sql);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        return ['text' => json_encode($rows, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)];
    }
}
