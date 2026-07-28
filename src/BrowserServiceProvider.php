<?php

namespace Sandip\Browser\Native;

use Illuminate\Support\ServiceProvider;
use Sandip\Browser\Native\Commands\CopyAssetsCommand;

class BrowserServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(Browser::class, fn () => new Browser);
    }

    public function boot(): void
    {
        if ($this->app->runningInConsole()) {
            $this->commands([
                CopyAssetsCommand::class,
            ]);
        }
    }
}
