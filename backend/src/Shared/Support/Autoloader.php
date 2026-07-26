<?php
declare(strict_types=1);

namespace App\Shared\Support;

final class Autoloader
{
    public static function register(string $rootPath): void
    {
        spl_autoload_register(static function (string $class) use ($rootPath): void {
            $prefix = 'App\\';
            if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
                return;
            }

            $relative = substr($class, strlen($prefix));
            $file = $rootPath . '/src/' . str_replace('\\', '/', $relative) . '.php';

            if (is_file($file)) {
                require_once $file;
            }
        });
    }
}