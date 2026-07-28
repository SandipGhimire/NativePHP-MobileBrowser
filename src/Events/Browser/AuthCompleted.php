<?php

namespace Sandip\Browser\Native\Events\Browser;

use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class AuthCompleted
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public string $callbackUrl,
        public array $params = [],
        public ?string $id = null,
    ) {}
}
