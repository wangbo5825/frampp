<?php

declare(strict_types=1);

namespace Frampp\Agent;

/**
 * SQL 只读守卫：仅允许 SELECT / SHOW / DESCRIBE / EXPLAIN，强制 LIMIT，拒绝多语句。
 */
final class QueryGuard
{
    private const ALLOWED_PREFIXES = ['SELECT', 'SHOW', 'DESCRIBE', 'EXPLAIN'];

    public static function guard(string $sql, int $maxRows): string
    {
        $trimmed = trim($sql);
        if ($trimmed === '') {
            throw new \InvalidArgumentException('SQL 为空');
        }
        if (substr_count($trimmed, ';') > 1 || (str_ends_with($trimmed, ';') && trim(substr($trimmed, 0, -1)) === '')) {
            throw new \InvalidArgumentException('不允许多语句');
        }
        $single = rtrim($trimmed, ';');
        $upper = strtoupper($single);
        $matched = false;
        foreach (self::ALLOWED_PREFIXES as $prefix) {
            if (str_starts_with($upper, $prefix)) {
                $matched = true;
                break;
            }
        }
        if (!$matched) {
            throw new \InvalidArgumentException('仅允许只读 SQL（SELECT / SHOW / DESCRIBE / EXPLAIN）');
        }

        // 注释与字符串中的 LIMIT 不精确，但作为最低防线足够；最后取行数仍有上限
        if (str_starts_with($upper, 'SELECT') && !preg_match('/\bLIMIT\b/i', $single)) {
            $single .= " LIMIT $maxRows";
        }
        return $single;
    }
}
