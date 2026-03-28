diff --git a/README.md b/README.md
index af9cd8ca138d5a05b58f51eb436be61583dd75c5..40ab346624782cc023fabeb5e2806a39726dc58d 100644
--- a/README.md
+++ b/README.md
@@ -1,2 +1,20 @@
 # lampac-ukraine
-gpt
+
+Документаційний репозиторій специфікацій для інтеграції з Lampac:
+
+- схема БД v1 (`docs/specs/db-mapping-v1.sql`)
+- контракт експорту (`docs/specs/lampac-export-contract-v1.md`)
+- OpenAPI (`docs/specs/openapi-lampac-v1.yaml`)
+- реєстр провайдерів (`docs/specs/provider-registry-v1.yaml`)
+- план міграції (`docs/specs/migration-plan-v1.md`)
+
+## Локальна перевірка специфікацій
+
+```bash
+bash scripts/validate-specs.sh
+```
+
+Що перевіряється:
+1. OpenAPI lint (`@redocly/cli`)
+2. Валідність YAML-спек (`provider-registry-v1.yaml`, `openapi-lampac-v1.yaml`)
+3. SQL dry-run міграції `db-mapping-v1.sql` на тимчасовій PostgreSQL БД
