<?php

declare(strict_types=1);

namespace Frampp\Agent;

#[\Attribute(\Attribute::TARGET_METHOD)]
final class AsTool
{
    public function __construct(
        public readonly string $name,
        public readonly string $description = '',
        public readonly array $inputSchema = [],
    ) {
    }
}
