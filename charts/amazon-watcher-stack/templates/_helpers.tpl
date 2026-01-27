{{/*
Expand the name of the chart.
*/}}
{{- define "amazon-watcher-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "amazon-watcher-stack.fullname" -}}
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
{{- define "amazon-watcher-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "amazon-watcher-stack.labels" -}}
helm.sh/chart: {{ include "amazon-watcher-stack.chart" . }}
{{ include "amazon-watcher-stack.selectorLabels" . }}
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
{{- if .Values.argocd.tags }}
{{- range $key, $value := .Values.argocd.tags }}
{{- if $value }}
{{- if eq $key "environment" }}
app.maborak.com/environment: {{ $value | quote }}
{{- else if eq $key "team" }}
app.maborak.com/team: {{ $value | quote }}
{{- else if eq $key "project" }}
app.maborak.com/project: {{ $value | quote }}
{{- else }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
ArgoCD annotations
*/}}
{{- define "amazon-watcher-stack.argocd.annotations" -}}
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
{{- define "amazon-watcher-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "amazon-watcher-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service name for backend
*/}}
{{- define "amazon-watcher-stack.backend.serviceName" -}}
{{- printf "%s-backend" (include "amazon-watcher-stack.fullname" .) }}
{{- end }}

{{/*
Service name for backend canary
*/}}
{{- define "amazon-watcher-stack.backend.canaryServiceName" -}}
{{- printf "%s-backend-canary" (include "amazon-watcher-stack.fullname" .) }}
{{- end }}

{{/*
Service name for UI
*/}}
{{- define "amazon-watcher-stack.ui.serviceName" -}}
{{- printf "%s-ui" (include "amazon-watcher-stack.fullname" .) }}
{{- end }}

{{/*
Service name for screenshot
*/}}
{{- define "amazon-watcher-stack.screenshot.serviceName" -}}
{{- printf "%s-screenshot" (include "amazon-watcher-stack.fullname" .) }}
{{- end }}

{{/*
Service name for database
*/}}
{{- define "amazon-watcher-stack.db.serviceName" -}}
{{- printf "%s-db" (include "amazon-watcher-stack.fullname" .) }}
{{- end }}

{{/*
Database connection URL
Note: Password will be injected via environment variable reference
*/}}
{{- define "amazon-watcher-stack.db.url" -}}
{{- $dbName := .Values.database.postgres.db | default "amazon_watcher" }}
{{- $dbUser := .Values.database.postgres.user | default "amazon_watcher" }}
{{- $dbHost := include "amazon-watcher-stack.db.serviceName" . }}
{{- $dbPort := .Values.database.postgres.port | default 5432 | int }}
{{- printf "postgresql://%s:$(POSTGRES_PASSWORD)@%s:%d/%s" $dbUser $dbHost $dbPort $dbName }}
{{- end }}

{{/*
Backend image
*/}}
{{- define "amazon-watcher-stack.backend.image" -}}
{{- printf "%s:%s" .Values.backend.image.repository (.Values.backend.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Backend image Dev
*/}}
{{- define "amazon-watcher-stack.backend.image-dev" -}}
{{- printf "%s:%s-dev" .Values.backend.image.repository (.Values.backend.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
UI image
*/}}
{{- define "amazon-watcher-stack.ui.image" -}}
{{- printf "%s:%s" .Values.ui.image.repository (.Values.ui.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Screenshot image
*/}}
{{- define "amazon-watcher-stack.screenshot.image" -}}
{{- printf "%s:%s" .Values.screenshot.image.repository (.Values.screenshot.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Database image
*/}}
{{- define "amazon-watcher-stack.db.image" -}}
{{- printf "postgres:%s" (.Values.database.postgres.version | default "16-alpine") }}
{{- end }}

{{/*
Backend environment variables - iterate over env map (prefixes already included)
Skips empty values and special computed vars (APT_BACKEND_DATABASE_URL, APT_BACKEND_SCREENSHOT_SERVICE_URL, DOMAIN_UI)
*/}}
{{- define "amazon-watcher-stack.backend.env" -}}
{{- range $key, $value := .Values.backend.env }}
{{- if and $value (ne $key "APT_BACKEND_DATABASE_URL") (ne $key "APT_BACKEND_SCREENSHOT_SERVICE_URL") (ne $key "DOMAIN_UI") }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
UI environment variables - iterate over env map (prefixes already included)
Skips VITE_API_BASE_URL (handled separately)
*/}}
{{- define "amazon-watcher-stack.ui.env" -}}
{{- range $key, $value := .Values.ui.env }}
{{- if ne $key "VITE_API_BASE_URL" }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Screenshot environment variables - iterate over env map (prefixes already included)
*/}}
{{- define "amazon-watcher-stack.screenshot.env" -}}
{{- range $key, $value := .Values.screenshot.env }}
{{- if $value }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate checksum of environment variables to force pod restart on config changes
*/}}
{{- define "amazon-watcher-stack.backend.envChecksum" -}}
{{- $envJson := .Values.backend.env | toJson }}
{{- $secretHash := .Values.secrets.jwtSecret | default "" | toString | sha256sum | trunc 8 }}
{{- printf "%s-%s" ($envJson | sha256sum | trunc 8) $secretHash }}
{{- end }}

{{- define "amazon-watcher-stack.ui.envChecksum" -}}
{{- .Values.ui.env | toJson | sha256sum | trunc 8 }}
{{- end }}

{{- define "amazon-watcher-stack.screenshot.envChecksum" -}}
{{- .Values.screenshot.env | toJson | sha256sum | trunc 8 }}
{{- end }}
