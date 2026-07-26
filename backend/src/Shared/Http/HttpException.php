<?php
declare(strict_types=1);

namespace App\Shared\Http;

use RuntimeException;

final class HttpException extends RuntimeException
{
    public function __construct(string $message, private readonly int $status = 400)
    {
        parent::__construct($message);
    }

    public function status(): int
    {
        return $this->status;
    }
}