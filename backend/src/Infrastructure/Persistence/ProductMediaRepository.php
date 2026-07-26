<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class ProductMediaRepository extends PdoCrudRepository
{
    protected string $table = 'product_media';
    protected array $fillable = ['product_id', 'media_type', 'file_name', 'file_path', 'mime_type', 'uploaded_by'];
    protected array $filterable = ['product_id', 'media_type'];
}