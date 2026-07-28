<?php

namespace Sandip\Browser\Native;

class Browser
{
    public function open(string $url): PendingOpen
    {
        return new PendingOpen($url);
    }

    public function close(?string $id = null): bool
    {
        if (! function_exists('nativephp_call')) {
            return false;
        }

        $result = nativephp_call('MobileBrowser.Close', json_encode(['id' => $id]));

        if (! $result) {
            return false;
        }

        $decoded = json_decode($result, true);

        return ! (isset($decoded['status']) && $decoded['status'] === 'error');
    }
}
