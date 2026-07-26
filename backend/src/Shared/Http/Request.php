<?php
declare(strict_types=1);

namespace App\Shared\Http;

final class Request
{
    private array $jsonBody;
    private array $formBody;
    private array $files;

    /** @var array<string, mixed> */
    private array $attributes = [];

    public function __construct(
        private readonly string $method,
        private readonly string $path,
        private readonly array $query,
        private readonly array $headers,
        private readonly string $rawBody,
        array $formBody = [],
        array $files = []
    ) {
        $decoded = json_decode($this->rawBody, true);
        $this->jsonBody = is_array($decoded) ? $decoded : [];
        $this->formBody = $formBody;
        $this->files = $files;
    }

    public static function fromGlobals(): self
    {
        $uri = $_SERVER['REQUEST_URI'] ?? '/';
        $path = parse_url($uri, PHP_URL_PATH) ?: '/';
        $scriptName = $_SERVER['SCRIPT_NAME'] ?? '';
        if ($scriptName !== '' && str_starts_with($path, dirname($scriptName))) {
            $base = rtrim(str_replace('\\', '/', dirname($scriptName)), '/');
            if ($base !== '' && $base !== '.') {
                $path = substr($path, strlen($base));
                $path = $path !== '' ? $path : '/';
            }
        }

        $headers = [];
        foreach ($_SERVER as $key => $value) {
            if (str_starts_with($key, 'HTTP_')) {
                $name = str_replace('_', '-', strtolower(substr($key, 5)));
                $headers[$name] = (string)$value;
            }
        }

        if (isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
            $headers['authorization'] = (string)$_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
        } elseif (isset($_SERVER['Authorization'])) {
            $headers['authorization'] = (string)$_SERVER['Authorization'];
        }

        if (function_exists('getallheaders')) {
            foreach (getallheaders() as $name => $value) {
                $headers[strtolower((string)$name)] = (string)$value;
            }
        }

        return new self(
            strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET'),
            '/' . ltrim($path, '/'),
            $_GET,
            $headers,
            file_get_contents('php://input') ?: '',
            $_POST,
            $_FILES
        );
    }

    public function method(): string
    {
        return $this->method;
    }

    public function path(): string
    {
        return $this->path;
    }

    public function query(string $key, mixed $default = null): mixed
    {
        return $this->query[$key] ?? $default;
    }

    /** @return array<string, mixed> */
    public function queryParams(): array
    {
        return $this->query;
    }

    public function input(?string $key = null, mixed $default = null): mixed
    {
        $input = array_merge($this->formBody, $this->jsonBody);

        if ($key === null) {
            return $input;
        }

        return $input[$key] ?? $default;
    }

    /** @return array<string, mixed> */
    public function files(): array
    {
        return $this->files;
    }

    /** @return array<string, mixed>|null */
    public function file(string $key): ?array
    {
        $file = $this->files[$key] ?? null;
        return is_array($file) ? $file : null;
    }

    public function header(string $key, ?string $default = null): ?string
    {
        return $this->headers[strtolower($key)] ?? $default;
    }

    public function bearerToken(): ?string
    {
        $header = $this->header('authorization');
        if (!$header) {
            return null;
        }

        if (!preg_match('/Bearer\s+(.*)$/i', $header, $matches)) {
            return null;
        }

        return trim($matches[1]);
    }

    public function cookie(string $key, ?string $default = null): ?string
    {
        return isset($_COOKIE[$key]) ? (string)$_COOKIE[$key] : $default;
    }

    public function setAttribute(string $key, mixed $value): void
    {
        $this->attributes[$key] = $value;
    }

    public function attribute(string $key, mixed $default = null): mixed
    {
        return $this->attributes[$key] ?? $default;
    }
}
