<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class AppSettingRepository extends PdoCrudRepository
{
    protected string $table = 'app_settings';
    protected array $fillable = ['setting_key', 'setting_value'];
    protected array $filterable = ['setting_key'];
}