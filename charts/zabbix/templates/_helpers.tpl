{{- define "chart-name" -}}
{{- printf "%s%s" .Chart.Name .Release.Name -}}
{{- end -}}

{{- define "zabbix-mariadb-chart.image" -}}
{{- printf "%s:%s" .Values.images.repository .Values.images.tag | quote -}}
{{- end -}}

{{- define "zabbix-mariadb-chart.pullPolicy" -}}
{{- default "IfNotPresent" .Values.images.pullPolicy | quote -}}
{{- end -}}

{{- define "zabbix-mariadb-chart.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "zabbix-mariadb-chart.dbServer" -}}
{{- printf "%s-mariadb" (include "chart-name" .) | quote -}}
{{- end -}}

{{- define "zabbix-mariadb-chart.zabbixServerHostname" -}}
{{- printf "%s-server" (include "chart-name" .)  | quote -}}
{{- end -}}