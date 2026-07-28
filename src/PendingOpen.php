<?php

namespace Sandip\Browser\Native;

use InvalidArgumentException;

class PendingOpen
{
    public const MODES = ['webview', 'external'];

    protected string $url;

    protected ?string $id = null;

    protected string $mode = 'webview';

    protected ?string $title = null;

    protected bool $showToolbar = true;

    protected bool $showNavigationButtons = true;

    protected bool $shareButton = true;

    protected bool $desktopMode = false;

    protected bool $started = false;

    public function __construct(string $url)
    {
        if (trim($url) === '') {
            throw new InvalidArgumentException('A URL must be provided.');
        }

        $this->url = $url;
    }

    public function mode(string $mode): self
    {
        if (! in_array($mode, self::MODES, true)) {
            throw new InvalidArgumentException(sprintf(
                'Invalid browser mode: %s. Valid modes are: %s.',
                $mode,
                implode(', ', self::MODES)
            ));
        }

        $this->mode = $mode;

        return $this;
    }

    public function external(bool $external = true): self
    {
        return $this->mode($external ? 'external' : 'webview');
    }

    public function title(string $title): self
    {
        $this->title = $title;

        return $this;
    }

    public function showToolbar(bool $enabled = true): self
    {
        $this->showToolbar = $enabled;

        return $this;
    }

    public function showNavigationButtons(bool $enabled = true): self
    {
        $this->showNavigationButtons = $enabled;

        return $this;
    }

    public function shareButton(bool $enabled = true): self
    {
        $this->shareButton = $enabled;

        return $this;
    }

    public function desktopMode(bool $enabled = true): self
    {
        $this->desktopMode = $enabled;

        return $this;
    }

    public function id(string $id): self
    {
        $this->id = $id;

        return $this;
    }

    public function getId(): ?string
    {
        return $this->id;
    }

    public function open(): bool
    {
        if ($this->started) {
            return false;
        }

        $this->started = true;

        if (! function_exists('nativephp_call')) {
            return false;
        }

        $result = nativephp_call('MobileBrowser.Open', json_encode([
            'url' => $this->url,
            'mode' => $this->mode,
            'title' => $this->title,
            'showToolbar' => $this->showToolbar,
            'showNavigationButtons' => $this->showNavigationButtons,
            'shareButton' => $this->shareButton,
            'desktopMode' => $this->desktopMode,
            'id' => $this->id,
        ]));

        if (! $result) {
            return false;
        }

        $decoded = json_decode($result, true);

        return ! (isset($decoded['status']) && $decoded['status'] === 'error');
    }

    public function __destruct()
    {
        if (! $this->started) {
            $this->open();
        }
    }
}
