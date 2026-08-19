<?php

declare(strict_types=1);

namespace Frampp\Agent;

/**
 * MCP stdio 服务器：基于 JSON-RPC 2.0 新行分隔消息。
 *
 * 支持方法：initialize / notifications/initialized / ping / tools/list / tools/call。
 * 安全：仅从 stdin 读取、向 stdout 输出；绑定由调用方（本地进程）保证。
 */
final class Server
{
    public const VERSION = '0.1.0';

    public function __construct(
        private readonly AgentConfig $config,
        private readonly ToolRegistry $registry,
    ) {
    }

    public function run(): int
    {
        $input = fopen('php://stdin', 'rb');
        $output = fopen('php://stdout', 'wb');
        if ($input === false || $output === false) {
            return 1;
        }

        while (($line = fgets($input)) !== false) {
            $line = trim($line);
            if ($line === '') {
                continue;
            }
            $request = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
            $response = $this->handle($request);
            if ($response !== null) {
                fwrite($output, json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n");
                fflush($output);
            }
        }
        fclose($input);
        fclose($output);
        return 0;
    }

    /** @return array<string,mixed>|null */
    private function handle(array $request): ?array
    {
        $id = $request['id'] ?? null;
        $method = $request['method'] ?? '';
        $params = $request['params'] ?? [];

        if (str_starts_with($method, 'notifications/')) {
            return null;
        }

        try {
            $result = match ($method) {
                'initialize' => [
                    'protocolVersion' => $params['protocolVersion'] ?? '2025-03-26',
                    'capabilities'    => ['tools' => ['listChanged' => false]],
                    'serverInfo'      => ['name' => 'frampp-agent', 'version' => self::VERSION],
                ],
                'ping'       => new \stdClass(),
                'tools/list' => ['tools' => $this->registry->list()],
                'tools/call' => $this->toToolResult($this->registry->call(
                    (string) ($params['name'] ?? ''),
                    (array) ($params['arguments'] ?? [])
                )),
                default      => throw new \RuntimeException("未知方法: $method"),
            };
            return ['jsonrpc' => '2.0', 'id' => $id, 'result' => $result];
        } catch (\Throwable $e) {
            return [
                'jsonrpc' => '2.0',
                'id'      => $id,
                'error'   => ['code' => -32601, 'message' => $e->getMessage()],
            ];
        }
    }

    /** @return array{content:list<array{type:string,text:string}>,isError:bool} */
    private function toToolResult(array $result): array
    {
        return [
            'content' => [['type' => 'text', 'text' => (string) ($result['text'] ?? '')]],
            'isError' => (bool) ($result['isError'] ?? false),
        ];
    }
}
