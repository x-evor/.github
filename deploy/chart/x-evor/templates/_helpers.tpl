{{- define "x-evor.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "x-evor.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "x-evor.labels" -}}
app.kubernetes.io/name: {{ include "x-evor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
