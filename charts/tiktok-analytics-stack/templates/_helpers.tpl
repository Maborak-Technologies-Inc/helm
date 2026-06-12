{{/*
Expand the name of the chart.
*/}}
{{- define "tiktok-analytics-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "tiktok-analytics-stack.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tiktok-analytics-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tiktok-analytics-stack.labels" -}}
helm.sh/chart: {{ include "tiktok-analytics-stack.chart" . }}
{{ include "tiktok-analytics-stack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.argocd.labels }}
{{- range $key, $value := .Values.argocd.labels }}
{{- if $value }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
ArgoCD annotations
*/}}
{{- define "tiktok-analytics-stack.argocd.annotations" -}}
{{- if .Values.argocd.annotations }}
{{- range $key, $value := .Values.argocd.annotations }}
{{- if $value }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tiktok-analytics-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tiktok-analytics-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service name for backend
*/}}
{{- define "tiktok-analytics-stack.backend.serviceName" -}}
{{- printf "%s-backend" (include "tiktok-analytics-stack.fullname" .) }}
{{- end }}

{{/*
Service name for backend canary
*/}}
{{- define "tiktok-analytics-stack.backend.canaryServiceName" -}}
{{- printf "%s-backend-canary" (include "tiktok-analytics-stack.fullname" .) }}
{{- end }}

{{/*
Service name for UI
*/}}
{{- define "tiktok-analytics-stack.ui.serviceName" -}}
{{- printf "%s-ui" (include "tiktok-analytics-stack.fullname" .) }}
{{- end }}

{{/*
Service name for database
*/}}
{{- define "tiktok-analytics-stack.db.serviceName" -}}
{{- printf "%s-db" (include "tiktok-analytics-stack.fullname" .) }}
{{- end }}

{{/*
Database connection URL
Note: Password will be injected via environment variable reference
*/}}
{{- define "tiktok-analytics-stack.db.url" -}}
{{- $dbName := .Values.database.postgres.db | default "tiktok" }}
{{- $dbUser := .Values.database.postgres.user | default "postgres" }}
{{- $dbHost := include "tiktok-analytics-stack.db.serviceName" . }}
{{- $dbPort := .Values.database.postgres.port | default 5432 | int }}
{{- printf "postgresql://%s:$(POSTGRES_PASSWORD)@%s:%d/%s" $dbUser $dbHost $dbPort $dbName }}
{{- end }}

{{/*
Service name for redis
*/}}
{{- define "tiktok-analytics-stack.redis.serviceName" -}}
{{- printf "%s-redis" (include "tiktok-analytics-stack.fullname" .) }}
{{- end }}

{{/*
Redis image
*/}}
{{- define "tiktok-analytics-stack.redis.image" -}}
{{- printf "redis:%s" (.Values.redis.version | default "7-alpine") }}
{{- end }}

{{/*
Redis connection URL
Note: Password will be injected via environment variable reference
*/}}
{{- define "tiktok-analytics-stack.redis.url" -}}
{{- $redisHost := include "tiktok-analytics-stack.redis.serviceName" . }}
{{- $redisPort := .Values.redis.port | default 6379 | int }}
{{- $redisDb := .Values.redis.db | default 0 | int }}
{{- printf "redis://:$(REDIS_PASSWORD)@%s:%d/%d" $redisHost $redisPort $redisDb }}
{{- end }}

{{/*
Backend image
*/}}
{{- define "tiktok-analytics-stack.backend.image" -}}
{{- printf "%s:%s" .Values.backend.image.repository (.Values.backend.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
UI image
*/}}
{{- define "tiktok-analytics-stack.ui.image" -}}
{{- printf "%s:%s" .Values.ui.image.repository (.Values.ui.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Database image
*/}}
{{- define "tiktok-analytics-stack.db.image" -}}
{{- printf "postgres:%s" (.Values.database.postgres.version | default "16-alpine") }}
{{- end }}

{{/*
Backend computed environment variables (secrets + auto-generated URLs).
Shared across: backend-rollout, worker-deployment.
*/}}
{{- define "tiktok-analytics-stack.backend.computedEnv" -}}
- name: PYTHONPATH
  value: "/app"
{{- if .Values.database.enabled }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "tiktok-analytics-stack.fullname" . }}-db-secret
      key: postgres-password
{{- end }}
{{- if .Values.redis.enabled }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "tiktok-analytics-stack.fullname" . }}-redis-secret
      key: redis-password
{{- end }}
- name: PHOVEUS_BACKEND_JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "tiktok-analytics-stack.fullname" . }}-backend-secret
      key: jwt-secret
