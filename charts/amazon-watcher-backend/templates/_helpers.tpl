{{- define "amazon-watcher-backend.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "amazon-watcher-backend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "amazon-watcher-backend.labels" -}}
helm.sh/chart: {{ include "amazon-watcher-backend.chart" . }}
{{ include "amazon-watcher-backend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "amazon-watcher-backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "amazon-watcher-backend.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "amazon-watcher-backend.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}

{{- define "amazon-watcher-backend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "amazon-watcher-backend.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end -}}

