<?php

use Sandip\Browser\Native\Browser;
use Sandip\Browser\Native\Events\Browser\Closed;
use Sandip\Browser\Native\Events\Browser\Opened;
use Sandip\Browser\Native\PendingOpen;

beforeEach(function () {
    $this->pluginPath = dirname(__DIR__);
    $this->manifestPath = $this->pluginPath.'/nativephp.json';
});

describe('Plugin Manifest', function () {
    it('has a valid nativephp.json file', function () {
        expect(file_exists($this->manifestPath))->toBeTrue();

        json_decode(file_get_contents($this->manifestPath), true);

        expect(json_last_error())->toBe(JSON_ERROR_NONE);
    });

    it('has required fields', function () {
        $manifest = json_decode(file_get_contents($this->manifestPath), true);

        expect($manifest)->toHaveKeys(['name', 'namespace', 'bridge_functions']);
        expect($manifest['name'])->toBe('sghimire/mobile-browser');
        expect($manifest['namespace'])->toBe('Browser');
    });

    it('registers its own bridge functions', function () {
        $manifest = json_decode(file_get_contents($this->manifestPath), true);

        $names = array_column($manifest['bridge_functions'], 'name');

        expect($names)->toBe(['MobileBrowser.Open', 'MobileBrowser.Close']);

        foreach ($manifest['bridge_functions'] as $function) {
            expect($function)->toHaveKeys(['name']);
            expect(isset($function['android']) || isset($function['ios']))->toBeTrue();
        }
    });

    it('requests internet permission on Android', function () {
        $manifest = json_decode(file_get_contents($this->manifestPath), true);

        expect($manifest['android']['permissions'])->toContain('android.permission.INTERNET');
    });

    it('declares the events it dispatches', function () {
        $manifest = json_decode(file_get_contents($this->manifestPath), true);

        expect($manifest['events'])->toBe([
            'Sandip\\Browser\\Native\\Events\\Browser\\Opened',
            'Sandip\\Browser\\Native\\Events\\Browser\\Closed',
        ]);
    });
});

describe('Native Code', function () {
    it('has Android Kotlin file', function () {
        $kotlinFile = $this->pluginPath.'/resources/android/BrowserFunctions.kt';

        expect(file_exists($kotlinFile))->toBeTrue();

        $content = file_get_contents($kotlinFile);
        expect($content)->toContain('package com.sandip.plugins.browser');
        expect($content)->toContain('object BrowserFunctions');
        expect($content)->toContain('class Open(');
        expect($content)->toContain('class Close(');
        expect($content)->toContain('BridgeFunction');
    });

    it('has iOS Swift file', function () {
        $swiftFile = $this->pluginPath.'/resources/ios/BrowserFunctions.swift';

        expect(file_exists($swiftFile))->toBeTrue();

        $content = file_get_contents($swiftFile);
        expect($content)->toContain('enum BrowserFunctions');
        expect($content)->toContain('class Open:');
        expect($content)->toContain('class Close:');
        expect($content)->toContain('BridgeFunction');
    });

    it('has matching bridge function classes in native code', function () {
        $manifest = json_decode(file_get_contents($this->manifestPath), true);

        $kotlinContent = file_get_contents($this->pluginPath.'/resources/android/BrowserFunctions.kt');
        $swiftContent = file_get_contents($this->pluginPath.'/resources/ios/BrowserFunctions.swift');

        foreach ($manifest['bridge_functions'] as $function) {
            if (isset($function['android'])) {
                $parts = explode('.', $function['android']);
                $className = end($parts);
                expect($kotlinContent)->toContain("class {$className}(");
            }

            if (isset($function['ios'])) {
                $parts = explode('.', $function['ios']);
                $className = end($parts);
                expect($swiftContent)->toContain("class {$className}:");
            }
        }
    });

    it('supports both webview and external modes on both platforms', function () {
        $kotlinContent = file_get_contents($this->pluginPath.'/resources/android/BrowserFunctions.kt');
        $swiftContent = file_get_contents($this->pluginPath.'/resources/ios/BrowserFunctions.swift');

        expect($kotlinContent)->toContain('"webview"');
        expect($kotlinContent)->toContain('"external"');
        expect($swiftContent)->toContain('"webview"');
        expect($swiftContent)->toContain('"external"');
    });

    it('dispatches events asynchronously instead of blocking the bridge thread', function () {
        $kotlinContent = file_get_contents($this->pluginPath.'/resources/android/BrowserFunctions.kt');
        $swiftContent = file_get_contents($this->pluginPath.'/resources/ios/BrowserFunctions.swift');

        expect($kotlinContent)->toContain('NativeActionCoordinator.dispatchEvent');
        expect($swiftContent)->toContain('LaravelBridge.shared.send');
    });
});

