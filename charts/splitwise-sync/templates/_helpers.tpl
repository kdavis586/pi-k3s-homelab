{{/*
Expand the name of the chart.
*/}}
{{- define "splitwise-sync.name" -}}
{{- .Chart.Name }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "splitwise-sync.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "splitwise-sync.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
