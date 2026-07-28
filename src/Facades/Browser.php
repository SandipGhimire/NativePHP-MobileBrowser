<?php

namespace Sandip\Browser\Native\Facades;

use Illuminate\Support\Facades\Facade;

class Browser extends Facade
{
    protected static function getFacadeAccessor(): string
    {
        return \Sandip\Browser\Native\Browser::class;
    }
}