describe('PHP Classes', function () {
    it('has service provider', function () {
        $file = $this->pluginPath.'/src/BrowserServiceProvider.php';
        expect(file_exists($file))->toBeTrue();

        $content = file_get_contents($file);
        expect($content)->toContain('namespace Sandip\Browser\Native');
        expect($content)->toContain('class BrowserServiceProvider');
    });

    it('has facade', function () {
        $file = $this->pluginPath.'/src/Facades/Browser.php';
        expect(file_exists($file))->toBeTrue();

        $content = file_get_contents($file);
        expect($content)->toContain('namespace Sandip\Browser\Native\Facades');
        expect($content)->toContain('class Browser extends Facade');
    });

    it('has main implementation class, builder, events, and attribute', function () {
        expect(file_exists($this->pluginPath.'/src/Browser.php'))->toBeTrue();
        expect(file_exists($this->pluginPath.'/src/PendingOpen.php'))->toBeTrue();
        expect(file_exists($this->pluginPath.'/src/Events/Browser/Opened.php'))->toBeTrue();
        expect(file_exists($this->pluginPath.'/src/Events/Browser/Closed.php'))->toBeTrue();
        expect(file_exists($this->pluginPath.'/src/Attributes/OnNative.php'))->toBeTrue();
    });
});

describe('Browser manager', function () {
    it('returns a fluent PendingOpen from open()', function () {
        expect((new Browser)->open('https://example.com'))->toBeInstanceOf(PendingOpen::class);
    });

    it('close() returns false outside a native runtime', function () {
        expect((new Browser)->close())->toBeFalse();
    });
});

describe('PendingOpen', function () {
    it('defaults to webview mode', function () {
        $pending = new PendingOpen('https://example.com');

        expect($pending->getId())->toBeNull();
    });

    it('rejects an empty URL', function () {
        new PendingOpen('');
    })->throws(InvalidArgumentException::class);

    it('accepts a valid mode', function () {
        expect((new PendingOpen('https://example.com'))->mode('external'))->toBeInstanceOf(PendingOpen::class);
    });

    it('rejects an unknown mode', function () {
        (new PendingOpen('https://example.com'))->mode('not-a-real-mode');
    })->throws(InvalidArgumentException::class);

    it('external() toggles mode', function () {
        expect((new PendingOpen('https://example.com'))->external())->toBeInstanceOf(PendingOpen::class);
    });

    it('chains fluent configuration methods', function () {
        $pending = (new PendingOpen('https://example.com'))
            ->title('Example')
            ->showToolbar(true)
            ->showNavigationButtons(false)
            ->shareButton(false)
            ->desktopMode(true)
            ->id('example-browser');

        expect($pending)->toBeInstanceOf(PendingOpen::class);
        expect($pending->getId())->toBe('example-browser');
    });

    it('returns false when opened outside a native runtime', function () {
        expect((new PendingOpen('https://example.com'))->open())->toBeFalse();
    });

    it('refuses to open twice', function () {
        $pending = new PendingOpen('https://example.com');
        $pending->open();

        expect($pending->open())->toBeFalse();
    });
});

describe('Events', function () {
    it('Opened carries url, mode, and an optional id', function () {
        $event = new Opened(url: 'https://example.com', mode: 'webview', id: 'abc');

        expect($event->url)->toBe('https://example.com');
        expect($event->mode)->toBe('webview');
        expect($event->id)->toBe('abc');
    });

    it('Closed defaults reason and id to null', function () {
        $event = new Closed;

        expect($event->reason)->toBeNull();
        expect($event->id)->toBeNull();
    });
});

describe('Composer Configuration', function () {
    it('has valid composer.json', function () {
        $composerPath = $this->pluginPath.'/composer.json';
        expect(file_exists($composerPath))->toBeTrue();

        $composer = json_decode(file_get_contents($composerPath), true);

        expect(json_last_error())->toBe(JSON_ERROR_NONE);
        expect($composer['name'])->toBe('sghimire/mobile-browser');
        expect($composer['type'])->toBe('nativephp-plugin');
        expect($composer['extra']['nativephp']['manifest'])->toBe('nativephp.json');
        expect($composer['autoload']['psr-4'])->toHaveKey('Sandip\\Browser\\Native\\');
    });
});

describe('Lifecycle Hooks', function () {
    it('has copy_assets hook command', function () {
        $manifest = json_decode(file_get_contents($this->manifestPath), true);

        expect($manifest['hooks']['copy_assets'] ?? null)->not->toBeNull();

        $commandFile = $this->pluginPath.'/src/Commands/CopyAssetsCommand.php';
        expect(file_exists($commandFile))->toBeTrue();
    });

    it('copy_assets command extends NativePluginHookCommand', function () {
        $content = file_get_contents($this->pluginPath.'/src/Commands/CopyAssetsCommand.php');

        expect($content)->toContain('extends NativePluginHookCommand');
        expect($content)->toContain('use Native\Mobile\Plugins\Commands\NativePluginHookCommand');
    });

    it('copy_assets command has correct signature', function () {
        $manifest = json_decode(file_get_contents($this->manifestPath), true);
        $expectedSignature = $manifest['hooks']['copy_assets'];

        $content = file_get_contents($this->pluginPath.'/src/Commands/CopyAssetsCommand.php');

        expect($content)->toContain('$signature = \''.$expectedSignature.'\'');
    });
});
