<?php

namespace Sandip\Browser\Native\Events\Browser;

use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class Opened
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public string $url,
        public string $mode,
        public ?string $id = null,
    ) {}
}
