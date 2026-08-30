<?php

declare(strict_types=1);

namespace Frampp\ControlPanel;

/**
 * Caddy admin API 客户端：支持 TCP（http://127.0.0.1:2019）与
 * unix socket（unix:///var/run/...）两种地址，供站点管理 / IP 访问控制热重载使用。
 */
final class CaddyAdminClient
{
    public function __construct(private readonly Config $config)
    {
    }

    /**
     * @return array{status:int,body:string}
     */
    public function post(string $path, string $body, string $contentType = 'application/json'): array
    {
        $address = $this->config->adminAddress();
        if (str_starts_with($address, 'unix://')) {
            return $this->unixPost(substr($address, 7), $path, $body, $contentType);
        }
        return $this->tcpPost($address, $path, $body, $contentType);
    }

    /**
     * @return array{status:int,body:string}
     */
    public function get(string $path): array
    {
        $address = $this->config->adminAddress();
        if (str_starts_with($address, 'unix://')) {
            return $this->unixRequest('GET', substr($address, 7), $path, '', '');
        }
        $ctx = stream_context_create([
            'http' => [
                'method'        => 'GET',
                'ignore_errors' => true,
                'timeout'       => 5,
            ],
        ]);
        $body = @file_get_contents($address . $path, false, $ctx);
        return ['status' => $this->lastStatus(), 'body' => (string) $body];
    }

    /** TCP 模式：与现有 file_get_contents 行为一致 */
    private function tcpPost(string $address, string $path, string $body, string $contentType): array
    {
        $ctx = stream_context_create([
            'http' => [
                'method'        => 'POST',
                'header'        => "Content-Type: $contentType\r\n",
                'content'       => $body,
                'ignore_errors' => true,
                'timeout'       => 5,
            ],
        ]);
        $resp = @file_get_contents($address . $path, false, $ctx);
        return ['status' => $this->lastStatus(), 'body' => (string) $resp];
    }

    /** unix socket 模式：手写 HTTP/1.1 请求 */
    private function unixPost(string $socket, string $path, string $body, string $contentType): array
    {
        return $this->unixRequest('POST', $socket, $path, $body, $contentType);
    }

    private function unixRequest(string $method, string $socket, string $path, string $body, string $contentType): array
    {
        $errno = 0;
        $errstr = '';
        $fp = @stream_socket_client('unix://' . $socket, $errno, $errstr, 5, STREAM_CLIENT_CONNECT);
        if ($fp === false) {
            return ['status' => 0, 'body' => "unix socket 连接失败: $errstr"];
        }
        $head = "$method $path HTTP/1.1\r\nHost: localhost\r\n";
        if ($body !== '') {
            $head .= "Content-Type: $contentType\r\nContent-Length: " . strlen($body) . "\r\n";
        }
        $head .= "Connection: close\r\n\r\n";
        fwrite($fp, $head . $body);

        $raw = '';
        while (!feof($fp)) {
            $chunk = fread($fp, 8192);
            if ($chunk === false) {
                break;
            }
            $raw .= $chunk;
        }
        fclose($fp);

        $status = 0;
        if (preg_match('#^HTTP/\S+\s+(\d+)#', $raw, $m)) {
            $status = (int) $m[1];
        }
        // 剥离响应头（简单解析：头部以 \r\n\r\n 结束）
        $bodyPart = $raw;
        if (($pos = strpos($raw, "\r\n\r\n")) !== false) {
            $bodyPart = substr($raw, $pos + 4);
        }
        return ['status' => $status, 'body' => trim($bodyPart)];
    }

    private function lastStatus(): int
    {
        $code = 0;
        foreach ($http_response_header ?? [] as $header) {
            if (preg_match('#^HTTP/\S+\s+(\d+)#', $header, $m)) {
                $code = (int) $m[1];
            }
        }
        return $code;
    }
}
