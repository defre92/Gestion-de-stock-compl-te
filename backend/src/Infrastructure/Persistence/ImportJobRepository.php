<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class ImportJobRepository extends PdoCrudRepository
{
    protected string $table = 'import_jobs';
    protected array $fillable = [
        'entity_type',
        'file_name',
        'status',
        'total_rows',
        'success_rows',
        'failed_rows',
        'error_log',
        'started_by',
    ];
    protected array $filterable = ['entity_type', 'status', 'started_by'];
}
