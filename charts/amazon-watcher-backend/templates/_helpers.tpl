{{- define "chart-name" -}}
{{- printf "%s%s" .Chart.Name .Release.Name -}}
{{- end -}}

{{- define "amazon-watcher-backend.image" -}}
{{- if and .Values.images.tag (ne .Values.images.tag "") -}}
{{- printf "%s:%s" .Values.images.repository .Values.images.tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.images.repository .Chart.AppVersion -}}
{{- end -}}
{{- end -}}
