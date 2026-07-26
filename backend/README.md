# Backend API (Clean Architecture)

## Dossiers

- `public/index.php`: entree unique HTTP + routing v1.
- `src/Domain`: contrats metier.
- `src/Application`: services/use-cases.
- `src/Infrastructure`: repositories PDO.
- `src/Presentation`: controllers/middlewares.
- `src/Shared`: autoload, HTTP, DB, securite.
- `bin`: scripts CLI migration/seed.

## Execution locale

```bash
php -S localhost:8080 -t backend/public
```

## Qualite

Validation syntaxe PHP:

```bash
php -l backend/public/index.php
```

Validation complete du projet:

```bash
# PowerShell
Get-ChildItem -Recurse -File backend,frontend | ? Extension -eq '.php' | % { php -l $_.FullName }
```
