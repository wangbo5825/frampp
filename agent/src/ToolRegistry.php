<?php

declare(strict_types=1);

namespace Frampp\Agent;

use ReflectionClass;
use ReflectionMethod;

/**
 * 通过 #[AsTool] 注解发现工具方法（与 php-mcp 属性注解风格一致，便于未来迁移）。
 */
final class ToolRegistry
{
    /** @var array<string,array{callable:callable,description:string,schema:array}> */
    private array $tools = [];

    public function __construct(private readonly AuditLogger $audit, private readonly AgentConfig $config)
    {
    }

    public function register(object $instance): void
    {
        $ref = new ReflectionClass($instance);
        foreach ($ref->getMethods(ReflectionMethod::IS_PUBLIC) as $method) {
            $attr = $method->getAttributes(AsTool::class)[0] ?? null;
            if ($attr === null) {
                continue;
            }
            $tool = $attr->newInstance();
            $this->tools[$tool->name] = [
                'callable'    => [$instance, $method->getName()],
                'description' => $tool->description,
                'schema'      => $tool->inputSchema,
            ];
        }
    }

    /** @return list<array{name:string,description:string,inputSchema:array}> */
    public function list(): array
    {
        $out = [];
        foreach ($this->tools as $name => $def) {
            $out[] = [
                'name'        => $name,
                'description' => $def['description'],
                'inputSchema' => $def['schema'],
            ];
        }
        ksort($out);
        return array_values($out);
    }

    public function call(string $name, array $arguments): array
    {
        if (!isset($this->tools[$name])) {
            return ['isError' => true, 'text' => "未知工具: $name"];
        }
        try {
            $result = ($this->tools[$name]['callable'])($arguments);
        } catch (\Throwable $e) {
            $result = ['isError' => true, 'text' => $e->getMessage()];
        }
        $this->audit->record($name, $arguments, $result);
        return $result;
    }
}
