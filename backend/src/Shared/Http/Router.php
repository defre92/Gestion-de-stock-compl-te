<?php
declare(strict_types=1);

namespace App\Shared\Http;

final class Router
{
    /** @var array<int, array{method:string,pattern:string,regex:string,handler:callable,middlewares:array<int, callable>}> */
    private array $routes = [];

    public function add(string $method, string $pattern, callable $handler, array $middlewares = []): void
    {
        $regex = preg_replace('#\{([a-zA-Z_][a-zA-Z0-9_]*)\}#', '(?P<$1>[^/]+)', $pattern);
        $regex = '#^' . $regex . '$#';

        $this->routes[] = [
            'method' => strtoupper($method),
            'pattern' => $pattern,
            'regex' => $regex,
            'handler' => $handler,
            'middlewares' => $middlewares,
        ];
    }

    public function dispatch(Request $request): void
    {
        foreach ($this->routes as $route) {
            if ($route['method'] !== $request->method()) {
                continue;
            }

            if (!preg_match($route['regex'], $request->path(), $matches)) {
                continue;
            }

            $params = [];
            foreach ($matches as $key => $value) {
                if (!is_int($key)) {
                    $params[$key] = $value;
                }
            }

            $next = static fn (Request $req, array $par) => ($route['handler'])($req, $par);

            foreach (array_reverse($route['middlewares']) as $middleware) {
                $currentNext = $next;
                $next = static fn (Request $req, array $par) => $middleware($req, $par, $currentNext);
            }

            $next($request, $params);
            return;
        }

        throw new HttpException('Route not found', 404);
    }
}