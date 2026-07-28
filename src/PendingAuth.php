<?php

namespace Sandip\Browser\Native;

use InvalidArgumentException;

class PendingAuth
{
    public const REDIRECT_SCHEME = 'nativephp';

    protected string $authorizeUrl;

    protected string $redirectUri;

    protected ?string $id = null;

    protected bool $ephemeral = true;

    protected bool $started = false;

    public function __construct(string $authorizeUrl, string $redirectUri)
    {
        if (trim($authorizeUrl) === '') {
            throw new InvalidArgumentException('An authorize URL must be provided.');
        }

        $scheme = parse_url($redirectUri, PHP_URL_SCHEME);

        if (! $scheme) {
            throw new InvalidArgumentException(
                'A redirectUri with a scheme must be provided, e.g. nativephp://127.0.0.1/auth/callback.'
            );
        }

        if ($scheme !== self::REDIRECT_SCHEME) {
            throw new InvalidArgumentException(sprintf(
                'redirectUri must use the "%s://" scheme so the OAuth callback can be routed back into the app, e.g. %s://127.0.0.1/auth/callback.',
                self::REDIRECT_SCHEME,
                self::REDIRECT_SCHEME
            ));
        }

        $this->authorizeUrl = $authorizeUrl;
        $this->redirectUri = $redirectUri;
    }

    public function ephemeral(bool $enabled = true): self
    {
        $this->ephemeral = $enabled;

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

    public function auth(): bool
    {
        if ($this->started) {
            return false;
        }

        $this->started = true;

        if (! function_exists('nativephp_call')) {
            return false;
        }

        $result = nativephp_call('MobileBrowser.Auth', json_encode([
            'url' => $this->authorizeUrl,
            'redirectUri' => $this->redirectUri,
            'ephemeral' => $this->ephemeral,
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
            $this->auth();
        }
    }
}
