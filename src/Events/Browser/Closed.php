<?php

namespace Sandip\Browser\Native\Events\Browser;

use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class Closed
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public ?string $reason = null,
        public ?string $id = null,
    ) {}
}