- name: PHOVEUS_BACKEND_DATABASE_URL
  value: {{ .Values.backend.env.PHOVEUS_BACKEND_DATABASE_URL | default (include "tiktok-analytics-stack.db.url" .) | quote }}
{{- if or .Values.redis.enabled .Values.backend.env.PHOVEUS_BACKEND_REDIS_URL }}
- name: PHOVEUS_BACKEND_REDIS_URL
  value: {{ .Values.backend.env.PHOVEUS_BACKEND_REDIS_URL | default (include "tiktok-analytics-stack.redis.url" .) | quote }}
{{- end }}
- name: PHOVEUS_BACKEND_DOMAIN_UI
{{- if .Values.backend.env.PHOVEUS_BACKEND_DOMAIN_UI }}
  value: {{ .Values.backend.env.PHOVEUS_BACKEND_DOMAIN_UI | quote }}
{{- else if .Values.global.domain.ui }}
  value: {{ printf "http://%s" .Values.global.domain.ui | quote }}
{{- else }}
  value: ""
{{- end }}
{{- include "tiktok-analytics-stack.backend.env" . }}
{{- end }}

{{/*
Database validation - fails if database is disabled without an external URL.
Call at the top of any template that needs database access.
*/}}
{{- define "tiktok-analytics-stack.backend.validateDatabase" -}}
{{- if and (not .Values.database.enabled) (not .Values.backend.env.PHOVEUS_BACKEND_DATABASE_URL) }}
{{- fail "ERROR: database.enabled=false but PHOVEUS_BACKEND_DATABASE_URL is empty. You must provide an external database URL when the internal database is disabled." }}
{{- end }}
{{- end }}

{{/*
Backend environment variables - iterate over env map (prefixes already included)
Skips empty values and special computed vars (PHOVEUS_BACKEND_DATABASE_URL, PHOVEUS_BACKEND_REDIS_URL, PHOVEUS_BACKEND_DOMAIN_UI, PHOVEUS_BACKEND_JWT_SECRET)
*/}}
{{- define "tiktok-analytics-stack.backend.env" -}}
{{- range $key, $value := .Values.backend.env }}
{{- if and $value (ne $key "PHOVEUS_BACKEND_DATABASE_URL") (ne $key "PHOVEUS_BACKEND_REDIS_URL") (ne $key "PHOVEUS_BACKEND_DOMAIN_UI") (ne $key "PHOVEUS_BACKEND_JWT_SECRET") }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
UI environment variables - iterate over env map (prefixes already included)
Skips VITE_API_BASE_URL (handled separately)
*/}}
{{- define "tiktok-analytics-stack.ui.env" -}}
{{- range $key, $value := .Values.ui.env }}
{{- if ne $key "VITE_API_BASE_URL" }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate checksum of environment variables to force pod restart on config changes
*/}}
{{- define "tiktok-analytics-stack.backend.envChecksum" -}}
{{- $envJson := .Values.backend.env | toJson }}
{{- $secretHash := .Values.secrets.jwtSecret | default "" | toString | sha256sum | trunc 8 }}
{{- printf "%s-%s" ($envJson | sha256sum | trunc 8) $secretHash }}
{{- end }}

{{- define "tiktok-analytics-stack.ui.envChecksum" -}}
{{- .Values.ui.env | toJson | sha256sum | trunc 8 }}
{{- end }}

{{/*
AnalysisTemplate name for backend
*/}}
{{- define "tiktok-analytics-stack.backend.analysisTemplateName" -}}
{{- printf "%s-backend-health-check" (include "tiktok-analytics-stack.fullname" .) }}
{{- end }}

{{/*
Determine storage class name with fallbacks.
*/}}
{{- define "tiktok-analytics-stack.storageClass" -}}
  {{- if (lookup "storage.k8s.io/v1" "StorageClass" "" "nfs-client") -}}
    {{- "nfs-client" -}}
  {{- else if .Values.global.storage.storageClassName -}}
    {{- .Values.global.storage.storageClassName -}}
  {{- else -}}
    {{- "" -}}
  {{- end -}}
{{- end -}}
